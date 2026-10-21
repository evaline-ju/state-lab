# state-lab — agent instructions

A line of research on state management for agents: demo flows exercising various state
requirements, from durability to passability, organized by track under `docs/demos/`.
Nothing here is a library or a service — everything is meant to be run by hand from
its README.

## Repository layout

```
state-lab/
├── docs/demos/            # all demos, one directory per track
│   ├── README.md          # the track index
│   └── <track>/
│       ├── README.md      # track overview + table of demos with status
│       ├── FINDINGS.md    # measured results — append-only
│       ├── scratch.md     # unformed ideas, promoted into demos when built
│       └── <demo>/        # self-contained: README + scripts + manifests
└── AGENTS.md              # this file — the conventions
```

## Demo conventions

1. **A demo is runnable from its README alone.** Prerequisites, setup, what to
   observe, teardown. If a step isn't written down, the demo doesn't have that step.
2. **`setup.sh` / `teardown.sh` bracket anything with side effects** — kind clusters,
   pods, port-forwards, files outside the demo directory.
3. **Adding a demo means adding its row** to the track README's table (name, what it
   demonstrates, status: Sketch → Validated).
4. **Measured numbers go in the track's `FINDINGS.md`**, append-only. A README makes
   claims; FINDINGS records what actually happened, including the failures.
5. **Keep demos self-contained.** No dependencies on other tracks; tooling shared
   within a track lives at the track root, never across tracks.
6. **Never commit secrets or local state.** Kubeconfigs, `.env*`, `*.key`, `.claude/`
   are gitignored — keep them that way. Demo settings that carry tokens are shipped
   as `*.example` files.

## Commits

- Conventional-commit subject (`feat:`, `fix:`, `docs:`, `chore:`).
- The trailer is **`Assisted-By:`**, not `Co-Authored-By:` — the org convention.
  There is no hook enforcing it in this repo; add it yourself.

## Checks

```sh
pre-commit run --all-files   # gitleaks — the only gate
```
