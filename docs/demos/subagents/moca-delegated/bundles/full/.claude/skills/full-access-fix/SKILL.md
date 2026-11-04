---
name: full-access-fix
description: Apply a diagnosed fix to a project and verify it against the organization's testing conventions. Assumes insider knowledge of how tests are expected to be run and what counts as a clean pass. Use this skill when the task is "take this diagnosis, make the fix stick."
---

# Full-access-fix posture

You are working as an insider on this project: you know the
organization's testing conventions, you can edit source freely in your
own writable copy, and you are expected to verify your work before
calling it done.

## Testing conventions (organization-standard)

- **Test command:** `python3 -m unittest discover -s tests`. This is
  the organization's standard for Python projects of this shape — no
  pytest, no third-party runner.
- **Clean pass:** the final line of output is `OK` after `Ran N tests
  in …s`. Any `FAILED` or `ERROR` line, even if preceded by `OK` for a
  subset, is a failure.
- **Reporting:** the full test output (verbatim) is part of the
  deliverable, not a summary. Reviewers want to see the exact lines
  the runner printed, including the `.` / `F` / `E` character stream.

## Scope and posture

- You MAY edit files under `src/`. That's the project's own code.
- You MUST NOT edit files under `vendor/` or any other dependency
  tree. Those are vendored external dependencies and changes there
  bypass the version pin. If the diagnosis says the fix is in
  `vendor/`, surface that as a problem rather than making the edit.
- You MUST NOT install or download anything. The project is
  stdlib-only; if it needed more, the diagnosis would have said so.

## How to work

1. **Read the diagnosis.** The prompt will include a prior agent's
   full report. Trust it as the specification of what needs to change
   — your job is to apply it, not re-diagnose.
2. **Record a baseline before editing.** From your current directory:
   `git init -q && git add -A && git commit -qm baseline`. This
   exists only so step 6 can produce a diff.
3. **Make the exact edit the diagnosis called for.** No extra cleanup,
   no drive-by refactors. One file, one line, as described.
4. **Run the test suite.** `python3 -m unittest discover -s tests`,
   from your current directory.
5. **Capture the full output verbatim.** Including the dot/E/F stream,
   the `Ran N tests in …s` line, and the trailing `OK` or `FAILED`.
6. **Capture the diff.** `git diff` — a unified diff with paths
   relative to the project root.

## About your workspace

Your working directory is this workload's own **writable** tree of
the project, on its own volume. The tree is **deleted with the
workload** once your result is collected; nothing exports it. Your
final message is the only record, and the operator applies your diff
from it.

## End-of-turn deliverable

End your turn with a report containing:

1. The exact change made (file, line number, before → after).
2. The full test output after your change (verbatim, from the first
   `.`/`E`/`F` character through the trailing `OK` / `FAILED` line).
3. The `git diff` output, verbatim, in a fenced `diff` block.

All three are required. A report without the verbatim test output is not
acceptable: it means the fix was never actually verified against the
organization's testing convention.
