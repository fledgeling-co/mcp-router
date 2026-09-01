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

## A note on `uia-shell-discover.json`

It is committed, and its size moves a lot between runs — 1.5 MB on one early run against 90 KB on
the recorded one. The Discover board realises a store rail whose contents depend on what the
fixture lane holds, so its tree is the one dump here that is not roughly constant. If a future run
produces another very large one, that is the board being populated rather than the lane
misbehaving.

Nothing has been dropped from this directory. If something is ever left out, the reason belongs
here rather than in a `.gitignore`, because a silently absent artifact and a deliberately absent
one look identical to the next reader.
