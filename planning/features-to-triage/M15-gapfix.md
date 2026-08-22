# M15 gap-fix — four record defects, and the one product defect nothing guards

**Parent:** M15 · **Verdict:** Needs More Work, 2026-08-22 (first verification) · **Branch:** `ai/m15`

## What passed, and it is the build

Driven and measured on the running app: window chrome, seven pane rows, group and row read-back,
close pressed, `⌘,` posted — all without activating the app. Plus a rendered-window fidelity pass.
`make lint` **0 in 543 files**, `no-raw-design-values` **125 scanned / 84 geometry, clean**,
`make test` **1710 in 212**, `mac-shell.sh` **52/0**, `m8-settings-menubar.sh` **35/0** with
`SecurityAgent` frontmost throughout.

Escape and arrow-key traversal stay **open and that is accepted**: `.onExitCommand { dismiss() }`
ships at `SettingsWindow.swift:81`, and the null-instrument argument is the right shape — the
reading was negative both with and without the handler, which proves the instrument insensitive
rather than the product broken. `UI_VERIFICATION.md` rule 1 prescribes reporting such a check
rather than taking the screen. Requirement 11 to M18 is correct: no pane opens a sheet.

## BL-1 — the divergence list does not adjudicate its own findings

`mock-fidelity-gate.sh settings` exits 1 with **97 findings**, described as all inside four
declared divergences. By the manifest's own rule — *"a finding outside this list is a defect"* — at
least **12 are not**: eleven cite `spec-M15.md` §2 assumption 7 (the mock refuses the window while
the build keeps it live) and one cites M18's `Choose…`. Neither is in the numbered list.

**This is arm 6b's own subject one level up.** An allowance list that does not adjudicate is worse
than no list, because the next reader learns it is not authoritative — the same way a scanned-file
count that can fall without failing teaches a reader not to trust the denominator.

Add the router-stopped divergence as a fifth and the M18 handoff as a sixth, or reword the rule so
it says what it actually enforces. Do not widen a divergence to swallow findings it was not written
for.

## BL-2 — the wrong row count, in four places

The verifier found the mock's built/unbuilt row count wrong in four places, entering via §11's
narrowing 3. Correct all four, and use a **wrap-tolerant** sweep with a **presence control** on the
corrected figure — R17 spent four passes on a claim a line-anchored grep could not see, and G4's
gap-fix caught two broken sweeps only because it asserted the corrected text was present. An
absence check cannot detect its own blindness.

## BL-3 — the one product defect this item found by hand has no regression guard

M15 discovered two `Settings…` menu items both bound to `⌘,`: declaring the `Settings` scene
contributes the item, and `CommandGroup(replacing: .appSettings)` added a second. It removed that
block, which is right.

**Nothing would catch it coming back.** `mac-shell.sh`'s EXTRAS loop matches each item against the
inventory, so a *second identical item* passes. Give it a guard that counts rather than matches —
an item appearing twice, or two items sharing a chord, is the assertion.

## BL-4 — no acceptance evidence file

`planning/evidence/M15-acceptance.md` does not exist, against `UI_VERIFICATION.md` rule 2. M1, M2,
M3, M4, M11, M13, M14, M23 and M27 all carry one. It is the file that stops the next run
re-verifying screens already proven, and this item drove a lot of window.

## Also fix, small

`ShellCommandRouter.swift:62` and `:114` still say the menu item *"is a `SettingsLink`"*. None is
declared anywhere.

## The plan defects are the orchestrator's, and are recorded as such

- **D3 is half a defect.** It named the right discipline — measure before applying `⌘,` twice — and
  the **wrong failure mode**: it predicted a double-bound chord and directed creating
  `SettingsCommandItem.swift`, when declaring the scene contributes the whole item. The mechanism
  caught the real defect; the hypothesis was wrong and produced a file that had to be deleted.
- **B1/B6's "copy the file and keep the original"** is a redeclaration in one module and does not
  compile.
- **`MeasureDump` was called "already surface-generic" and is not** — one state name covers two
  conditions across surfaces, and the shared mapping would have rendered a live window under the
  stopped one's name and reported it as a measurement of the stopped one.

No action needed on these beyond leaving them recorded. They are findings about the plan's author.

## Acceptance

1. Every one of the 97 findings falls inside a declared divergence, or the rule is reworded to say
   what it enforces. State the count per divergence.
2. The row count is right in all four places, proven by a wrap-tolerant sweep with a presence
   control, both pasted.
3. A duplicate `Settings…` — or any two items sharing a chord — reddens a standing gate. Arm it.
4. `planning/evidence/M15-acceptance.md` exists per `UI_VERIFICATION.md` rule 2.
5. Gates unmoved, **measured at this base and pasted**: lint **0 over 543**, `make test`
   **1710 in 212**, `mac-shell.sh` **52/0**, `m8-settings-menubar.sh` **35/0**.

The reconciler exits 1 on check E naming `G5 (ai/g5)` from every worktree and **nothing was
merged** — recorded on `main` as a dispatch hazard and as G4's twelfth instance. The correct claim
is *clean apart from the known check-E false-RED*. Do not satisfy it by editing shared tracker
files.

## Scope

`planning/fidelity/settings.*`, the four row-count homes, one acceptance script, the two comment
lines, and a new `planning/evidence/M15-acceptance.md`. No change to the shipped `Settings` scene.
