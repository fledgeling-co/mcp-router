# M6 — Inbox and phone pairing (Mac side)

**Depends on:** M5.

Where things sent from the phone arrive, and how the phone gets permission to send.

- Pairing: a QR code and a typed fallback code, with a **live expiry countdown visible
  while you look at it**, and plain language about what the code grants. The code lets a
  remote party put executable code on this laptop, so the warning is the floor, not
  decoration. Fallback ladder: QR → can't scan → enter code → use this device instead.
- Paired-device management: see, name, and revoke.
- The inbox: items queued from the phone, each reviewable and installable from here.
  **Installation happens on the Mac and only on the Mac.**

Deep link: `?only=mac&pane=inbox`, `?sheet=pair`.

## What the test campaign measured about this, 2026-08-21

**Defects:** DEF-001, DEF-041 · **Requirements:** REQ-015, REQ-016 · **Surface:** SURF-010

The transport is unimplemented, and three independent routes agree. The strongest is not
the campaign's: **I5 already proved it and is merged at `4157bc4`** — see ORCHESTRATOR.md.
Its finding is sharper than "unproven": *the round trip does not happen because neither side
implements it*, carried by one line — the phone stored a paired-Mac record for a Mac it
never contacted, at an address it demonstrably could reach. Nine mutations, every assertion
shown able to go red, with a same-process connection to the same port in the same run as the
load-bearing calibration. Read that row before planning this item; it is the measurement,
and the campaign's two routes below only corroborate it.

From the assertion side (**DEF-001**): three campaign cases stand `fail` against REQ-015.
The Mac sheet mints a Crockford code and the phone can type it while nothing contacts the
other device.

From the effect side (**DEF-041**): an effect census over `app/Sources` with the test
targets excluded finds **no symbol that opens a connection to a paired device**. REQ-016 —
"a pairing exchange actually contacts the other device and stores a record only after that
contact succeeds" — therefore holds *vacuously*. The guarantee cannot be violated by a
build that never contacts anything, so it is recorded `vacuous` rather than `observed`: a
class of finding distinct from a contradiction, and one that wants the capability built
rather than the claim rewritten.

What the sheet does today is on glass at
`planning/test-campaign/evidence/shots/SURF-010.*.png`, judged against the design and
recorded `fail`: the design specifies a QR code, the code in mono at 22px, a red warning
that anyone who scans it can put items in your inbox until it expires, an expiry countdown
with a progress ring, and a "Can't scan? Type a code" fallback. The build carries the same
title and Done action and, in place of all of it, a refusal — that pairing needs the Mac to
be reachable from the phone, that this build ships no way to listen for one, and that
nothing is wrong with the user's phone or network.

That refusal is the **correct** behaviour for a build with no transport, and the campaign
recorded it as such: a sheet drawing a QR code no phone could act on would be the worse
failure. Building this item is what closes DEF-001 and takes REQ-016 off `vacuous`; the
refusal copy is what should be removed at that point, not before.
