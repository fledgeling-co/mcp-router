# Coverage model — mcp-router 2026-08-19

## Axes and partitions
- surface: 17 enumerated (8 Mac boards + shell + popover + pairing sheet + 3 iOS + daemon + control API + parity)
- state: empty · populated · offline/stale · refused · overflow. Held fixed: loading (skeleton is fixture-only and time-bound).
- viewport: Mac 1024×768 (acceptance default) · popover ~320×480 · iOS 393×852. Dropped: below-smallest Mac (no authored compact Mac layout).
- theme: light (on-glass default). Dark is a second cell on the shell/honesty pair. Dropped: high-contrast (no authored tokens).
- role: operator. There is no viewer role; the control API is loopback-authenticated.
- data-shape: zero · typical · overflow · offline · concurrent-write · forged-write.
- execution-plane: on-glass (macos-glass, ios-glass) and headless (swift-testing / parity).
- locale: held fixed LTR-short. No localisation.
- pairing-transport cells: FLOW-002 effect is characterised as fail (DEF-001), not dropped.

## Strength
Pairwise floor. 3-way locally on theme×viewport×surface for Mac boards (sampled as light×1024×each board + dark×1024×shell + light×offline×popover). Honesty cluster is role×state×network, sampled as operator×stale×offline and unauthenticated×refused×forged-write.

## Constraints
A viewer role does not exist. Touch has no hover. iOS has no accessibility tree for geometry. A raster-visual case on ios-glass uses simctl screenshots, which the lane marks untrustworthy by construction — cited as such.

## Effect classes — what a requirement may declare, and how to read the list

Every requirement carries an `effect` field naming what it makes the product do outside its own
memory. The vocabulary is the instrument's and it is CLOSED: a value outside it is not a new class,
it is a value that fails a membership test and drops out of the census, which reads as a requirement
promising nothing observable and therefore owing no witness.

The list is not copied here, because a copy drifts from the tool it describes. Read it with:

```sh
python3 planning/test-campaign/bin/effect-class-census.py           # prints the recognised set
python3 planning/test-campaign/bin/effect-class-census.py --quiet   # suppresses only that header
```

That gate parses the set out of every copy of the instrument this repository can see — the
`vendor/` pin and the machine's plugin cache — and reports a disagreement between two copies as a
finding, since a repository pinned to one vocabulary while its runs use another is the same silence
one level up. It runs on `make lint`, with `--control` beside it.

**When the true class is not in the list.** Declare `effect: "none"` and name the real class in
`effectUnrepresentable`. `none` then means *no representable class*, not *no external interaction*,
and the row owes MORE than an ordinary one rather than less: the named class must be outside the
instrument's set, `effect` must be exactly `none` so the narrowing is stated, and `provider` must
resolve against `campaign.json`'s `sourceRoot` through the instrument's own `resolve_provider`. The
gate enforces all three. REQ-027 is the only row in that position — a filesystem READ, which the
list has no class for.

## The blind-mutation vocabulary

`campaign.json`'s `blindVocabulary` is written for THIS corpus and replaces the shipped defaults
(`only: true`) rather than extending them. The defaults are snake_case for a Rust/RPC shape: over
the 2282 test bodies under `testRoot` they find 3 mutating call sites where the declared list finds
481, so a number produced from them was a reading of 3 of 481. `bin/blind-vocabulary-arm.py` arms
it on every `make lint`, both directions, and prints the recall against the defaults. The blind
findings remain a worklist — DEF-055 carries their measured precision — and the campaign publishes
no blind number.
