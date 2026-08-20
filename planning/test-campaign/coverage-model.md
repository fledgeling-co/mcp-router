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
