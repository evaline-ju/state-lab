# state-lab — agent instructions (short version)

Demos repo for the Rossoctl agentic platform: runnable demos organized by track under
`docs/demos/`. The full conventions are in [`CLAUDE.md`](CLAUDE.md) — read it before
changing anything. The rules that matter most:

- A demo is **runnable from its README alone**; `setup.sh`/`teardown.sh` bracket
  anything with side effects.
- Measured results go in the track's `FINDINGS.md` — append-only, never rewritten.
- Adding a demo means adding its row to the track README's table.
- **Never commit secrets or local state** (kubeconfigs, `.env*`, `.claude/`).
- Commits: conventional subjects; trailer is **`Assisted-By:`**, not
  `Co-Authored-By:` (no hook enforces it here — add it yourself).
