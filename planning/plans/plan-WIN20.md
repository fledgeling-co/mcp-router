# WIN20 — plan: build the channel before thirteen surfaces are built on it

Spec: `planning/specs/spec-WIN20.md` · Brief:
`planning/features-to-triage/WIN20-windows-automation-plane-for-the-test-campaign.md`

The order below is the order the work was done in, and the reason for it is that each step's output
is the next step's oracle. Building the harness first and the subject afterwards would have meant
grading a tree nobody had seen.

---

## The decision that shaped everything else

**WIN3 has landed no drawable window, so the subject had to be built here or the item could not
run.** The brief anticipates this and says to build a minimal WinUI probe and say plainly that is
what was measured.

The alternative considered and rejected was to measure a WPF or WinForms window instead, both of
which are far cheaper to start. It was rejected because it would answer the wrong question: the
brief's whole argument is that the *framework choice* decides whether the campaign can see anything,
and a WPF automation peer is not a WinUI one. A cheap measurement of the wrong framework is worse
than none, because it reads like an answer.

## The slices

| # | Slice | Why it is separate | Tier |
|---|---|---|---|
| 1 | a WinUI 3 probe window carrying DESIGN.md §11's vocabulary and the four states | the subject. Without it the harness has nothing real to read | build |
| 2 | `uia-dump.ps1` — an out-of-process tree reader that never activates | the channel | build |
| 3 | `probe-expectation.json` — the on-screen vocabulary, written by hand | the oracle. Generated from the XAML it would be unfalsifiable | build |
| 4 | `uia-assert.py` — grade a dump, with `unoracled` as a first-class outcome | the verdict, and the three-outcome discipline | build |
| 5 | `uia-selftest.py` — arm every assertion, both directions | without it, most of §4 is an unfireable absence-check | build |
| 6 | `probe-lane.ps1` + `run-probe-lane.ps1` — the session-0 refusal and the interactive bridge | discovered during slice 1; not foreseen | build |
| 7 | enrol in `scripts/windows/verify.ps1` | an oracle enrolled in nothing is evidence nobody re-runs (WIN17's finding, quoted in that lane) | build |
| 8 | the registry rows, as a proposal | `campaign.py` cannot run here; see spec §8 | doc |

Slice 6 was not in the plan when the work started. It was forced by measurement: the first probe
launch died with `STATUS_STOWED_EXCEPTION` and the first UIA walk returned an empty list, both
because an agent shell here sits in session 0. Those two failures compose into a lane that would
report green over nothing, which is the failure mode this repository is organised around, so the
refusal became a deliverable rather than a workaround.

## Test strategy

There are two levels and they check different things.

**The lane** (`run-probe-lane.ps1`) answers *does this framework publish what the campaign needs*.
It runs the subject, reads it, and grades it. Green twice with identical figures is the bar; it was
met — 36 control-view elements, 65 raw, 85 passed, 0 failed, 2 unoracled, both runs.

**The selftest** (`uia-selftest.py`) answers *would the lane notice if it did not*. It is the more
important of the two, because most of what the lane asserts is a negative — the target never held
the foreground, no unselected item reports selected, no declared-unoracled control turned up — and a
negative check passes for free the moment it stops being able to fire. 23 arms, 18 required to exit
1, 4 required to exit 3, and one control requiring the real dump to trip nothing.

The four exit-3 arms are the load-bearing ones. An empty tree, an absent target window, a truncated
walk and a missing dump file all satisfy every name-and-state assertion trivially, and a gate that
returned 0 on any of them would be spending a green tick on a measurement that never happened.

## What is deferred, and to what

| Deferred | To | Why |
|---|---|---|
| pointing the harness at the product | WIN3 | there is no product window. The harness takes `-ProcessId` or `-TitleContains`; nothing about it is probe-specific |
| the thirteen Windows surfaces' own cases | WIN4–WIN16 | they stay `never-measured` until they exist. What changed is that the channel now exists |
| merging SURF-029 / REQ-036 / REQ-037 / CASE-0293…0296 (each has no row in any registry: proposed, not written) into the registry | a macOS run of `campaign.py` | the derived views cannot be regenerated on Windows |
| Narrator announcement | unscheduled | acceptance clause 6; the tree serves Narrator by construction but nothing here drove one |
| the CommandBar overflow finding | WIN3's construction | recorded as unoracled with the two conditions that would open a rung |
| geometry off the plane (bounding rectangles are captured but nothing asserts them) | when a Windows surface has a published geometry to check against | §12's geometry table is authored; no Windows surface exists to measure it on |
