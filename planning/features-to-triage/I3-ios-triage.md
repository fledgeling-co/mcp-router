# I3 — iPhone: Triage, Queue, Library, Settings

**Depends on:** I2.

Triage is the surface with the most design history and the tightest constraints.

**It is a checklist, not a swipe deck.** The deck was built and rejected for a reason
that is not taste: a swipe commits a security decision on a gesture, one item at a time,
with no undo and no record of what was dismissed. What replaces it:

- Buckets as segmented tabs with counts — Undecided / Queued / Not for me — so
  dismissals have a home and are revisitable from the desk.
- A checkbox per row, and a one-line colour-coded capability summary on every row so the
  security fact is visible without opening anything.
- Tap to expand for the full capability list.
- A commit bar carrying the count (`Send 2 to Mac`), disabled until something is
  selected, with a line stating that nothing installs from the phone.
- Inline Undo after any batch action. No confirmation dialog — the commit bar already
  states what will happen and Undo already exists.

Two bugs found in the prototype that must not survive into the build: every checkbox
rendered ticked by default on a screen whose whole job is deliberate selection, and the
capability lines truncated. Rows are a fixed height and never ellipsise.

**Queue** — what has been sent and its status on the Mac. **Library** — what is
installed, read-only. **Settings** — the paired Mac, notifications, and unpairing.

Deep link: `?only=phone&tab=triage`.
