# M18 — twelve sheets, and the gate each decision gets

**Depends on:** M1. **Related:** M8 (quarantine is one of the twelve).
**Source:** `design/mcp-router-console.html`, PRD §9.7.

A sheet carries one decision together with the evidence for it. Twelve are drawn.

| Sheet | The decision | The evidence it shows |
|---|---|---|
| pair | trust a phone | QR, typed fallback, expiry, and what pairing grants and does not grant |
| reconcile | remove duplicate entries from a harness config | full unified diff of the real file, before/after counts |
| quarantine | let a changed tool be callable again | schema diff *and* description diff, with why it was held |
| readme | install or update a capability | rendered README, changelog, capability list (M19) |
| capability-delta | accept a version that asks for more | what the new version added, against what was approved |
| add-server | add an upstream by hand | the command as typed, resolved against the child PATH |
| add-marketplace | trust a source of skills | origin, owner, what it will be allowed to write |
| recommendation | act on an analyst finding | the grep hits with file and line, and the four-step judgement chain |
| queued-detail | approve what the phone queued | tool list, capability summary, who queued it and when |
| analyzer | choose which model reads your sessions | the five CLIs, their sign-in state, per-store consent |
| path | understand where children look for binaries | the resolved login-shell PATH, directory by directory (R6) |
| confirm-remove | remove an installed capability | what is being removed and the undo window |

## Friction scales with blast radius

The recurring failure is one feedback mechanism serving every action: a three-second toast
behind a command that stops every job on the host. **A row whose gate is a toast is a defect,
and so is a gate that exceeds the blast radius.**

| Action | Blast radius | Gate |
|---|---|---|
| Remove duplicates from a harness config | someone else's file | diff, counts, "Open the file instead", named-consequence button |
| Remove selected capabilities | installed capability | multi-select, named count, 30-day undo stated on the surface |
| Accept held schema changes | a tool regains callability | both diffs, and the reason it was held |
| Disable a server | one server stops answering | quiet destructive-red text button, never the primary |
| Trip breaker / wake now | one child process | none — reversible in one press, and the state is visible |
| Approve a phone-queued install | executable code on this Mac | the phone queues; the Mac shows the tools and asks |
| Stop Router | every session loses its tools | menu item, no accelerator |

Reversible actions are not confirmed. Undo beats "are you sure", and the 30-day window on
Cleanup is stated on the surface rather than in a preference nobody reads.

## Sheet mechanics

A sheet drops from its window's titlebar and is modal to that window only. It has at most one
filled primary; a destructive alternative is a quiet red text button, never a second filled
one. Return activates the default; Escape cancels. A sheet opened from the Settings window
attaches to the Settings window.

## Converting this to SwiftUI

Attach each sheet with `.sheet(item:)` on the view that owns the decision, so the sheet belongs
to its window. A sheet presented from a Settings pane attaches to the Settings window; the mock
draws both windows in one page and cannot demonstrate that, so it is a requirement the
implementation has to meet without a reference.

- `item:` rather than `isPresented:` — the sheet's content comes from the value that opened it,
  which removes the class of bug where a sheet opens showing the previously selected row.
- The twelve sheets are one enum, so the inventory is a compile-time fact.
- `confirmationDialog` is not a substitute for the gated sheets in the table above. A dialog
  cannot show a diff, and the diff *is* the gate for reconcile, quarantine and capability-delta.
- Return activates the default button via `.keyboardShortcut(.defaultAction)`; Escape cancels
  via `.cancelAction`. Both are free from the button roles, and a destructive alternative takes
  `.destructive` rather than a red foreground colour, so the platform styles it.

Acceptance: every row of the gate table has a test naming the sheet it presents, and no
destructive action's gate resolves to a transient message (M23).
