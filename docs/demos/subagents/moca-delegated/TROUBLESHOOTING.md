# Troubleshooting

Known failure modes, plus the flow by hand: the acceptance test for the
mechanics and the fallback when the agent gets stuck.

## Known failure modes

- **`mocactl` gets connection refused, or `login` says "the control
  plane closed the connection".** A port-forward died, usually because
  its pod was replaced (its log under `~/.local/state/moca-chained-demo/`
  says `lost connection to pod`). `pgrep -f 'kubectl --context kind-moca
  .* port-forward'` should show three PIDs. Re-run
  `./prereqs-install.sh`, which kills stale forwards first; if a port is
  still bound, `lsof -nP -iTCP:<port> -sTCP:LISTEN -t | xargs -r kill -9`
  and re-run. Also check `SH_CONTROL_PLANE_URL` / `SH_HARNESS_URL` are
  set (OpenCode only gets them via `./run-opencode.sh`).
- **`setup.sh` fails at doctor.** Follow the fix doctor prints for each
  failing check.
- **`workloads create` fails with "Context Service refused the
  upload".** The `public-url` in the `moca-context-service` ConfigMap
  isn't reachable from this host; check the 19090 port-forward.
- **`the harness refused: 404 http_404` with `server: istio-envoy`.**
  `HARNESS_PORT=8080` collides with Rancher Desktop's lima SSH mux on
  `*:8080`; use the default `18080` or another free port.
- **A supervisor restart mid-run.** The run is reaped as `failed` /
  `owner_lost` within ~90 s; re-dispatch under a fresh `--label`.
- **`get` says `no session`.** Wrong session id, or the session was
  deleted / aged out past 24h.

## OpenCode-specific (`PARENT=opencode`)

- **mocactl fails with "missing control-plane URL".** OpenCode was
  launched directly. Use `./run-opencode.sh`, or export the two URLs
  from `MOCA.md` first.
- **`permission requested: external_directory (/var/folders/...)`.**
  OpenCode blocks shell access outside the project root. If the agent
  strays to `/tmp`, point it back at `.moca-delegate/` and `results/`.

## Inspecting state in the sandbox

A read-only workload never changes. A writable one keeps the fix
leaf's edits on its PVC until `workloads delete`; they never reach your
working tree. The leaf's final message is the record, which is why
`full-access-fix` asks for the diff and test output in it.

`mocactl workloads list` shows your live workloads; `workloads get
<id>` shows one, until the agent deletes it.

```bash
cd ~/tmp/moca-chained-scratch
mocactl subagents --tag moca-chained-subagents-demo
mocactl subagents --tag moca-chained-subagents-demo --json \
  | jq -r '[.subagents[] | select(.label=="diagnose")] | sort_by(.submittedAt) | last | .workload'
cat results/<sessionId>.text      # the collected result
```

## Running the flow by hand

What the parent agent runs for each prompt, minus the agent. Start
from a fresh `./setup.sh`.

```bash
cd ~/tmp/moca-chained-scratch

export SH_CONTROL_PLANE_URL=http://127.0.0.1:18090
export SH_HARNESS_URL=http://127.0.0.1:18080

TAG=moca-chained-subagents-demo

DIGEST_PUBLIC="$(grep -E '^Config digest public:' MOCA.md | awk '{print $NF}')"
DIGEST_FULL="$(grep -E '^Config digest full:'   MOCA.md | awk '{print $NF}')"
```

Packs and prompts go in `.moca-delegate/`, results in `results/`
(both gitignored, so never packed). `latest` reads the newest ledger
row for a label:

```bash
mkdir -p .moca-delegate results
latest() { mocactl subagents --tag "$TAG" --json \
  | jq -r --arg l "$1" --arg f "$2" \
    '[.subagents[] | select(.label==$l)] | sort_by(.submittedAt) | last | .[$f]'; }
```

**1 — author the diagnose leaf's prompt:**

```bash
cat > .moca-delegate/diagnose.prompt.txt <<'EOF'
Use the public-research skill. The project's tests currently fail —
diagnose why. The relevant docs are under docs/upstream-refs/.
EOF
```

**2 — pack and create a read-only workload:**

```bash
contextctl ctx pack . -o .moca-delegate/diagnose.context
DIAG_WORKLOAD_ID="$(mocactl workloads create \
  --context .moca-delegate/diagnose.context \
  --sandboxes 1 --mount read-only --json | jq -r '.workloadId')"
```

**3 — dispatch** with the public-only bundle:

```bash
mocactl spawn --kind prompt --config "$DIGEST_PUBLIC" \
  --workload "$DIAG_WORKLOAD_ID" --tag "$TAG" --label diagnose \
  --prompt-file .moca-delegate/diagnose.prompt.txt --json
```

Then stop; the ledger holds the handles. To check durability once,
kill the supervisor port-forward while the leaf runs, restore it, and
collect anyway.

**4 — collect** (re-run until done):

```bash
SID="$(latest diagnose sessionId)"
WLID="$(latest diagnose workload)"
mocactl get "$SID" --out results --json
```

`queued` (exit 1, "has not finished yet") → still running; `failed` /
`paused` (exit 1) → reason on stderr; `responded` (exit 0) → done:

```bash
cat results/"$SID".text
mocactl workloads delete "$WLID"
```

The diagnosis should say `src/greet.py` calls `lib.old_name`, but the
vendored `vendor/lib/__init__.py` (v2.0.0) only exports `new_name`.

**5 — chain the fix leaf**, inlining the diagnosis verbatim (the fix
leaf can't see the diagnose leaf's disk):

```bash
DIAG="$(cat results/"$SID".text)"
cat > .moca-delegate/fix.prompt.txt <<EOF
Use the full-access-fix skill. A prior agent produced this diagnosis
of the failing tests:

------------------------------------------------------------------------
$DIAG
------------------------------------------------------------------------

Apply the fix and verify.
EOF
```

The bundles' skills carry the rules and deliverable shape, so the
prompts only name the task. Create a writable workload (no `spawn
--writable` needed), dispatch, collect, release:

```bash
contextctl ctx pack . -o .moca-delegate/fix.context
FIX_WORKLOAD_ID="$(mocactl workloads create \
  --context .moca-delegate/fix.context \
  --sandboxes 1 --mount writable --json | jq -r '.workloadId')"

mocactl spawn --kind prompt --config "$DIGEST_FULL" \
  --workload "$FIX_WORKLOAD_ID" --tag "$TAG" --label fix \
  --prompt-file .moca-delegate/fix.prompt.txt --json

FIX_SID="$(latest fix sessionId)"
mocactl get "$FIX_SID" --out results --json
cat results/"$FIX_SID".text
mocactl workloads delete "$FIX_WORKLOAD_ID"
rm -r .moca-delegate
```

The report should show `old_name` → `new_name` in `src/greet.py`, the
tests passing, and a diff to apply locally.

**6 — see the whole chain:**

```bash
mocactl subagents --tag "$TAG"
```

The newest `diagnose` and `fix` rows should show `done`.

**7 — tear down:**

```bash
cd -   # back to the demo dir
./teardown.sh
mocactl sessions   # the demo's leaf sessions are gone
```

Re-dispatch after a failure with a fresh label and workload:

```bash
mkdir -p .moca-delegate
# write .moca-delegate/fix2.prompt.txt as in step 5, then:
contextctl ctx pack . -o .moca-delegate/fix2.context
FIX2_WORKLOAD_ID="$(mocactl workloads create \
  --context .moca-delegate/fix2.context \
  --sandboxes 1 --mount writable --json | jq -r '.workloadId')"
mocactl spawn --kind prompt --config "$DIGEST_FULL" \
  --workload "$FIX2_WORKLOAD_ID" --tag "$TAG" --label fix2 \
  --prompt-file .moca-delegate/fix2.prompt.txt --json
```

Start over with a fresh scratch dir and bundles:

```bash
./teardown.sh && ./setup.sh
```
