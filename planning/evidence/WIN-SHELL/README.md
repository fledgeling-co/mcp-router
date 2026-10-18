# WIN-SHELL — the Windows shell on the automation plane

Written by `scripts/windows/uia/shell-lane.ps1`, run through
`scripts/windows/uia/run-shell-lane.ps1` so it lands on WinSta0. Regenerate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows/uia/run-shell-lane.ps1

## What is here

- `run/assert-report.json` — the graded result, one row per destination, plus a `controls` array
  from the lane's section 3b **control census**: the arm that names controls and reads their
  state. The destination sweep grades a board on whether the board CHANGED, which cannot tell
  seven sections of working switches from three inert ones — DEF-076 lived in exactly that gap.
  The census addresses controls by `AutomationId` (a name search returns the first element with
  that name anywhere in the tree, and the menu bar already holds a `Router`), reads the ids and
  labels it expects out of `SettingsPresentation.cs` rather than restating them, and finishes by
  toggling a switch through the plane and reading a *different* element — the board's state
  readout, rendered from the model — because that is the only difference an out-of-process reader
  can see between a bound control and an inert one. This is the file
  `planning/goals/completion-gates.py winlive` reads and the one the campaign cases are
  generated from by `planning/test-campaign/bin/win-cases-from-lane.py`.
- `run/lane.log`, `run/lane.json` — the transcript and the one-line verdict.
- `run/uia-shell-<destination>.json` — the control-view tree as it stood *after* that
  destination was actuated. `uia-shell-settings.json` is the evidence behind DEF-076.
- `run/uia-shell-discover-detail.json` — the tree with the Discover **detail dialog** open, which
  is the evidence behind DEF-075. It is the only dump here that the lane cannot always produce:
  the dialog opens behind a store row, and a store row exists only when the registry search
  returns something. When it does not, the census row reads `unoracled` and this file is whatever
  the last reachable run wrote. A stale one is worse than an absent one, so its `capturedAtUtc`
  is the field to check against `assert-report.json`'s before believing it.

## A note on `uia-shell-discover.json`

It is committed, and its size moves a lot between runs — 1.5 MB on one early run against 90 KB on
the recorded one. The Discover board realises a store rail whose contents depend on what the
fixture lane holds, so its tree is the one dump here that is not roughly constant. If a future run
produces another very large one, that is the board being populated rather than the lane
misbehaving.

Nothing has been dropped from this directory. If something is ever left out, the reason belongs
here rather than in a `.gitignore`, because a silently absent artifact and a deliberately absent
one look identical to the next reader.
