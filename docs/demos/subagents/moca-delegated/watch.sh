#!/usr/bin/env bash
# Follow the demo from a side terminal: prints one line per change to this
# demo's workloads (StatefulSet, pods, status) and leaves (ledger rows and
# state). Run it alongside the parent agent; Ctrl-C to stop.
#
# Polls the same sources as the README's "Peek at" commands: kubectl in
# moca-sandbox and `mocactl subagents` / `mocactl workloads get`. Only leaves
# submitted after the script starts are shown (WATCH_SINCE_MS overrides).

set -euo pipefail

KIND_CLUSTER="${KIND_CLUSTER:-moca}"
KUBE_CONTEXT="kind-${KIND_CLUSTER}"
SANDBOX_NS="${SANDBOX_NS:-moca-sandbox}"
HARNESS_PORT="${HARNESS_PORT:-18080}"
CP_PORT="${CP_PORT:-18090}"
SCRATCH_DIR="${SCRATCH_DIR:-$HOME/tmp/moca-chained-scratch}"
INTERVAL="${INTERVAL:-3}"
TAG="moca-chained-subagents-demo"
WATCH_SINCE_MS="${WATCH_SINCE_MS:-$(($(date +%s) * 1000))}"

export SH_CONTROL_PLANE_URL="${SH_CONTROL_PLANE_URL:-http://127.0.0.1:${CP_PORT}}"
export SH_HARNESS_URL="${SH_HARNESS_URL:-http://127.0.0.1:${HARNESS_PORT}}"

for bin in kubectl mocactl jq; do
  command -v "${bin}" >/dev/null 2>&1 || { echo "${bin} not on PATH" >&2; exit 1; }
done

STATE_DIR="$(mktemp -d)"
trap 'rm -rf "${STATE_DIR}"' EXIT
PREV="${STATE_DIR}/prev"
CUR="${STATE_DIR}/cur"
: >"${PREV}"

say() { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

# One line per fact; a line that is new since the last poll is an event.
#   sts <wl> <statefulset> <mount>
#   pod <wl> <pod> <phase> <ready>
#   leaf <sessionId> <label> <wl> <bundle> <state>
# Bundles are named from the digests setup.sh wrote to MOCA.md.
digest() {
  grep -E "^Config digest $1:" "${SCRATCH_DIR}/MOCA.md" 2>/dev/null | awk '{print $NF}' | head -1 || true
}

snapshot() {
  kubectl --context "${KUBE_CONTEXT}" -n "${SANDBOX_NS}" get statefulsets,pods \
    -l moca.dev/workload -o json 2>/dev/null | jq -r '
      .items[]
      | (.metadata.annotations["moca.dev/record-key"] // "" | split(":") | last) as $wl
      | if .kind == "StatefulSet" then
          "sts \($wl) \(.metadata.name) \(.metadata.annotations["moca.dev/mount"] // "-")"
        else
          "pod \($wl) \(.metadata.name) \(.status.phase)" +
          " \([.status.containerStatuses[]?.ready] | length > 0 and all)"
        end' || true
  mocactl subagents --tag "${TAG}" --json 2>/dev/null | jq -r --argjson since "${WATCH_SINCE_MS}" \
    --arg pub "$(digest public)" --arg full "$(digest full)" '
    .subagents[]
    | select(.submittedAt >= $since)
    | (.bundle // "-") as $b
    | (if $b == $pub and $pub != "" then "public-only"
       elif $b == $full and $full != "" then "full"
       else ($b | sub("^sha256:"; "") | .[0:12]) end) as $bundle
    | "leaf \(.sessionId) \(.label) \(.workload // "-") \($bundle) \(.state)\(if .detail then " (\(.detail))" else "" end)"' || true
}

workload_status() {
  mocactl workloads get "$1" --json 2>/dev/null |
    jq -r '"status \(.status), revision \(.revision // "-" | .[0:12])"' || echo "status unknown"
}

say "watching ${TAG} on ${KUBE_CONTEXT} (every ${INTERVAL}s; Ctrl-C to stop)"
created="exists"
while true; do
  snapshot | sort -u >"${CUR}"

  # StatefulSet lines first, so a workload is announced before its pod.
  comm -13 "${PREV}" "${CUR}" | sort -s -k1,1r | while read -r kind a b c d e rest; do
    case "${kind}" in
      sts) say "workload ${a}: StatefulSet ${b} ${created} (mount ${c}) — $(workload_status "${a}")" ;;
      pod) say "workload ${a}: pod ${b} ${c}, ready=${d}" ;;
      leaf)
        case "${e}" in
          queued | running) say "leaf ${b} (${a}) on ${c} [${d}]: ${e}${rest:+ ${rest}}" ;;
          *) say "leaf ${b} (${a}) on ${c} [${d}]: ${e}${rest:+ ${rest}} — collect: mocactl get ${a} --json" ;;
        esac
        ;;
    esac
  done
  comm -23 "${PREV}" "${CUR}" | while read -r kind a b _; do
    if [[ "${kind}" == sts ]] && ! grep -q "^sts ${a} " "${CUR}"; then
      say "workload ${a}: StatefulSet ${b} deleted"
    fi
  done

  mv "${CUR}" "${PREV}"
  created="created"
  sleep "${INTERVAL}"
done
