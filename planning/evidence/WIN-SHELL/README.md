# WIN-SHELL — the Windows shell on the automation plane

Written by `scripts/windows/uia/shell-lane.ps1`, run through
`scripts/windows/uia/run-shell-lane.ps1` so it lands on WinSta0. Regenerate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows/uia/run-shell-lane.ps1

## What is here

- `run/assert-report.json` — the graded result, one row per destination. This is the file
  `planning/goals/completion-gates.py winlive` reads and the one the campaign cases are
  generated from by `planning/test-campaign/bin/win-cases-from-lane.py`.
- `run/lane.log`, `run/lane.json` — the transcript and the one-line verdict.
- `run/uia-shell-<destination>.json` — the control-view tree as it stood *after* that
  destination was actuated. `uia-shell-settings.json` is the evidence behind DEF-076.

## What is deliberately not here

`run/uia-shell-discover.json` is not committed. On the recorded run it was 1.5 MB — the Discover
board realises a populated store rail, so its tree is an order of magnitude larger than the
others, and a file that size per run per commit is a cost the evidence does not need to carry.
Every claim made about `discover` rests on `assert-report.json`, which holds its title, element
count and tree fingerprint. Regenerate the full dump with the command above if the tree itself
is ever the question.

Nothing else was dropped. The omission is here rather than in a `.gitignore` because a silently
absent artifact and a deliberately absent one look identical to the next reader.
