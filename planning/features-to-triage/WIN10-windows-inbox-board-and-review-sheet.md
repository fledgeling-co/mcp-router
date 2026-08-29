---
status: to-triage
found-by: intake, parity target for SURF-008 · 2026-08-30
registry-target: none
no-target-reason: SURF-008 registers the macOS Inbox board and review sheet and the registry holds no Windows equivalent, so no recorded case could witness the Windows one
---

# The Windows Inbox board and review sheet — the phone queues, it never installs

- origin: owner directive, 2026-08-30; parity target for the Mac Inbox board and review sheet
- audience: anyone on Windows who queues capabilities from their phone, or wants the analyst's findings in one place
- platforms: windows

## What and why

Inbox is "everything waiting on a decision from you: what your phone queued, and what the session
analyst noticed." It carries the product's central safety property, stated on the surface: "Nothing
here has been installed — the phone queues, it never installs."

That sentence is the feature. The phone is a discovery surface with no authority to execute
anything; the decision happens on the desktop, in front of the review sheet. A Windows
implementation that let an item install itself on arrival would break the guarantee the whole
pairing design exists to provide.

The board groups by decision state (`Undecided · 3`, `Approved · 12`, `Not for me · 5`) and each
undecided item carries its provenance (`postgres-mcp from Luke's iPhone, 2 min ago`) and an explicit
restatement that nothing has happened yet: "It has not been downloaded and nothing has been written
to any harness."

The review sheet is the decision surface. Its heading in the design of record is **What it would be
able to do**, followed by plain-language capability lines — read any table in the database you point
it at; run arbitrary SQL including writes unless you set it read-only; no network access beyond that
database; no filesystem access. Capabilities in plain words, not a permission manifest, and stated
in the conditional because it has not been granted anything yet.

## Acceptance sketch

- Items arrive from a paired phone and appear without a manual refresh.
- Nothing is downloaded or written to any harness before the user approves; the surface says so and it is true.
- Each item shows where it came from and when.
- The review sheet lists what the capability would be able to do, in plain language, before any approve action.
- Approve, and decline, are both available; approve installs and decline records the decision without installing.
- Undecided, approved and declined groups are all reachable, with counts that agree with their contents.
- Empty (nothing waiting), no-phone-paired, and disconnected states draw distinctly from one another.

## Assumptions made writing this

- Assuming pairing a phone to the Windows client is possible at all, which is WIN12's subject; if it is not, this board still carries analyst findings and degrades to that.
- Assuming the analyst findings and the phone queue share one board, as in the design of record, rather than splitting on Windows.
- Assuming approval is transmitted over the existing `POST /servers/:name/approve` route rather than needing a new one.
