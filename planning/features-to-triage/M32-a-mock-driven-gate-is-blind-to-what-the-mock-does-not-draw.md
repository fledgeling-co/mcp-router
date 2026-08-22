---
status: to-triage
found-by: M22, by driving the shipped app, 2026-08-23
---

# A mock-driven fidelity gate cannot see a defect in something the mock does not draw

M22's Harnesses board rendered **`Read now ago`**.

`shortAgo` returns the *word* `"now"` under five seconds and a duration above it, so the
surrounding copy reads correctly for every value except the one a freshly-loaded board always
shows first. A user opening that board sees it.

**It survived all three green instruments, and the reason is structural rather than an oversight:**

- **No test asserted the exact string.** Ordinary coverage gap.
- **M23's fidelity gate compares the build's copy against the mock — and the mock has no freshness
  line at all**, because the freshness line is one of M22's own additions. **There was nothing on
  the other side to disagree with.**
- The board is new, so no earlier rendered pass existed to contradict.

The second bullet is the item. `mock-fidelity` inverts the burden of proof — a difference is a
defect until a citation proves it intentional — which is the right default and makes it strong on
everything the mock draws. **On anything the build adds that the mock never drew, it has no
opinion, and no opinion reads exactly like agreement.** The gate reports `extra` with a citation
and the citation is honest; what neither side can say is whether the extra thing is *correct*.

So the coverage claim *"this surface is through M23's gate, clean over 193 nodes"* is true and
means less than it sounds like. It means: nothing the mock draws diverges. It does not mean the
surface is right.

## Why this is not fixed by drawing it in the mock

Adding a freshness line to `design/mcp-router-console.html` closes this instance and not the
class. Every conversion that adds a build-side affordance the design never specified re-opens it,
and the design of record legitimately does not specify everything — `M19`'s `path` refusal and
`M18`'s three undrawable readings are all cases where the build must say something the mock does
not.

The general remedy is that **an `extra` needs an oracle of its own**, not just a citation. Options
for triage, none costed yet:

- A required assertion per `extra` row — the citation names what checks it, not only why it exists.
- Golden-copy assertions on strings the build composes, which is what would have caught this one:
  `Read now ago` is wrong on inspection with no comparison needed.
- A property check on the composers themselves — `shortAgo` returning a word in one branch and a
  duration in another is a type-level smell that a round-trip test over the value range finds.

## The same run found two defects in its own lane, and they are the same family

Both recorded at the line that was wrong rather than summarised:

- A sentinel `grep` for `isn't built yet` **matched the board's own disabled-control help tag** —
  that sentence is `CommandAvailability.surfaceAbsent`'s, correctly reused. A detector matching
  the product's legitimate copy.
- An `awk` read AX fields **5 and 7** where SwiftUI puts a Button's label in **AXDescription (6)**
  and `enabled` is field **8**. It reported *"no Reconcile control is drawn disabled"* about
  **four that were**.

> **A gate reading the wrong column says the product is wrong.**

That is `G4`'s subject — an assertion named for a quantity it does not read — arriving in the
acceptance lane rather than in a count. Both were found only by driving the app.

## One more thing worth keeping from the same run

`m22-boards.sh` is now enrolled in `make acceptance`. **A lane nothing dispatches passes by hand
forever while reading as covered work** — `parity-stream.sh` sat executable and unrun from `R2-R`
until `P3`. Any new acceptance lane gets enrolled in the same change that writes it.
