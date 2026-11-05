# Troubleshooting

Known failure modes, plus the by-hand flow — which doubles as the acceptance
test for the mechanics (if this sequence doesn't run clean in a plain
terminal, nothing above it is believable) and as the fallback when the agent
gets stuck.

## Known failure modes

- **`mocactl` can't reach the control plane / connection refused, or
  `mocactl login` fails with "the control plane closed the connection
  (a proxy idle timeout?)".** A port-forward isn't running, or its
  pinned pod rotated and the forward died mid-flight (common after any
  cluster-side restart). `prereqs-install.sh` backgrounds all three —
  supervisor on 18080, control plane on 18090, Context Service on 19090.
  Check they are up with
  `pgrep -f 'kubectl --context kind-moca .* port-forward'` (expect
  three PIDs) and that something is listening on each port
  (`lsof -nP -iTCP:18090 -sTCP:LISTEN`); tail the logs under
  `~/.local/state/moca-chained-demo/` for why one died — a `kubectl
  port-forward` process whose pod was replaced logs `error forwarding
  port … failed to find sandbox` and `lost connection to pod`, and may
  leave the local port in a half-closed state that blocks a naive
  restart. To restart cleanly, re-run `./prereqs-install.sh` (it kills
  stale forwards first); if a port is still bound,
  `lsof -nP -iTCP:<port> -sTCP:LISTEN -t | xargs -r kill -9` and
  re-run. Also make sure `SH_CONTROL_PLANE_URL` / `SH_HARNESS_URL` are
  exported (Claude Code inherits them via `.claude/settings.json`'s
  `env`; OpenCode inherits them only when launched via
  `./run-opencode.sh`).
- **`setup.sh` fails at doctor.** Follow the fix doctor prints for
  each failing check — it covers reachability, login, credentials,
  and the harness.
- **A dispatch fails at `mocactl workloads create` with "Context
  Service refused the upload".** Context Service's public URL may not
  be reachable from this host. Check the `moca-context-service`
  ConfigMap and that your port-forward (or whatever makes `public-url`
  reachable) is up. Setup probes this once at startup; a mid-run
  outage can trigger the same failure.
- **Port conflict with Rancher Desktop's lima SSH mux on `*:8080`.**
  The demo defaults the three port-forwards to `18080` / `18090` /
  `19090` to avoid this, and `prereqs-install.sh` passes
  `SH_PUBLIC_HARNESS_URL=http://127.0.0.1:${HARNESS_PORT}` to
  `deploy/k8s/setup.sh` so the control plane advertises the matching
  port. If you've set `HARNESS_PORT=8080` and see
  `the harness refused: 404 http_404` with `server: istio-envoy`,
  that's the mux — unset the override or pick a different port.
- **A supervisor restart mid-run.** The run is reaped as
  `failed` / `owner_lost` within ~30–100 s and `mocactl get` surfaces
  that terminal state; re-dispatch under a fresh `--label`.
- **`get` says `no session`.** Wrong session id, or the session was
  deleted / aged out past 24h.

## OpenCode-specific (`PARENT=opencode`)

- **OpenCode launched directly, mocactl fails with "missing
  control-plane URL".** OpenCode has no `settings.json` `env`
  equivalent; the staged `run-opencode.sh` wrapper exports
  `SH_CONTROL_PLANE_URL` / `SH_HARNESS_URL` before execing opencode.
  Either launch via `./run-opencode.sh` from the scratch dir, or
  `export` the two URLs by hand first (recorded in `MOCA.md`).
- **A compound shell command is auto-rejected under `opencode run`**
  with `permission requested: external_directory (/var/folders/...)`.
  OpenCode gates any shell operation on paths outside the project
  root. The upstream skill packs into `.moca-delegate/` and collects
  into `results/`; if the agent strays to `/tmp`, tell it to use those.

## Inspecting state in the sandbox

A read-only workload never changes. A `--mount writable` workload
keeps the fix leaf's edits on its own PVC until `workloads delete`,
but they never reach your working tree. The leaf's final message is
the record of what it did — if you want a diff or test output, the
prompt must ask for it as text (the `full-access-fix` skill and the
templates in "Running the flow by hand" below already do).

To inspect a workload, look up its id from the ledger and use
`mocactl workloads get <workloadId>` — only before the agent deletes
it after collection. `mocactl workloads list` shows every workload
still live for your login.

```bash
cd ~/tmp/moca-chained-scratch
mocactl subagents --tag moca-chained-subagents-demo
mocactl subagents --tag moca-chained-subagents-demo --json \
  | jq -r '[.subagents[] | select(.label=="diagnose")] | sort_by(.submittedAt) | last | .workload'
cat results/<sessionId>.text      # the collected result
```

## Running the flow by hand

What the parent agent is meant to run for each operator prompt,
without the agent noise — and the acceptance test for the mechanics:
this sequence must run clean in a plain terminal before anything else
is believed. Run it from a fresh `./setup.sh`.

```bash
cd ~/tmp/moca-chained-scratch

# mocactl reaches MOCA through the port-forwards (both must be up).
# Export the two URLs (setup.sh prints these; they're also in MOCA.md):
export SH_CONTROL_PLANE_URL=http://127.0.0.1:18090
export SH_HARNESS_URL=http://127.0.0.1:18080

# Constant tag — scopes `mocactl subagents --tag` and teardown to
# this demo's leaves on the machine-global ledger.
TAG=moca-chained-subagents-demo

# The two config digests promoted at setup time (both are in MOCA.md).
DIGEST_PUBLIC="$(grep -E '^Config digest public:' MOCA.md | awk '{print $NF}')"
DIGEST_FULL="$(grep -E '^Config digest full:'   MOCA.md | awk '{print $NF}')"
```

Packs, prompt files and collected results go where the
`moca-delegate-task` skill puts them: `.moca-delegate/` and `results/`,
both in the scratch dir's `.gitignore`, so `contextctl ctx pack .`
never ships them. The `latest` helper picks the newest ledger row for
a label (the tag is constant, so older runs share it):

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

The `public-research` skill (shipped by the public-only bundle) carries
the posture, the test command, the "no edits / stdlib-only / end with
the full report" rules, and the deliverable shape. The prompt only has
to name the task.

**2 — pack the project and create this leaf's workload** on its own
read-only sandbox:

```bash
contextctl ctx pack . -o .moca-delegate/diagnose.context
DIAG_WORKLOAD_ID="$(mocactl workloads create \
  --context .moca-delegate/diagnose.context \
  --sandboxes 1 --mount read-only --json | jq -r '.workloadId')"
```

**3 — dispatch it** with the public-posture config bundle via
`--config`, and `--label diagnose` so a resumed session can find it by
name. `--json` prints one line on stdout
(`{"type":"session","sessionId":"…","pid":…}`); diagnostics go to
stderr:

```bash
mocactl spawn --kind prompt --config "$DIGEST_PUBLIC" \
  --workload "$DIAG_WORKLOAD_ID" --tag "$TAG" --label diagnose \
  --prompt-file .moca-delegate/diagnose.prompt.txt --json
```

Then **stop**. The leaf is durable server-side; no sidecar note needed
— `mocactl subagents --tag "$TAG" --json` reads back the label,
sessionId, workloadId, bundle digest, and state. Durability spot-check
(worth doing once): Ctrl-C the supervisor's port-forward while the
leaf runs, restore it, and collect anyway — step 4 still works, because
the server finishes the run no matter what your laptop did.

**4 — collect** (later; re-run every minute or so until done — each
check is free and does not disturb the leaf):

```bash
SID="$(latest diagnose sessionId)"
WLID="$(latest diagnose workload)"
mocactl get "$SID" --out results --json
```

Branch on the printed `status`, not the exit code: `queued` (exit 1)
→ still running; `failed` or `paused` (exit 1) → reason on stderr;
`responded` (exit 0) → read the result and release the workload.
`responded` is the prompt-kind success — `solved` is the solve-kind
twin, and `mocactl subagents` calls both of them `done`:

```bash
cat results/"$SID".text
mocactl workloads delete "$WLID"
```

The diagnosis should name the renamed API: `src/greet.py` calls
`lib.old_name` while the vendored `vendor/lib/__init__.py` (v2.0.0)
exports only `new_name`. The sandbox image ships `python3` but no
`pip`; the project is stdlib-only, so `python3 -m unittest` runs
directly.

**5 — chain the fix leaf.** Author its prompt with the diagnosis
inlined **verbatim** (never point one leaf at another leaf's files —
each leaf has its own sandbox and disk):

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

The `full-access-fix` skill (shipped by the full bundle) carries the
testing convention, the src/-not-vendor/ rule, the "no pip" rule, and
the verbatim-test-output deliverable. The prompt only has to pass
through the prior leaf's diagnosis.

Pack a fresh workload for the fix leaf on its own writable sandbox
(`--mount writable`, so no `spawn --writable`), dispatch it with
`--label fix`, then collect and release. `get` exit 1 with "has not
finished yet" just means still running:

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

The report should say `src/greet.py` changed (`old_name` → `new_name`)
and that the tests pass. The edits stay on the fix workload's PVC until
`workloads delete` and never reach your working tree; the report's diff
is what you apply locally.

**6 — see the whole chain:**

```bash
mocactl subagents --tag "$TAG"
```

The newest `diagnose` and `fix` rows should show `done`; one that ran
over five minutes may show `running` until reconciled. `mocactl get` is
the source of truth: `responded` means it finished.

**7 — tear down:**

```bash
cd -   # back to the demo dir
./teardown.sh
mocactl sessions   # the demo's leaf sessions are gone
```

Re-dispatch after a failure (fresh label, fresh workload). The
diagnosis is still in `results/`, so re-author the prompt as in step 5:

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

Start a completely fresh chain (fresh scratch dir and config bundles; the tag stays the same):

```bash
./teardown.sh && ./setup.sh
```
