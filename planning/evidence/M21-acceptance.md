# M21 — acceptance evidence

`planning/practices/UI_VERIFICATION.md` rule 2. Append; never rewrite.

M21 changes token *values*, so every surface in the app renders differently and none changes shape.
Re-photographing all eight boards would be the sweep rule 2 exists to stop: what changed under them
is one palette, and the one screen-level claim worth making is that the new values reach the screen
at all. That is what the row below measures.

| Screen | How verified | Commit | Result |
|---|---|---|---|
| The shell — all eight boards, menu bar, keyboard, restoration | `scripts/acceptance/mac-shell.sh` against the Release build, driven through the accessibility plane by pid, never frontmost (script asserts this itself and reported `MCP Router was never the frontmost application during this run`) | `9957bb9` | **exit 0, 52 ok**. A first run at the same commit exited 1 at the scroll edge; see `planning/progress/M21.md` for both runs and why the failure is not attributed here |
| The scroll-edge separator (Servers) | Same run, `axkit veil` over a window-scoped `screencapture -l`, at rest and at scroll offset 0.95 | `9957bb9` | **opacity 0.0000 at rest → 0.0921 scrolled → 0.0000 returned.** M13 measured 0.0756 against the old `--line` at `#FFF @7.5%`; 0.0921 is the new `#FFF @9%`. The document, the token and the pixel agree — this is the one place a token value was read off the screen rather than out of a file |
| Both shells' window ground | `scripts/acceptance/shells.sh` — **not run**. Its token extraction was repointed at `ColorToken+Appearance.swift` and verified in isolation (dark `#1C1C1E`, light `#FFFFFF`); the script itself launches and drives both the Mac app and a simulator | `382026c` | **owed.** The extraction it depends on is proven; the render assertion is not |
| The four appearance contexts as rendered | Not attempted | — | **not possible here.** No engine available to this project applies `prefers-contrast`, so light+contrast and dark+contrast are computed and specified, never photographed |
