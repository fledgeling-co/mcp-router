# M29 gap-fix — the band's missing term, and five oracles that could not fail

`"Disable a server" is drawn with nothing behind it` · branch `ai/m29` · worktree `.worktrees/M29`
Base `0e5ff49` · verdict answered: **Needs More Work**, 2026-08-26, first verification, at `a526031`.

Delivered and ready to verify. Not verified here, not merged.

Six commits, `a5f9b6e` → `1992efe`. Tree clean.

---

## WO-1 — the band consulted three fields and never the switch  · FIXED

`MenuBarPresentation.AttentionCause.causes(for:)` read `pendingChange`, `auth` and `indexError`
while `MCPServer.needsAttention` carried a `!disabled` term it did not. One disabled server holding
a schema change therefore produced `needsAttention == false` and `attentionRows ==
["sift|heldChange"]` at the same instant: a menu-bar row under an unlit dot, opening a sheet whose
`Disable` button was already dimmed.

The guard is the same term, in the one function the band and the dot both resolve through. Three
assertions:

- the case as measured, with the control — the same server switched on is exactly one row;
- **the cross product** of `disabled` × held × unauthorised × index-failed, 16 arms, asserting
  `rows.isEmpty == !dot` and that the spoken label counts what the band lists. The defect was one
  term missing from one of two expressions that are meant to be the same condition, and only the
  combination `disabled` × *a cause* exposed it;
- `PopoverContent` at the call site, which maps the unfiltered list.

Seen red with the guard removed (`causes(for:)` returned all three causes; the popover drew the
row), green with it restored byte-identically — `MenuBarPresentation.swift` sha256
`e2f1ed5774e4526deb2a94ece2b4a12575ae6678e24e035f7ca69625f3e71668` before and after.

**The audit found no second instance.** Every reader of `pendingChange`, `auth.supported`,
`indexError` and `placard` outside `RouterCore` was checked: `JackPresentation.forServer` already
returns `.dormant` for a disabled server above every other arm, `ServerFilter.needsYou` carries its
own guard (DIS-7), `ReadoutModel.serversNeedingAttention` reads `needsAttention`. The two
`unindexed`/`notIndexed` counts do include a disabled server whose index failed, and that is
consistent rather than a defect — the branch's own rule is that disabling does not change what the
router holds, which is why `ServerRowModel.indexedTools` counts it too.

## WO-2 — `writesInFlight` had no oracle  · FIXED

Deleting `writesInFlight.insert(name)` and its `defer` together left all 1960 tests passing,
because every assertion ran after the write returned and an empty set is also what a mechanism
that never inserts produces.

The recording client gains a `duringPatch` hook — test-only, no production change — which is the
one moment the set state exists. The assertion is paired with the dim it drives:
`ServerRowView.disabledReason` reads `Applying…` while the mark is held and `nil` when it is not.

Proved by that exact deletion: 1 red of 23 across the three board-write suites, and only the new
assertion. `ServersBoardWrites.swift` restored to sha256
`eaf158e5b13712b8bffb2845b48a69707a12fcbeb1a018c7d07251e6b763410c`.

## WO-3 — the automatic-sweep skip, and reindex  · FIXED

Both Swift guards were unmeasured; deleting them together left the suite green.

**The serving process.** The stale-manifest filter moves out of `RouterService.start()` into
`staleManifestWarning(_:upstreams:)`, because `start()` binds a port and spawns a server and
nothing in the suite could reach a decision made inside it. Behaviour, payload and log ordering
relative to the control-token line are unchanged. Asserted against a cold manifest, which makes
*every* upstream stale — so the only thing that can keep one out of the warning is the switch — and
in the rendered text as well as the payload, since `parity-log.sh` diffs the line.

**The watcher.** The guard stays where it is, asserted end to end by whether a child process ever
ran: the scratch child announces itself by creating a file before it answers anything, so "never
spawned" is measured rather than inferred from a filtered list. Control in the opposite direction —
the same entry with the switch cleared is spawned, indexed and adopted.

**Reindex.** `POST /servers/:name/reindex` reaches the indexer for a disabled server, through
`ControlHandler.handle` rather than by calling the indexer, because the hazard is a `disabled`
check added at the dispatch arm as an obvious tidy-up — which would remove the only way to re-read
a switched-off server's tool surface before switching it back on. Still 401 without the control
token. `ControlAuthSupport.makeDeps` gains an optional `config:` defaulting to the existing
fixture, so every prior caller reads as it did.

## WO-4 — oracles 12 and 18 were unmeasurable  · FIXED

`disableLabel` and `disableReason` were private computed properties on a `View` with zero test
references; nothing in the repo read the row's `accessibilityValue`. The two become statics, the
spoken value becomes `ServerRowView.accessibilityValueText`, and both are asserted with controls
in both directions — a live row speaks neither string, and a row showing a failed write speaks the
failure it is showing.

**And the binding, which the copy assertions do not state on their own.** A static returning the
right string proves nothing if `body` stopped calling it. There is no accessor for a `Button`'s
label on this host, so it is read off the source with `SheetShortcutScan`, the instrument this repo
already uses for keyboard shortcuts for exactly that reason: the destructive control's declaration
must name `Self.disableLabel(serverName)`, must carry no literal label, and all three carriers of
the dimmed reason — `.disabled`, `.help`, `.accessibilityHint` — must read the one function.

`make mock-fidelity SURFACE=servers` is confirmed **inherited**: exit 3,
`MeasureDump/main.swift:206` non-exhaustive switch missing `.readme`, sha256
`b243a9ed9aff68d579eb821446e4bf734c03d1bebf1ebcdb75c11a809c776dfc` on this branch and on `main`.
So M29's redrawn row remains unmeasured against the mock, and the unit-reachable oracle is the
route rather than a preference.

## WO-5 — the tautological assertion  · FIXED

`aRefusedEnableSaysWhatTheErrorSays` asserted `recorded == .routerNotRunning` and then compared
`recorded.userFacingDescription` to `ControlAPIError.routerNotRunning.userFacingDescription` — two
spellings of one payload-free case, so no implementation could fail it. The write is now refused
with a `.server(status:message:hint:)`, and the assertion is that the router's own two sentences
and its status survive into the rendered text unrewritten, with a second refusal as control.

## The out-of-family pass, and what it changed

`agy --model gemini-3.7-flash-high`, `--new-project` from `/tmp`, on the gap-fix diff. Answered on
subject with file and line references from the diff — **not degraded**. Three of its five sections
returned no finding, including the two the prompt pointed it at (the `staleManifestWarning`
extraction, the `duringPatch` hook).

Two findings taken:

- `#expect(rendered == "\(recorded.headline). \(recorded.advice)")` was a value against itself,
  since `userFacingDescription` is those two joined — **the shape this round exists to remove,
  reintroduced one line below it.** Replaced with the row reading the stored error.
- the copy statics were asserted in isolation from the button that draws them. That is DIS-16 and
  the source-scan guard above.

## Gates, with exit codes, on the final tree

| Gate | Exit | Reading |
|---|---|---|
| `make test` | **0** | 1977 tests in 251 suites (from 1960/248 at the verdict) |
| `make lint` | **0** | 0 violations, 648 files |
| `make parity` | **0** | 367 vector cases, floor 367 |
| `scripts/acceptance/parity-control.sh` | **0** | 56 rows, 56 ok |
| `npm run build` | **0** | `tsc -p tsconfig.json` |
| `scripts/red-green.py` DIS-1…16 | **0** | **16/16 KILLED**, each arm run against only the test it names |
| `make mock-fidelity SURFACE=servers` | **3** | **inherited**, byte-identical to `main` |
| `scripts/acceptance/parity-manifest-check.sh` | **1** | **inherited**, census pin 94 vs 96 |

Nine mutations were applied to the worktree during the proving passes and every one was reverted
and hash-verified; one arm was cut short by a caller-side timeout and left `ServersBoardWrites.swift`
mutated, which is recorded here rather than quietly fixed — restored from git and re-run alone.
`git status --porcelain` empty at the end.

## Red-green: the eight new arms

| Arm | Mutation | Kills |
|---|---|---|
| DIS-8 | `causes(for:)` loses its `!disabled` guard | the band case, the cross product, the popover |
| DIS-9 | the whole in-flight mechanism is deleted | the mark is set during the write |
| DIS-10 | the stale warning loses its `disabled` term | both warning tests |
| DIS-11 | the watcher's sweep loses its guard | no child is spawned for a disabled entry |
| DIS-12 | a `disabled` skip is **added** at the reindex arm | reindex reaches a disabled server |
| DIS-13 | the spoken value drops `tools withheld` | the disabled row's accessibility value |
| DIS-14 | the sheet's label reverts to `Remove` | the button names its subject |
| DIS-15 | a refused write is re-worded | oracle 17 |
| DIS-16 | the button takes a literal that renders identically | the binding guard alone |

DIS-9, DIS-10, DIS-11 and DIS-15 are the exact deletions the verifier ran; each left 1960 tests
passing before this round. DIS-16 renders the same label as the code it replaces, so every
assertion on the returned string survives it and only the binding guard bites.

## Not fixed, and why

- **`ShellModelBadges.menuContext`** asks whether the selected server is tripped from its placard
  alone, so the *Reset Server* menu command stays live for a disabled server carrying one. Noted,
  not fixed: it is outside the work order, and reset on a disabled server is harmless by this
  item's own line 5 — reindex is the user asking, and the switch does not stop it.
- **The two inherited gates**, confirmed rather than chased, per the work order.
