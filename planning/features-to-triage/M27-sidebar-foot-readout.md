# M27 — the sidebar foot's loopback readout is absent, and the child-process card lost its label

**Category:** mac · **Found:** 2026-08-20, by the campaign's design differential
**Defect:** DEF-043 · **Surfaces:** SURF-001 (shell, all boards) · **Related:** M23, DEF-042

## What was measured

`design/mocks/prototype.html:681` emits, from inside the shared sidebar wrapper:

```html
<div class="sfoot"><span class="dot live"></span>127.0.0.1:8879</div>
```

Because it is in the wrapper, the design paints a live-dot loopback readout at the foot of
the sidebar on **every** board. The build paints none. Across 9 accessibility dumps taken
at 1156×680 — one per destination — the only two `127.0.0.1` hits are the Settings board's
own Endpoint row, at window-relative `x=942`, which is the content area rather than the
sidebar.

Separately, `prototype.html:699-700` labels the sidebar-foot card `Child processes` over a
large numeral and `of N declared`. The build draws the count as an unlabelled, uncarded row
reading `Running   1 of 4`, and the string `Child processes` appears in **0 of 9** dumps.
The number survives; the card and its label do not.

## Why this is a brief rather than a closed defect

The loopback address is exactly the kind of number ORCHESTRATOR.md's honesty rule governs —
*no number is displayed that the router does not observe* — so its removal may have been
deliberate, and DEF-042 records four other places where the build is the correct half of a
design divergence. What is not deliberate either way is that nothing in the campaign had
checked. The measurement above is the first time either element was looked for.

## What to deliver

Settle each of the two independently, and say which way it went and why.

1. **The loopback readout.** Either restore it at the foot of the shared sidebar, showing
   the endpoint the app is actually talking to and a dot reflecting observed reachability
   rather than a constant — or record in `DESIGN.md` that it is deliberately absent and why,
   and annotate `prototype.html:681` as superseded. A readout that hard-codes `:8879` while
   the app talks to a different port would be the honesty rule broken in the other
   direction, so if it is restored, it reads from the same source the Settings Endpoint row
   reads.
2. **The child-process label.** The count is already correct and on screen. Give it the
   design's label and card, or record that the bare row is the intended treatment. This one
   carries no honesty question — `Child processes` names what the number already is — so
   absent a reason to differ, the design wins.

Add on-glass coverage for whichever way each goes, so the next differential compares against
a settled answer. The campaign's Mac lane captures at 980×620 through
`scripts/acceptance/mac-app.sh`; the shell is SURF-001 and its predicate must hold on every
destination, since that is what "in the shared wrapper" means.

## Scope

These two elements of the sidebar foot, and nothing else on the shell. The campaign's
differential names other divergences on these boards; they belong to DEF-042 and to M23's
mock-to-SwiftUI contract, not here. If you find a third divergence in the sidebar while
working, record it and leave it.

**Do not activate MCPRouter to take a capture by hand.** The campaign's standing constraint
is that this lane never activates the app; the capture script is the supported route.
