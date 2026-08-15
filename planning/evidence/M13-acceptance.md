# M13 — acceptance evidence

Item: the scroll-edge separator, A34. Branch `ai/m13`, worktree `.worktrees/M13`.
Everything below was run on this branch, invisibly (`open -g`, AX reads by pid, no activation).

## The diagnosis

The brief left it open whether the separator was broken or the check sampled the wrong row.
**Settled: the separator is correct and the check was wrong.** Detail and the full review dispositions
are in `planning/specs/spec-M13.md`; the measurements are here.

### The failing colour is the separator's own composite

`DESIGN.md` §2: `--line` = `#FFF` @ 7.5%, `--ground` = `#1E1E1E`.
`0.075 × 255 + 0.925 × 30 = 46.875 → 0x2F`. The reported `#2F2F2F` **is** the separator over the
content ground, computed from tokens without reference to any capture.

### The line is present, pinned, and one point tall

Servers, band `x 544…1752`, content-top row `104`, driven through the scroll bar's `AXValue`:

| offset | row 104 | contiguous run |
|---|---|---|
| 0 | `#1E1E1E` 1.000 | 1209px — the whole band |
| 0.15 | `#2F2F2F` **1.000** | 1209px — the whole band |
| 0.35 | `#2F2F2F` **1.000** | 1209px — the whole band |
| 0.6 | `#2F2F2F` 0.707 | 844px, `x 724…1567` |
| 0.85 | `#333334` 0.901 | — |

Rows 104 **and** 105 carry it; 103 and 106 do not. Two image rows at 2× is one point, which is
`MetricToken.focusRing.leadingScalar / 2` — `ScrollEdgeSeparator`'s declared height.

At 0.6 the run's boundaries are the Servers board's own header: the large "Servers" heading on the
left and the "Add server…" button on the right, which by that offset have scrolled up to the top
edge. The next colours in the row's histogram are `#C6C6C6` (the heading's glyph grey) and
`#457EC7`/`#477FC7` (the button's accent blue).

### The decisive measurement: solving the composite

Solving `a = (A − B) / (255 − B)` per pixel at the line row against the row below it. The probe does
not contain the number 0.075:

| offset | readable | recovered opacity | agreeing |
|---|---|---|---|
| 0 | 1.000 | **0.0000** | 1.000 |
| 0.15 | 1.000 | 0.0756 | 1.000 |
| 0.35 | 1.000 | 0.0756 | 1.000 |
| 0.6 | 0.723 | **0.0756** | 0.998 |
| 0.85 | 0.950 | **0.0742** | 1.000 |

7.5% is `--line`'s own alpha, recovered from pixels. At 0.85 the line is not lost — it composites
over the scrolled table-row ground `#222224` to give `#333334`, exactly as the equation predicts.
**The overlay is on top, at full width, over moving content, at every scrolled offset.**

## What changed

`scripts/acceptance/mac-shell.sh` (A34's rendered half) and a new `veil` subcommand in
`scripts/acceptance/axkit.swift`. **No application source is modified** — `git diff --stat` on this
branch is two files, both under `scripts/acceptance/`.

## Gates

| Gate | Command | Exit |
|---|---|---|
| Debug build | `make build-mac` | **0** |
| Release build | `make build-mac-release` | **0** |
| Lint | `make lint` | **0** (exit code read directly, not through a pipeline) |
| Unit tests | `swift test` from `app/` | see below |
| Acceptance | `scripts/acceptance/mac-shell.sh` | A34 green; run stops later at a pre-existing failure, below |

### `swift test`

Red on both full runs — and **provably not from this branch**, by structure before argument:
`app/Package.swift` references nothing under `scripts/`, and the only two files this branch changes
are `scripts/acceptance/axkit.swift` and `scripts/acceptance/mac-shell.sh`. The test target compiles
a source tree identical to `main`.

The behaviour is load flake, and the giveaway is that **the failing set moves between runs** on an
unchanged tree:

| run | failed |
|---|---|
| 1 | `P6 — a per-server idle window overrides the default` (`PoolReapingTests.swift:61`) |
| 2 | `a reconnect over a feed that stays live releases its guard…` (`ActivityReconnectTests.swift:50`) and `a typed burst is one request, not one per keystroke` (`DiscoverBoardTests.swift:168`) |

All three are wall-clock races — P6 builds a pool with `idleMs: 25` and asserts reaping after a 150ms
sleep; the other two are a bounded-wait guard and a debounce window. Re-run in isolation by
**function** name, which is what `--filter` matches (a display-string filter matches nothing and
reports a green over zero tests):

| filter | result |
|---|---|
| `perServerIdleWins` | `1 test in 1 suite passed` × 3 |
| `reconnectIsNotDeadAfterItsFirstSuccess` | `1 test in 1 suite passed` × 2 |
| `searchIsDebounced` | `1 test in 1 suite passed` × 2 |

Each filter reports `1 test in 1 suite`, so these are real matches rather than vacuous greens.
Recorded as pre-existing timing flakes under a multi-runner fleet; this item neither causes nor
fixes them.

### The acceptance run

A34 itself, on the unmodified app:

```
the scroll edge
  at rest: opacity 0.0000 over 1369px (1.000 of the band readable, 1.000 agreeing)
  scrolled to 0.6 (content under the edge, 0.861 uniform below it):
    opacity 0.0756 over 1369px (1.000 of the band readable, 1.000 agreeing)
  ok — the scroll edge: nothing at rest, one line at opacity 0.0756 across 1369px of the
       content width once scrolled, with content underneath it
  ok — returning to the top cleared it: opacity back to 0.0000
```

Everything from the start of the script through A34 passes. The run then reaches its **last**
assertion — previously unreachable, because A34 stopped the run — and fails there. That failure is
pre-existing and is not this item's; the mechanism is diagnosed in `spec-M13.md` §"found-not-fixed",
item 3, together with the user-visible copy bug behind it.

## Red–green: the assertion was proven to fail, both ways

Each mutation was built and run end to end, then reverted by **re-applying the original text**
(never `git checkout --`). `git status app/` is clean and `git diff --stat` shows no Swift file.

| # | Mutation | Result |
|---|---|---|
| D1 | `ScrollEdgeSeparator(isVisible: false)` — the separator can never show | **exit 1** · `FAIL: no line is drawn over the top row once scrolled (opacity 0.0000) — the separator did not appear` |
| D2 | `isSeparatorVisible = true` in `ScrollEdgeState.observe` — it can never hide | **exit 1** · `FAIL: the content's top row is already veiled at rest (opacity 0.0756) — the separator is showing on a window nobody has scrolled` |

Between them they cover both halves of A34's clause: absent at rest, present above it.

D1 was first run against an earlier draft of the assertion, so it was **re-run against the committed
script** after the review fixes landed (measured scale, trailing-edge guard, tightened thresholds).
Same outcome, same message: exit 1, `opacity 0.0000 over 1369px`. The final verification run then
restored the separator, rebuilt, and reproduced the green above.

### The light-appearance branch, proven separately

`--line` is `#000 @ 10%` on the light ground, where a white-only solver reads nothing. Against a
synthesised light edge (`#ECECEE` ground, hairline authored at 10%):

| capture | `veil` | previous white-only solver |
|---|---|---|
| light ground + dark hairline | `1.000 0.1017 1.000 200` | `qualifying 0.000` — finds nothing |
| light ground, no hairline | `1.000 0.0000 1.000 200` | — |

## Review lane

`grok --model grok-4.6` (grok 1.0.3, `~/.grok/bin/grok`), the owner's substitution for the
account-limited codex lane. Smoke-tested before use: exit 0, `LANE OK`. **No downgrade was needed.**

Two passes, both adversarial: one on the diagnosis and proposed design, one on the implemented
assertion. Seven findings accepted and fixed, two rejected on measurement, one noted. Full
dispositions in `planning/specs/spec-M13.md`.

## Screens touched

| Screen | How verified | Result |
|---|---|---|
| Mac shell content zone, Servers | `scripts/acceptance/mac-shell.sh` A34 — rendered, driven through `AXValue`, invisible | pass |

No other surface was exercised for this item, and no other item's acceptance script was run. The
app was launched backgrounded throughout and the script's own frontmost-unchanged guard passed on
every run.
