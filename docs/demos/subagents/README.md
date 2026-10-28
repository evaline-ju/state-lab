# Subagents

How subagent work is dispatched, where its state lives, and what survives
when the parent agent dies.

## Demos

| Demo | Angle | Status |
| ---- | ----- | ------ |
| [`moca-delegated/`](moca-delegated/) | Local coding agent (Claude Code / OpenCode) delegates chained leaves to [MOCA](https://github.com/rossoctl/moca); each leaf is server-durable past parent death. | Validated |
