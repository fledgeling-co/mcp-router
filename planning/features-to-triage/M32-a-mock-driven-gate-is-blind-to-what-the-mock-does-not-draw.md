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

## Two sessions reached this independently, by different routes

Worth recording because it changes what the finding is. The armada conductor received this
conclusion **at the start of the evening**, from the `m22` worker directly, in almost these words:
driving the shipped app found a defect three green instruments could not, the freshness line read
`Read now ago`, and the fidelity gate was structurally blind because the mock has no freshness line
to disagree with — that line being M22's own addition. It reached this orchestrator hours later
through the same worker's handover note.

Two routes, one conclusion. **So this is not one runner's insight; it is what falls out of driving
a surface the mock does not fully describe.** Anyone who drives such a surface will find it, and
anyone who only runs the gate will not.

**Disposition, 2026-08-23:** the coverage claim on the four branches waiting to merge that carry
M23 conversions is **suspended, not merely qualified**, until this item lands. *Clean over N nodes*
is not a coverage statement about a surface; it is a statement about the intersection of the
surface with the mock.

## The same shape, in six instruments in one evening

This item is one of six independent findings on 2026-08-23 that share a single mechanism: **an
instrument that cannot fail reports exactly like one that passed.**

| instrument | why it could not fail |
|---|---|
| `mock-fidelity` on a build-side addition | no mock counterpart to disagree with |
| M18's Cleanup sheet | no test mentions either keyboard shortcut |
| M20's plan slices | the promised names exist only in the plan |
| G5's `\binstalled\b` | cannot match inside `_installed_` — `_` is a word character |
| a `pf` anchor (another project) | its positive control could never resolve |
| a gate exiting 0 (another project) | over an empty population |

And a seventh, which is the one worth pausing on because it is the tool that measures the others:
**`reckon.py check` exits 0 by comparing `summary` against `rows` and never reading `headline`.**
Three sessions tonight quoted a generated headline that disagreed with the rows beneath it. That is
this same class inside the instrument the fleet uses to count its own remaining work — filed
against `reckon` rather than left as three sessions' folklore.
