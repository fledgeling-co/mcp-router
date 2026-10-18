# plan-WIN7 — the Windows Discover board

| | |
|---|---|
| ID | WIN7 |
| Spec | `planning/specs/spec-WIN7.md` |
| Size tier | Standard — one board surface, one real client, one headless suite |
| Build order | Model first (headless-testable), then the WinUI board, then the shell wiring, then gates |
| Mock | `design/mocks/mac-surfaces.html` §4, overridden where stale by `design/mcp-router-console.html` + DESIGN.md §6 (rulings recorded in spec §2, §4) |

---

## 1 · Files this item creates or touches

```
app/windows/MCPRouter.Shell.Model/
  Registry/RegistryModels.cs          wire shapes of GET /registry/search (exact superset keys)
  Registry/RegistryText.cs            sanitiser, monogram, invariant decimal, instrument formatting
  Registry/DiscoverCopy.cs            every user-facing string, keyed surface × state (§6 rule)
  Registry/RegistryPresentation.cs    provenance, date meaning + cell, figure, subtitle, notes,
                                      footer notes (trending note always), empty messages,
                                      warning classification, state resolution
  Registry/DiscoverBands.cs           the two bands, window scoping, band-empty-within-results
  Registry/RegistryCapability.cs      statement, action states, declaration, missing requirements
  Registry/RegistryClient.cs          HttpClient over 127.0.0.1:{port}; token only for POST
  Registry/ControlEndpoint.cs         port from servers.json top-level "port" else 8879;
                                      token path under MCP_ROUTER_HOME or %USERPROFILE%
app/windows/MCPRouter.Shell/
  Views/DiscoverBoard.xaml(.cs)       the board: header, controls, bands, states, notes
  Views/DiscoverDetailDialog.cs       the detail ContentDialog + install action
  Shell/ShellWindow.xaml.cs           ShowDestination: the one-line route to the real board
app/windows/MCPRouter.Shell.Tests/
  RegistryModelsTests.cs              wire parsing incl. installed flag, unknown-field tolerance
  RegistryTextTests.cs                sanitiser families, cap, monogram, invariant formatting
  RegistryPresentationTests.cs        provenance, dates, figures, notes, warning classes,
                                      state resolution (rate-limit ≠ empty), empty messages
  DiscoverBandsTests.cs               membership/absence/ordering/window asymmetry/band empties
  RegistryCapabilityTests.cs          statement, host authority, action states, declaration
                                      (shown == sent; name field; no force), missing values
  RegistryClientTests.cs              real loopback HttpListener: search parse, 502, refusal,
                                      unreachable, POST header/body/content-type, 401/409/422,
                                      token path resolution
  DiscoverCopyTests.cs                every key reached; token substitution; sentence case gate;
                                      no rate/delta/percentage anywhere (the brief's rule as a test)
planning/specs/spec-WIN7.md           this item's spec (authored with the plan, committed)
planning/plans/plan-WIN7.md           this file
```

The only pre-existing file touched is `ShellWindow.xaml.cs` (one routed line in
`ShowDestination`), kept minimal so the seven parallel W3 board runners' merges stay clean.

## 2 · Sequencing

1. **Model + tests first** (`Registry/` + the five suite files), verified by `dotnet test` —
   headless, no WinUI, the only gate that can run per-commit here.
2. **The board XAML + code-behind** against the finished model, then the detail dialog.
3. **Shell wiring** — `ShowDestination` routes `discover` to the board; everything else keeps
   its placeholder.
4. **Build** via `scripts/windows/build-shell.ps1` (MSBuild `-t:Restore` then `-t:Build`, the
   only lane that compiles WinUI here), then `dotnet test`, then the verify lane's portable
   subset, then the shell self-test (`--selftest`) for the two appearance captures.
5. **Live integration attempt**: start the real router (`node`/`npm` present on this machine —
   verify), poll `GET /registry/search` from the client, record the true verdict. If the
   registry or the router is unreachable, that state is the board's honest draw and the item
   records NOT-RUN with the measured reason.
6. Commit named paths on `ai/win7`. **Stop before verify and merge.**

## 3 · Test seams

- Everything behavioural lives in `MCPRouter.Shell.Model` (plain net8.0) — the same seam WIN3
  chose so gates run headless. The WinUI layer draws answers and decides nothing.
- `RegistryClientTests` hosts a real `HttpListener` on a random loopback port per test — the
  real HTTP boundary, no mock framework, no fabricated JSON beyond the fixture the test writes.
- The Windows-API surface used by the model is none: token reading, JSON and HTTP are all BCL.
- The board's UIA names are set in code beside the controls that draw them; the self-test's
  existing destination sweep captures the board (asserting only that it drew and is titled) —
  deeper UIA assertion belongs to WIN20's plane, which this board feeds by naming everything.

## 4 · Coverage against the state matrix (spec §5)

| State | Covered by |
|---|---|
| Loading | board renders skeleton + slow note; unit-tested via copy key and `BoardState` |
| Populated | bands + rows; `DiscoverBandsTests` + presentation tests |
| Partial | `RegistryPresentationTests` classifies all four warning classes; resolve() returns partial for empty+warnings (the brief's named worst state) |
| Stale | model keeps last response + error; test in presentation tests |
| Empty ×2, band-empty ×3 | copy keys + resolution tests |
| Disconnected / Failed | closed reason enum tests; board renders the pane |
| Overflow | truncation in XAML; full value in dialog; row heights fixed |
| Install | `RegistryCapabilityTests` incl. shown==sent argv invariant and no-force |

## 5 · Risks

- **WinUI compile quirks** (XAML metadata on cold obj/) — mitigated by the two-invocation build
  the lane already pins.
- **Live registry reachability from this machine** — the integration is attempted honestly; the
  unreachable draw is designed, not a failure mode.
- **Concurrent W3 runners** — the only shared file edit is one line in `ShowDestination`; the
  Model `Registry/` folder and test files are new named paths, collision-free by construction.
