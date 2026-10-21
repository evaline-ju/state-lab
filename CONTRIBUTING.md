# Contributing to state-lab

The **contribution process** — how to claim an issue, how review works, how to become a
maintainer, and the code of conduct — is documented once for the whole project in
[`rossoctl/rossoctl`](https://github.com/rossoctl/rossoctl/blob/main/CONTRIBUTING.md). See
[`GOVERNANCE.md`](GOVERNANCE.md) for the full index.

This file covers only what is **specific to this repo**: how to run its demos and what
its conventions are.

## Prerequisites

- bash
- [pre-commit](https://pre-commit.com/#install) (git hooks)
- Per-demo prerequisites (docker, kind, a harness, …) are listed in each demo's README —
  a demo that needs something says so at the top.

## Setup

```sh
git clone https://github.com/rossoctl/state-lab.git
cd state-lab

# Install the git hooks (gitleaks secret scanning).
pre-commit install
```

## Running and checking

There is nothing to build and no test suite: **demos are run, not tested**. A demo's
README is its plan — prerequisites, `setup.sh`, what to observe, `teardown.sh`. A demo
is considered Validated when someone other than its author has run its README end to
end.

```sh
pre-commit run --all-files   # gitleaks — the only automated gate
```

## Adding a demo

Demos live under [`docs/demos/`](docs/demos/), one directory per track. The pattern:

```
docs/demos/<track>/
├── README.md      # the track's question + a table of its demos, with status
├── FINDINGS.md    # measured results — append-only, never rewritten
├── scratch.md     # unformed ideas, promoted into demo dirs when built
└── <demo>/        # README (entry point) + setup.sh/teardown.sh + code
```

When you add a demo, add its row to the track README's table. Record what you measured
in `FINDINGS.md`, not in the demo's README — a README makes claims, FINDINGS records
what actually happened.

## Commits

- Conventional-commit style subject (`feat:`, `fix:`, `docs:`, `chore:`).
- The trailer is **`Assisted-By:`**, not `Co-Authored-By:`. There is no hook rewriting
  it in this repo — write it correctly the first time.

---

_Assisted-By: GLM 5.3_
