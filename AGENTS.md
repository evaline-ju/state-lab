# state-lab — agent instructions

A line of research on state management for agents: demo flows exercising various state
requirements, from durability to passability, organized by track under `docs/demos/`.
Nothing here is a library or a service — each demo is a self-contained directory.

## Repository layout

```
state-lab/
├── docs/demos/            # all demos, one directory per track
│   ├── README.md          # the track index
│   └── <track>/
│       ├── README.md      # track overview + table of demos with status
│       └── <demo>/        # self-contained: README + scripts + manifests
└── AGENTS.md              # this file — the conventions
```

## Demo conventions

1. **`setup.sh` / `teardown.sh` bracket anything with side effects** — kind clusters,
   pods, port-forwards, files outside the demo directory.
2. **Adding a demo means adding its row** to the track README's table (name, what it
   demonstrates, status: Sketch → Validated).
3. **Keep demos self-contained.** No dependencies on other tracks; tooling shared
   within a track lives at the track root, never across tracks.
4. **Never commit secrets or local state.** Kubeconfigs, `.env*`, `*.key`, `.claude/`
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
