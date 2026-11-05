# Local coding agent driving chained MOCA subagents

A local coding agent (**Claude Code** or **OpenCode** — pick one with
`PARENT=claude|opencode`) runs on your laptop and has no built-in way
to offload work to the cloud. Its in-process subagent tool (`Task` for
Claude, `task` for OpenCode) runs in the same session. This demo
**denies that tool** and delegates instead through a skill that
dispatches an isolated leaf to [MOCA](https://github.com/rossoctl/moca)
via the official client **`mocactl`**.

Both parent agents use the same skill, `mocactl` commands and operator
prompts; only the config format differs (see
[parent-agent differences](#parent-agent-differences)). The operator,
not the skill, decides the orchestration. Here, prompts in sequence:

1. *"Dispatch a subagent to diagnose the failing test."* The parent
   packs the scratch dir, creates a workload, spawns a leaf against
   it, and returns.
2. Later: *"Check on that subagent and report the diagnosis."* The
   parent collects the result and surfaces the diagnosis.
3. *"Dispatch a fixer with that diagnosis."* Repeat the pattern, this
   time with a `--mount writable` workload so the fix leaf can edit
   and test.

Neither MOCA nor the skill knows about the chain: each leaf is an
independent session, and the parent agent composes the flow from the
operator's prompts.

## How state flows

Four pieces cooperate:

1. **The `moca-delegate-task` skill** — upstream MOCA's delegation
   skill, staged verbatim from `<moca>/skills/moca-delegate-task/`.
   Pack to `.moca-delegate/repo.context`, `workloads create`,
   `spawn`, poll `subagents`, `get --out results/`, then delete the
   workload and `.moca-delegate/`. Demo specifics (pack `.`, the tag,
   chaining) come from the operator's prompts.
2. **`mocactl`** — the official MOCA client. Owns all auth in
   `~/.config/mocactl`.
3. **Two promoted config bundles** — `bundles/public-only/` and
   `bundles/full/`, each a `.claude/skills/` tree uploaded by `mocactl
   promote` as a sha256-pinned bundle. Diagnose dispatches with
   public-only; fix with full. Setup writes both digests to `MOCA.md`;
   teardown deletes them.
4. **A denied in-process subagent tool** — the parent agent's config
   denies the built-in subagent (`Task` / `task`), forcing the model
   through the skill. Each `mocactl spawn` permission prompt confirms
   the work is going to MOCA.

Per-leaf lifecycle: pack cwd → `workloads create --sandboxes 1
--mount read-only|writable` →
`mocactl spawn … --config $DIGEST --workload $WID --tag
moca-chained-subagents-demo --label <label>` → **stop**. The server
runs the leaf to completion and stores the result for 24h, whether or
not the client is still connected. The parent collects with `mocactl
get <sid> --out results`, then deletes the workload (its StatefulSet
and PVC go with it).

Tracking state lives on the mocactl ledger (`mocactl subagents --tag
moca-chained-subagents-demo --json`: label, sessionId, workloadId,
bundle digest, state), so a resumed parent session rebuilds the chain
from it alone.

## Prerequisites

### Tools on your PATH

- `kind` ≥ 0.24.0 (its default CNI enforces NetworkPolicy, which is
  MOCA's sandbox isolation) with Kubernetes 1.30+ (the workload
  provisioner needs ValidatingAdmissionPolicy).
- `kubectl`, `docker` (or podman's `docker` CLI), `jq`, and `claude`
  (Claude Code) or `opencode` (OpenCode 1.19.x+, tested on 1.19.4).
- [`mocactl`](https://github.com/rossoctl/moca/tree/main/packages/mocactl)
  (Node 22+), tested on v0.10.0:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/rossoctl/moca/main/scripts/install-mocactl.sh | MOCACTL_VERSION=v0.10.0 sh
  ```
  `./setup.sh` refuses an older build (it probes for `workloads`,
  `--label`, `--sandboxes` and `--prompt-file`).
- [`contextctl`](https://github.com/rossoctl/context-service/releases/tag/v0.3.0)
  v0.3.0+, from the release tarballs or `make build` (writes
  `bin/contextctl`). v0.3.0 is the first `ctx pack` that skips
  `.claude/` and `.gitignore`'d files, which the skill relies on.

### Checkouts

Clone MOCA and Context Service side-by-side. MOCA needs submodules:

```bash
git clone --recurse-submodules https://github.com/rossoctl/moca
git clone https://github.com/rossoctl/context-service
```

Export `CLONE_DIR` as the parent of both checkouts (required, no
default); the scripts expect `$CLONE_DIR/moca` and
`$CLONE_DIR/context-service`.

```bash
export CLONE_DIR=<parent-of-both-checkouts>
```

The MOCA checkout must be at or after
[`v0.10.0`](https://github.com/rossoctl/moca/releases/tag/v0.10.0)
(`git -C moca checkout v0.10.0 && git -C moca submodule update`), which
deploys Valkey 9 as the session store.

Clone this repo alongside them; all remaining commands run from the
demo directory:

```bash
git clone https://github.com/rossoctl/state-lab "$CLONE_DIR/state-lab"
cd "$CLONE_DIR/state-lab/docs/demos/subagents/moca-delegated"
```

### Install the cluster-side pieces

```bash
SH_TEST_USERS=1 ./prereqs-install.sh
```

Safe to re-run. It:

- creates the kind cluster `moca` and runs MOCA's `deploy/k8s/setup.sh`
  with `SH_WORKLOAD_SANDBOXES=1` (the `moca-provisioner` behind
  `--sandboxes`) and a test-user login gated by `SH_TEST_USER_SECRET`
  (demo constant `state-lab-demo-secret`; no identity provider);
- points CoreDNS at `1.1.1.1` / `8.8.8.8` (podman's resolv.conf often
  lists an unreachable IPv6 nameserver first);
- builds the Context Service image and `kind load`s it
  (`ghcr.io/rossoctl/context-service` denies anonymous pulls);
- writes one placeholder token to both MOCA's `moca-context-service`
  Secret and Context Service's `context-service-control-plane` Secret,
  which it checks on every `/internal/v1` call;
- backgrounds three port-forwards, logging to
  `~/.local/state/moca-chained-demo/`: supervisor on
  `${HARNESS_PORT:-18080}`, control plane on `${CP_PORT:-18090}`,
  Context Service on `${CS_PORT:-19090}`. Re-run the script to restart
  them.

To change a port, export the variable before both `./prereqs-install.sh`
and `./setup.sh`.

### Log in (once per machine)

Log in as the test user the install step configured, and store an
Anthropic-compatible endpoint and token as your inference credential:

```bash
export ANTHROPIC_BASE_URL=<your-anthropic-base-url>
export ANTHROPIC_AUTH_TOKEN=<your-anthropic-auth-token>
export SH_CONTROL_PLANE_URL=http://127.0.0.1:18090
export SH_TEST_USER_SECRET=state-lab-demo-secret
# Leaves run on the harness default model, claude-opus-4-8. mocactl has no
# per-spawn model flag; SH_MODEL on the supervisor overrides the default.
MOCA_TEST_USER_SECRET="$SH_TEST_USER_SECRET" mocactl login --test-user 1
printf %s "$ANTHROPIC_AUTH_TOKEN" | mocactl credentials add anthropic \
  --host "$(printf %s "$ANTHROPIC_BASE_URL" | awk -F/ '{print $3}')" --kind bearer \
  --endpoint "$ANTHROPIC_BASE_URL"

mocactl doctor
```

`--kind bearer` sends `Authorization: Bearer`, which gateways such as
LiteLLM expect. For `api.anthropic.com` with an `sk-ant-api…` key, use
`--host api.anthropic.com --kind api-key --endpoint
https://api.anthropic.com` (MOCA rejects Bearer for API keys there).

`mocactl doctor` must pass before `./setup.sh`.

## Setup

From this directory:

```bash
./setup.sh                                                  # Claude Code (default)
PARENT=opencode ./setup.sh                                  # OpenCode
```

This:

1. Verifies the tools, the `mocactl` features above, and the `moca`
   namespace.
2. Runs `mocactl doctor` and probes Context Service's public URL.
3. Stages `~/tmp/moca-chained-scratch/` **as the project**: the fixture
   at the root, the parent agent's config (Claude Code's
   `.claude/settings.json` carries the port-forward URLs in `env`;
   OpenCode gets `.opencode/opencode.jsonc` plus a `run-opencode.sh`
   wrapper that exports them), the upstream skill verbatim, and a
   `.gitignore` that keeps `MOCA.md`, `.moca-delegate/` and `results/`
   out of `contextctl ctx pack .`.
4. Promotes `bundles/public-only/` and `bundles/full/` and writes both
   digests and the URLs to `MOCA.md`.

Workloads are created per leaf at dispatch, each with its own sandbox
pod and PVC under `moca-sandbox`, seeded from the frozen revision.

Overrides: `PARENT` (`claude` default, or `opencode`), `MOCA_NS`
(default `moca`), `HARNESS_PORT` / `CP_PORT` / `CS_PORT`,
`SCRATCH_DIR`.

> **Re-running setup discards the previous scratch dir**, so collect
> results first. The tag is constant, so `mocactl subagents --tag`
> shows old and new leaves together until `./teardown.sh`.

## Run a session

Claude Code:

```bash
cd ~/tmp/moca-chained-scratch && claude
```

OpenCode, through the wrapper that exports the URLs:

```bash
~/tmp/moca-chained-scratch/run-opencode.sh
```

In a side terminal, `./watch.sh` follows the run. Each line is tagged
with the subagent's label (`[diagnose]`, `[fix]`) and reports a
workload, sandbox or subagent state change, for subagents submitted
after it starts. A workload shows `[awaiting spawn]` until
`mocactl spawn` labels it.

For the "Peek at state" commands below:

```bash
cd ~/tmp/moca-chained-scratch
export SH_CONTROL_PLANE_URL=http://127.0.0.1:18090
export SH_HARNESS_URL=http://127.0.0.1:18080
```

**Prompt 1 — start the diagnosis.** Paste something like:

> Dispatch a diagnose subagent on its own read-only sandbox
> (`--sandboxes 1 --mount read-only`). Config: `$DIGEST_PUBLIC` (from
> `MOCA.md`), tag `moca-chained-subagents-demo`, label `diagnose`.
> Have the leaf use its `public-research` skill. End the turn after
> `mocactl spawn` — do not call `get`, `subagents`, or `sleep`.

The denied subagent tool pushes the parent agent to
`moca-delegate-task`: pack, `workloads create`, `spawn`.

*Peek at state:* look up the workload from the ledger:

```bash
WLID=$(mocactl subagents --tag moca-chained-subagents-demo --json \
  | jq -r '[.subagents[] | select(.label=="diagnose")] | sort_by(.submittedAt) | last | .workload')
mocactl workloads get "$WLID" --json | jq '{status,contextType,revision}'
```

`status` goes `creating → awaiting_upload → provisioning → ready`;
`revision` is the sha256 of the files.

*Peek at the pod and PVC:* with `--sandboxes`, `workloads create`
waits (up to 5 minutes) while the provisioner creates the StatefulSet
and seeds the PVC. In a side terminal:

```bash
kubectl -n moca-sandbox get pods,pvc,sts
```

Expect one pod, PVC and StatefulSet per live workload, plus the shared
pool `moca-sandbox-0/1`, which this demo doesn't use. `workloads
delete` removes them.

*Optional:* quit and relaunch the parent agent before prompt 2 to show
the chain survives (see [Pause and resume](#pause-and-resume)).

**Prompt 2 — collect the diagnosis**, any time within 24h:

> Check on that subagent and report the diagnosis.

The agent finds the `diagnose` row on the ledger and runs `mocactl
get <sessionId> --out results`. On `queued` it reports "still running"
and stops; on `responded` it surfaces `results/<sessionId>.text` and
should delete the workload (`./teardown.sh` catches any it leaves).

*Peek at state:*

```bash
SID=$(mocactl subagents --tag moca-chained-subagents-demo --json \
  | jq -r '[.subagents[] | select(.label=="diagnose")] | sort_by(.submittedAt) | last | .sessionId')
mocactl get "$SID" --json | jq .
```

`status` goes `queued → responded` (or `failed` / `paused`).

**Prompt 3 — start the fix.** After reviewing the diagnosis:

> Dispatch a fix subagent on its own writable sandbox (`--sandboxes 1
> --mount writable`). Config: `$DIGEST_FULL` (from `MOCA.md`), tag
> `moca-chained-subagents-demo`, label `fix`. Have the leaf use its
> `full-access-fix` skill, with the previous diagnosis verbatim as its
> prompt (use `--prompt-file` if your shell refuses the inline form).
> End the turn after `mocactl spawn` — do not call `get`, `subagents`,
> or `sleep`.

Edits land on the fix workload's own PVC.

**Prompt 4 — collect the fix result.**

> Check on it.

The agent collects the `fix` row, surfaces the diff and test output
(`Ran 1 test` / `OK`), and should delete the workload. Only prompt
text passes between the two leaves.

### Observe the chain

The tag spans runs; to see just the latest (newest `diagnose` and
after), filter by `submittedAt`:

```bash
TAG=moca-chained-subagents-demo
mocactl subagents --tag "$TAG" --json | jq '
  .subagents
  | [.[] | select(.label=="diagnose")] as $diag
  | ($diag | sort_by(.submittedAt) | last | .submittedAt) as $start
  | map(select(.submittedAt >= $start))
'
```

Each row's `bundle` is the sha256 of the posture it booted with
(`$DIGEST_PUBLIC` for diagnose, `$DIGEST_FULL` for fix). The tag is a
client-side ledger label, not a server-side identity.

While leaves run, in another terminal:

```bash
kubectl -n moca-sandbox get pods
kubectl -n moca logs -f deploy/moca-supervisor
```

The supervisor logs a JSON audit line per run event (identifiers
only, no prompt text or file contents); filter by sessionId:

```bash
SID=$(mocactl subagents --tag moca-chained-subagents-demo --json \
  | jq -r '[.subagents[] | select(.label=="diagnose")] | sort_by(.submittedAt) | last | .sessionId')
kubectl --context kind-moca -n moca logs deploy/moca-supervisor | \
  jq -c -R "fromjson? | select(.event==\"audit\" and .sessionId==\"$SID\")"
```

The only transcript is the leaf's final message
(`results/<sid>.text`), which is why `full-access-fix` requires
verbatim test output in it.

## Pause and resume

The server finishes the run whether or not anything local is still
connected, so you can quit the parent agent any time after a dispatch.
Relaunch it from the scratch dir and send the next prompt; it finds the
leaf on the ledger. To take stock first, ask:

> Any subagents still pending from an earlier session?

or run `mocactl subagents --tag moca-chained-subagents-demo --json |
jq .` yourself. The ledger is the resumable state, not the parent
agent's session.

**What survives and what doesn't:**

| Event | Result collectable? |
| --- | --- |
| Quit the parent agent | Yes |
| Reboot the laptop | Yes — the worker dies, the server finishes the run |
| Wait up to 24h | Yes (server-side result TTL) |
| Wait past 24h | No — the stored result is gone |
| Port-forwards down mid-leaf | Yes — the leaf still completes; restore the port-forward to collect |
| Supervisor restarts mid-leaf | No — reaped as `failed` / `owner_lost` within ~90 s; re-dispatch under a fresh `--label` |
| Workload pod killed mid-leaf | Depends — in-flight tool calls fail with `worker disconnected`; the StatefulSet recreates the pod on the same PVC. Check `mocactl get`; re-dispatch if it failed |
| `./teardown.sh` | No — deletes the sessions and any leftover workloads |

**Caveats.**

- **`unknown` is an infrastructure outcome, not a finding.** The
  server still reports `queued` but the local worker is gone (e.g.
  port-forward down at dispatch), or the status query failed.
  Re-dispatch under a fresh `--label`.
- **Leaves over five minutes show `running` until reconciled.** The
  worker's HTTP client gives up on `POST /v1/runs` at its default
  5-minute timeout; the run continues and `subagents` reconciles it.

## Teardown

```bash
./teardown.sh
```

Deletes the tag's sessions (making their results unreachable), any
workloads still on the ledger, the two config bundles, and the scratch
dir. MOCA, Context Service, the cluster, your login and the
port-forwards are left alone.

## Full uninstall

```bash
./prereqs-uninstall.sh
```

Runs `teardown.sh`, kills the port-forwards, and deletes the kind
cluster. Your `mocactl` login and the checkouts are left alone.

## Parent-agent differences

| Dimension | Claude Code | OpenCode |
| --- | --- | --- |
| Config dir | `.claude/` | `.opencode/` |
| Config file | `settings.json` (jq-merged by setup.sh) | `opencode.jsonc` (cp'd by setup.sh) |
| In-process subagent to deny | `Task` | `task` |
| Env injection | native (`settings.json` `env` key) | wrapper (`run-opencode.sh` exports then execs) |
| Project-level instructions | `CLAUDE.md` (not shipped — operator prompts carry the discipline) | `AGENTS.md` (not shipped — same shape) |
| Tested version | current Claude Code | 1.19.4 |

## Troubleshooting

Known failure modes, inspecting sandbox state, and the flow by hand:
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

## Security note

A throwaway local cluster with MOCA's auth on. The scratch dir holds no
secrets; tokens stay in `~/.config/mocactl`. The test-user secret and
the Context Service token are fixed demo values, so don't point this at
anything you care about.

Each workload has its own StatefulSet and PVC in `moca-sandbox`. The
provisioner holds the RBAC there; the control plane and harness don't.

## Files in this directory

```
README.md                  This file
TROUBLESHOOTING.md         Known failure modes, how to inspect sandbox state, and the
                           by-hand flow (acceptance test + fallback when the agent is stuck)
ARCHITECTURE.md            Components, dispatch/collect sequence, trust boundaries
prereqs-install.sh         Stands up MOCA + Context Service on a local kind cluster and
                           backgrounds the three port-forwards; see Prerequisites
prereqs-uninstall.sh       Runs teardown.sh, kills the port-forwards, deletes the kind cluster
setup.sh                   Checks prereqs, stages the scratch dir, promotes the bundles
teardown.sh                Deletes the demo's sessions, leftover workloads, bundles, scratch dir
watch.sh                   Follows workload, sandbox and subagent state changes by label
parents/                   Parent-agent-specific config staged by setup.sh:
  claude/settings.json.example      Claude Code permission policy + env injection
  opencode/opencode.jsonc.example   OpenCode permission policy
  opencode/run-opencode.sh.in       Launcher template — renders to run-opencode.sh with
                                    port-forward URLs substituted at setup time
example_repo/              Stdlib-only Python project with a renamed-API bug; copied to
                           the scratch root, so the parent's cwd is the project
bundles/                   `public-only/` (diagnose leaf) and `full/` (fix leaf), each a
                           `.claude/skills/` tree, the layout `mocactl promote` reads,
                           whichever parent agent dispatches
```

In the scratch dir after `setup.sh` (Claude Code):

```
~/tmp/moca-chained-scratch/   The fixture is copied here so the parent's cwd is the project to pack.
├── .claude/
│   ├── settings.json      Permission policy + port-forward env for mocactl
│   └── skills/
│       └── moca-delegate-task/SKILL.md   Upstream SKILL.md, verbatim
├── .git/                  So `.gitignore` is honored by `contextctl ctx pack`
├── .gitignore             Keeps MOCA.md, .moca-delegate/, results/ out of each leaf's workload
├── MOCA.md                Written by setup.sh — the two promoted config digests + run facts
├── README.md src/ tests/ vendor/ docs/   The fixture, at the scratch root
├── .moca-delegate/        Created per leaf by the agent — holds the packed .context (and prompt file for --prompt-file); removed after collection
└── results/               Created by the agent on `mocactl get --out results` — holds <sid>.text per collected leaf
```

With `PARENT=opencode`: `.claude/` is replaced by `.opencode/opencode.jsonc`
and `.opencode/skills/moca-delegate-task/SKILL.md`, and a `run-opencode.sh`
wrapper is added at the scratch root. Both are listed in `.gitignore` so
`contextctl ctx pack .` keeps them out of each leaf's workload.
