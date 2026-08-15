# M13: the scroll-edge separator, A34

| | |
|---|---|
| Status | **Done** — merged `08b9bdf` 2026-08-15 |
| Item | M13 — the only genuinely red product check on `main` |
| Deps | M1 ✓ (the shell and `ScrollEdge.swift`) · M2 ✓ (`boardsThatScrollThemselves`) · M3 ✓ (the Servers board) · M6 ✓ (the eighth board) |
| Branch | `ai/m13` · worktree `.worktrees/M13` |
| Design authority | `DESIGN.md` §2 grounds and lines (`--line` = `#FFF` @7.5%), §3.3 opaque content, §7 motion |
| Out-of-family gate | `grok --model grok-4.6` (grok 1.0.3, `~/.grok/bin/grok`) — the owner's substitution for codex, whose account limit runs to 2026-08-20. Lane smoke-tested at the start of this item: exit 0, `LANE OK`. |

---

## Feature description

`scripts/acceptance/mac-shell.sh` exits 1 at A34:

```
FAIL: the top row is not one colour once scrolled (#2F2F2F covers 0.707) — that is content, not a separator
```

The brief named two candidate diagnoses and refused to choose between them: either the separator is
broken, or the check samples the wrong row. **Settling that was the first job, and it is settled.**

## The diagnosis, and the evidence that settles it

**The separator is correct. The check is wrong.** The app is not changed by this item; the check is.

Three independent measurements say so, all taken on a clean rebuild (the Debug product deleted and
`make build-mac` re-run to exit 0, so none of this is the stale-build artefact that has cost this
fleet time elsewhere).

### 1 · The failing colour *is* the separator

`DESIGN.md` §2 gives `--line` as `#FFF` @ 7.5% and `--ground` as `#1E1E1E`. Composite one over the
other:

```
0.075 × 255 + 0.925 × 30 = 46.875 → 47 = 0x2F
```

`#2F2F2F` is the scroll-edge separator's own composited colour, computed from the design tokens
without reference to the capture. The check reports the separator's colour and calls it content.

### 2 · The hairline is exactly one point tall, in the right place, and pinned

Captured through the same `screencapture -l<CGWindowID>` path the check uses, on Servers, with the
band the check computes (`x 544…1752`, content-top row `104`):

| scroll offset | row 104 | run |
|---|---|---|
| 0 | `#1E1E1E` **1.000** | 1209px — the full band |
| 0.15 | `#2F2F2F` **1.000** | 1209px — the full band |
| 0.35 | `#2F2F2F` **1.000** | 1209px — the full band |
| 0.6 | `#2F2F2F` 0.707 | 844px, `x 724…1567` |
| 0.85 | `#333334` 0.901 | — |

Rows 104 **and** 105 carry it and rows 103 and 106 do not: two image rows at 2× is one point, which
is `MetricToken.focusRing.leadingScalar / 2` — the height `ScrollEdgeSeparator` declares. It sits at
the same row at every non-zero offset, which is what a hairline pinned to the top of the content
zone does and what content moving through cannot do.

At 0.15 and 0.35 the assertion the check makes is satisfied **perfectly** — one colour, the
separator's colour, across the whole content width. A34's clause is met.

### 3 · What the missing 29.3% is

At offset 0.6 the run stops at `x 724` and resumes after `x 1567`. Those boundaries are the Servers
board's own header: the large "Servers" heading on the left and the "Add server…" button on the
right, which by that offset have scrolled up to the content-zone's top row. The histogram names them
— after `#2F2F2F` the next colours at row 104 are `#C6C6C6` (the heading's glyph grey) and
`#457EC7`/`#477FC7` (the button's accent blue). A 7.5% white hairline over a light glyph or a
saturated button is still dominated by what is underneath, so those pixels are not the separator's
colour and the row is not "one colour".

Nothing here is a rendering defect. The separator is drawn across the full width at every offset;
at 0.6 it is simply drawn over two opaque things that are brighter than it.

## Why the check breaks, stated precisely

The oracle is *"the content's top row is uniformly one colour at rest and uniformly a different one
once scrolled"*. That is only a valid reading of the separator while **the pixels behind the top
edge are a single flat colour across the whole content width**. It held when A34 was driven on a
scaffolded placeholder. It does not hold over a real board, because what is behind the top edge
after an arbitrary scroll is arbitrary board content.

The immediate trigger is the hard-coded scroll fraction of **0.6**. Servers is centred in a frame of
`MetricToken.sidebar × 3` = 768pt inside a 398pt viewport, so the scrollable range is ~370pt and the
flat gap above the board is ~208pt. `0.6 × 370 = 222pt` — the fraction overshoots the gap by about
fourteen points, and the board's heading arrives under the sample. A smaller fraction passes. The
check fails by a whisker, on a constant, for a reason that has nothing to do with the clause.

**Changing 0.6 to 0.4 is not the fix.** It is the same fragility with a luckier constant: the next
board, a different window size, or a change to the min-height flips it back — and it would work by
*avoiding* the case the separator exists for, sampling the empty region above the board instead of
the moment content passes under the toolbar. The oracle is what has to change, not the constant.
0.6 is kept, because it is the offset at which the interesting thing is happening.

## What the brief predicted, and why it was wrong

The brief and the check's own comment both expected the failure to come from Servers no longer using
the shell's scroll view — *"When the last board lands this needs the assertion moved onto a board's
own list instead."*

That premise is false, and the source says so. `ShellWindow.ContentZone` keeps
`boardsThatScrollThemselves: Set<Destination> = [.activity]`: **exactly one** of the eight boards
installs its own `ScrollView`. The other seven, Servers among them, are still wrapped in the shell's
`outerScroll`, which is still the view whose geometry drives `ScrollEdgeState`. The destination the
check picks is correct and needs no move. The stale comment is what sent the diagnosis down the
wrong path, so this item corrects it as well as the assertion.

## Clauses

| # | Clause | Evidence |
|---|---|---|
| A34 | The scroll-edge separator is absent at scroll offset 0 and present above it, exercised against a real scrolling window rather than only a derived Boolean | unchanged — `ShellTests.swift` covers the derived half; the rendered half is C1–C6 below |
| C1 | The rendered assertion identifies the separator by **solving the compositing equation**, not by requiring the row to be one colour: `a = (A − B) / (255 − B)` at every x whose background is legible, where B is read from the first row below the 1pt line | `axkit veil`, new subcommand |
| C2 | The measurement is taken at an offset that puts the **board's own content under the top edge** — the moment the separator exists for — chosen by walking outward (0.6, 0.85, 0.95) and taking the first that qualifies | `scripts/acceptance/mac-shell.sh`, A34 section |
| C3 | The run proves the view actually scrolled, so "no separator appeared" can never be reported for a scroll that silently did nothing | ditto — a `banddiff` liveness check below the edge |
| C4 | Every way the clause can go unproven is a **FAIL**, not a BLOCKED: no qualifying offset, too little readable background, an unevenly-lightened row. Exit 2 stays reserved for permissions, the session and the capture | ditto |
| C5 | The opacity is never written down — the scrolled reading is compared against the at-rest reading — so the appearance stays free to change | ditto |
| C6 | The comment claiming the assertion must move onto a board's own list once the last board lands is corrected to what the source actually does | `scripts/acceptance/mac-shell.sh` |
| C7 | The app is unchanged: no file under `app/Sources/` is modified by this item | `git diff --stat` on the branch |

## The out-of-family review, and what it changed

`grok --model grok-4.6`, briefed adversarially with the measurements above and told to refute the
conclusion. Its findings and their disposition:

| Finding | Disposition |
|---|---|
| **Rejected — refuted by measurement.** *"The separator is defective on the measurements you already have. At 0.6 the hairline does not hold the row; at 0.85 it loses `#2F2F2F` entirely. A shell overlay on top of the ScrollView cannot do that, so either the overlay is behind the document or a 7.5% veil is sitting on mixed content."* | Grok named the measurement that settles it — solve the composite at the sampled row against the row below — and then did not take it. Taken: the recovered opacity is **0.0756 at offset 0.6 (874px, 0.998 agreeing) and 0.0742 at 0.85 (1149px, 1.000 agreeing)**, against **0.0000 at rest**. 7.5% is `--line`'s own alpha, recovered from pixels without being written into the probe. At 0.85 the line has not been lost: it composites over the table-row ground `#222224` to give `#333334`, exactly as the equation predicts. The overlay is on top, at full width, at every scrolled offset. |
| **Accepted.** *"The control row does not establish that the background did not move, and cannot name the pixels that did. It passes on today's pixels with the overlay lighting up over the empty gap."* | The control row is gone. The compositing test replaces it and attributes the change to a uniform veil directly. |
| **Accepted — this was the sharpest finding.** *"Smallest-first selects the empty-gap regime and never looks at 0.6/0.85, so today's case stops being tested."* | Inverted. The offset now walks **outward** and takes the first at which the board's own content is under the edge, and fails if none does. The easy regime is no longer reachable. |
| **Accepted.** *"BLOCKED-when-unmeasurable is a mute switch: top-align the boards, the control row moves at every offset, the script prints BLOCKED and leaves."* | Every layout-dependent path is now a FAIL. Top-aligning the boards makes content reach the edge *sooner*, so it makes this assertion easier to satisfy, not quieter. Exit 2 is left only for the harness conditions the script already reserved it for. |
| **Noted, out of scope.** *"The mock draws the hairline on the toolbar (`.tbar.edge { box-shadow: 0 1px 0 var(--line) }`); the implementation draws it on the content zone."* | A placement question about where the rule belongs, not about whether A34 holds. Recorded for whoever revisits the toolbar; not changed here, and this item ships no app change. |

## The second out-of-family review — of the implemented gate

The design changed materially in response to the first review, so the *implementation* went back to
`grok --model grok-4.6` rather than the plan text. It found four things worth acting on.

| Finding | Disposition |
|---|---|
| **Accepted — a real false red.** *"Light appearance. `--line` is `#000 @ 10%` there and `--ground` is `#ECECEE` (236). The solver's `(255 − B) ≤ 24` skip drops every channel, `veil` prints zeros, and the run fails for the appearance rather than for the separator. Deterministic, not speculative."* | Correct. `veil` now takes the veil's direction from the pixel and reports the magnitude, so it solves toward black on a light ground as well as toward white on a dark one. Proven on a synthesised light-mode edge: **0.1017 recovered against an authored 0.10**, 0.0000 with no line, while the previous white-only solver returns `qualifying 0.000` on the same image. |
| **Accepted — a real false red.** *"`* 2` is a constant. At 1× the band samples a point into the document; at 3× it samples the toolbar. Backing scale is not read off the PNG."* | The scale is now measured — the capture is window-scoped, so its pixel width over the window's point width is the scale — and every offset in the band, including the 1pt line and the background row, is derived from it. |
| **Accepted — a real future footgun.** *"Selecting a server opens `ServerInspector`, a `ScrollView` of its own. `tail -1` and `axkit scroll`'s `last: true` both retarget to it; the gate would drive and photograph the inspector while reporting on the shell's scroll edge."* | Guarded. The sampled scroll area must reach the window's trailing edge, which a nested inspector scroller cannot, so the retarget becomes a stop with a named reason instead of a quiet mis-measurement. |
| **Accepted — factual error in my comment.** *"'one of the eight boards installs its own `ScrollView`' is false. `SettingsBoard` installs one and is not in the set."* | Verified: `SettingsBoard.swift:70` installs a `ScrollView` while staying out of `boardsThatScrollThemselves`, so it nests one scroller inside another. The comment is corrected, and the nesting is recorded below as found-not-fixed. |
| **Noted, partially mitigated.** *"A solid 1pt fill of the composite colour passes; so does a gutter-only line covering ≥ 20% of the band, because the flatness filter discards the text columns."* | The readable-share floor moved from 0.20 to 0.30 and the content-under-the-edge test from 0.98 to 0.90, which removes most of the room. The residual hole is narrow and is not closed: a line covering less than about half the *qualifying* columns already drives the median to zero and fails, and a hardcoded composite colour would have to get past `scripts/lint/no-raw-design-values.sh`. Recorded rather than engineered around. |
| **Rejected.** *"A tinted rule (accent at low alpha) still collapses to one number per x and would pass."* | True and intended. The clause is that a separator appears and clears; its colour is `--line` by construction and is a design-lint concern, not this gate's. Pinning the hue here is exactly the "pinning the appearance" the previous author was right to avoid. |

## Out of scope, and found-not-fixed

**1 · Boards using the shell's scroll view render vertically centred, not top-aligned.**
`ContentZone` gives the outer scroll's content `.frame(maxWidth: .infinity, minHeight:
scrollableMinHeight)` with no `alignment:`, so the default `.center` applies and a board shorter than
768pt floats in the middle of a 768pt frame. On a 398pt viewport that puts the Servers board's first
pixel roughly 208pt below the top of the pane, with a large empty gap above it — plainly visible in
this item's rest capture.

The change is one word (`alignment: .top`) but it re-lays-out the seven boards wrapped in the shell's
scroll view and so needs UI verification across all of them: a different item, and exactly the kind
of sweep the owner has asked runners not to launch off the back of an unrelated change.

The new assertion is written so that fixing it later is safe. It needs content under the top edge,
which top-alignment supplies immediately, and it has no path that goes quiet when the empty gap
disappears.

**2 · `SettingsBoard` nests a scroll view inside the shell's.** It installs its own `ScrollView`
(`SettingsBoard.swift:70`) while staying out of `ContentZone.boardsThatScrollThemselves`, so it is
wrapped in `outerScroll` as well. M2's B41 says explicitly that no scroll view nests inside another
and that a board with its own scroller joins that set. Either the board should join the set or the
inner scroller should go. Found while checking this item's comment against the source; it belongs to
whoever owns Settings, does not affect Servers, and is not touched here.

**3 · The next check along is red, and it is a false red of the same species — plus a real copy
bug behind it.** With A34 fixed, `mac-shell.sh` reaches its last assertion and fails:

```
FAIL: every destination has a board, but the Release bundle still contains 'isn't built yet'
      — the scaffold outlived the surface it stood in for
```

M6 engineered against exactly this: `ScaffoldPane.swift` records the sentinel **as a comment** and
explains that a `let` "would put it straight back into the binary". That worked — the pane
placeholder is gone. What the gate actually finds is a different string that happens to be the same
sentence: `MenuCommand.surfaceAbsent`'s headline, *"This part of the app isn't built yet."*, which
is **live** and reachable (`MenuCommand.swift:301, 306, 311, 318, 321`).

So the gate is a substring oracle that cannot tell a retired pane from a live menu reason — the same
shape of defect A34 had. But the more interesting half is the product bug it exposes: with all eight
boards shipped, `surfaceAbsent` is now the dimming reason for *"no servers are configured"* and
*"Skills isn't installed"*, and it tells the user **"This part of the app isn't built yet."** That is
false copy in the shipping menu, not a test artefact.

The fix is to reword the reason to what it now means, which also makes the Release assertion honest
again without touching the gate. Left alone here: it is `MenuCommand`'s copy and M6's scaffold
lifecycle, this item ships no app change, and the diagnosis above is complete enough to act on
directly. Recorded for the orchestrator to route.

