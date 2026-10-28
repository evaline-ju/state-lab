# Demos — organized by track

A **track** is one line of inquiry — a question the demos probe from several angles.
A **demo** is a self-contained directory.

| Track | What it explores | Demos |
| ----- | ---------------- | ----- |
| [`subagents/`](subagents/) | Dispatching subagent work and the state it carries | 1 |

<!-- One row per track. -->

## The per-track pattern

```
<track>/
├── README.md      # the question, the angle of each demo, a table with status
└── <demo>/        # README (the entry point) + setup.sh/teardown.sh + code
```

Demo status vocabulary: **Sketch** → **Validated**. A demo is Validated when someone
other than its author has run its README end to end.

---

_Assisted-By: GLM 5.3_
