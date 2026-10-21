# state-lab

This repo collects a set of demo flows exercising various state requirements, from
durability to passability.

Agents are becoming more distributed — cooperating processes spread across machines,
sessions, and lifetimes (see the [moca](https://github.com/rossoctl/moca) repo) — and
increasingly externalize their state into files, stores, and services rather than
their own context windows. Once state lives outside the agent, the hard questions
land on the platform: where does state live, who owns it, what happens when a process
dies mid-task, or when two agents disagree about what's true?

Demos live under [`docs/demos/`](docs/demos/), organized by **track**: one directory per
line of inquiry, each demo inside it self-contained.

## Tracks

| Track | What it explores | Status |
| ----- | ---------------- | ------ |
| [`TODO-track`](docs/demos/TODO-track/) | TODO | Stub |

<!-- One row per track. Rename TODO-track/ once the first track is named. -->

## Working here

- Each demo is a self-contained directory; its README is the entry point.
- AI agents: [`AGENTS.md`](AGENTS.md) carries the conventions — read natively by
  Claude Code, pi, and Codex.

## Contributing and governance

This is a line of research, not a platform component — but it still runs on project
conventions: [`GOVERNANCE.md`](GOVERNANCE.md) indexes the project-wide documents, and
[`CONTRIBUTING.md`](CONTRIBUTING.md) covers this repo's setup.

## License

Apache-2.0 — see [LICENSE](LICENSE).

---

_Assisted-By: GLM 5.3_
