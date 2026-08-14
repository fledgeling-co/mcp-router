# I4 — Let the phone install directly

**Source:** `phone-install` = `allow-install` (confirmed, the owner's own choice, against the shipped
default and with the consequence shown on the page).

What shipped is narrower than the original idea: the phone queues and the Mac decides. That boundary
is what the whole pairing design currently rests on. The owner has chosen to widen it.

**This changes the pairing threat model and the work is mostly that, not the UI.** Anything holding a
paired phone can change what the laptop runs. The page stated the consequence plainly and it was
accepted, so build it; it did not say the risk goes away.

Read first: `spec-I1.md` (pairing), `spec-I3.md` (the queue), and M6's Mac-side Inbox, which is the
component whose reason for existing this changes.

Open question for the spec, not to be settled by assumption: whether a second confirmation on the Mac
survives. The page noted that adding one is "most of the benefit gone", so if the design lands there,
say so plainly and let the owner decide rather than shipping a slower version of what already exists.
