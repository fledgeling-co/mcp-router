---
status: completed
found-by: intake, parity target for SURF-010 · 2026-08-30
reckon-sources: [SURF-042]
target-note: SURF-042 `Windows pairing dialog` carries `note: WIN12.`; the row did not exist when the `none` was declared on 2026-08-30.
---
# Pairing an iPhone to the Windows client

- origin: owner directive, 2026-08-30; parity target for the Mac Pairing sheet
- audience: anyone on Windows who wants to queue capabilities from their phone
- platforms: windows

## What and why

The Inbox board's value depends on a paired phone: the phone discovers and queues, the desktop
decides. Without pairing on Windows, WIN10 degrades to analyst findings only and the iOS app has no
Windows counterpart to pair with.

The Mac flow is a pairing sheet reached from `Pair iPhone...` on the Inbox board, met by the phone's
scanner and code-entry surfaces. The phone side already exists and is not changed by this brief — 
the Windows client has to be the other end of a protocol that is already specified.

Two things make this more than a redraw, and both should be settled before the surface is built:

- **Where the pairing secret lives.** On the Mac this is the keychain. The Windows equivalent is
  Windows Credential Manager, which encrypts per user via DPAPI. This is a security-relevant
  substitution rather than a styling one, and it belongs to WIN17's contract question as much as to
  this surface. No credential value is ever displayed or logged.
- **Discovery and reachability on a Windows network.** Whatever the Mac uses to advertise itself has
  to have a Windows answer, and Windows Defender Firewall will prompt on first bind. A pairing flow
  that silently fails behind a firewall prompt reads to the user as a broken product.

## Acceptance sketch

- `Pair iPhone...` reaches a pairing surface from the Inbox board.
- A phone running the existing iOS app can complete pairing against the Windows client, by scan and by manual code entry.
- The pairing secret is stored in Windows Credential Manager, never in a config file, and is never displayed or written to a log.
- A paired phone is listed, and unpairing is available and revokes access.
- The firewall case is handled: if the bind is blocked, the surface says so and says what to do, rather than timing out silently.
- Failure states — wrong code, expired code, unreachable phone, already paired — are each distinct.

## Assumptions made writing this

- Assuming the pairing protocol is fixed by the existing iOS app and router, so this brief builds the Windows end rather than proposing a new scheme.
- Assuming Credential Manager rather than a file, following the standing rule that a secret is never put in a config file to make a tool work.
- Assuming one phone at a time unless the Mac app supports more; that was not checked from here.
