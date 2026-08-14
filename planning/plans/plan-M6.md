# plan-M6 — Inbox and pairing (Mac)

Implements `planning/specs/spec-M6.md`. Tier: **Standard** — two surfaces, one new Kit seam, one
registry retirement, and a documented set of test amendments.

Nothing here restates the spec. This is the file manifest, the build order, and the decisions that
are about *construction* rather than about behaviour.

---

## Build order

Each phase leaves the tree compiling. Phase C is the one that flips the registry, and it is late on
purpose: until the board exists, registering `.inbox` would put an empty pane in front of the user
and break every tripwire for no gain.

### Phase A — the Kit seams (no UI, no registry change)

| File | Contents |
|---|---|
| `Kit/Pairing/MacPairing.swift` *(written)* | `PairingEndpoint`, `PairingAvailability`, `IssuedPairingCode`, `PairingRefusal`, `MacPairing` — issue, payload, encode, decide, outcome |
| `Kit/Inbox/InboxModels.swift` | `InboxItem`, `InboxEnvelope` (two-pass decode, closed version set, `InboxEnvelopeError`), `InboxItemState` |
| `Kit/Inbox/InboxService.swift` | `protocol InboxService` + `FixtureInboxService` with the eight scenarios |
| `Kit/Inbox/InboxCopy.swift` | Every user-facing string, held as data so a test reads copy without a host — the shape `PairingCopy` and `SkillCopy` already use |

`InboxItem` resolution is the load-bearing decision: an item holds its envelope **and** an optional
resolved `RegistryEntry`. `nil` is the Partial state, and it is what makes "cannot be accepted"
structural rather than a rule the view remembers — the accept path takes a resolved entry, so an
unresolved item has nothing to pass it.

### Phase B — the surfaces

| File | Contents |
|---|---|
| `UI/Shell/ShellPairingFactory.swift` | The Debug/Release choice, `MCPROUTER_PAIRING`, and the two makers. Mirrors `ShellClientFactory` exactly, including that the Release branch takes no input. |
| `UI/Boards/InboxBoardModel.swift` | `@MainActor @Observable`; load, dispositions, single-slot undo, selection, keyboard |
| `UI/Boards/InboxBoard.swift` | The pane: header, rows, states |
| `UI/Boards/InboxBoardRow.swift` | The 56pt row |
| `UI/Boards/InboxReviewSheet.swift` | M6's own sheet, calling `RegistryCapability` |
| `UI/Boards/PairingSheet.swift` | The Mac pairing sheet, both availability branches |
| `UI/Boards/PairingQRView.swift` | The QR, drawn from the encoded bytes |
| `UI/Boards/InboxBoardMetrics.swift` | Row and column geometry, from tokens only |

**The QR.** Drawn with `CoreImage`'s `CIQRCodeGenerator`, which is in the platform and needs no
dependency — the kit's no-external-dependencies promise holds. It renders the bytes
`MacPairing.encode` produced and nothing else; there is no second encoder and no string built in the
view. It is the one place a fabricated endpoint could reach a user, so the view takes the *encoded
text* rather than the payload, and cannot construct one itself.

### Phase C — register, retire the placeholder, and amend its tests **in one commit**

The plan gate was right that splitting this breaks the tree, and the breakage is not theoretical:
`ActivityBoardContractTests.swift:204` asserts `ScaffoldedDestination(.inbox) != nil` and goes red on
the registry line alone, before any type is deleted. `ShellWindow.swift:71-74` stops compiling the
moment the type goes. So the deletion, the registration and every test amendment land together.

1. `ScaffoldPane.swift`: delete `ScaffoldedDestination`, `ScaffoldCopy`, `ScaffoldPane`; add
   `.inbox` to `installed`; keep `BoardRegistry` and the file's path. Add the retired sentence as a
   comment in the `sentinel = "…"` shape, **placed below the closing `]`** — above it, the awk in
   `board-registry.sh` would accumulate a second `[` into its line before matching.
2. `ShellWindow.swift`: delete the scaffold branch in `body`; replace `case .inbox: EmptyView()`
   with `InboxBoard`; `ContentZone`'s doc comment loses its placeholder sentence.
3. `ShellModel.swift`: `inboxBoard` lazy var; `badge(for:)` switches on `BadgeSource`.
4. `Destination.swift`: `BadgeSource.queuedFromPhone`; `.inbox` returns it; both doc comments
   corrected.
5. **`ReadoutModel.swift:209`** — `badgeCount(from:)` lives here, not in `Destination.swift`. It
   gains the `.queuedFromPhone` case and returns `nil` for it, because an inbox count is not derived
   from `[MCPServer]`. The gate caught this file being missing from the plan.
6. `ShellCommandRouter.swift`: `pairPhone` stops routing to `.none`.
7. Every test in `spec-M6.md`'s amendment table, same commit.

**Only one reader matches the sentinel**, not two: `mac-shell.sh:884` greps it out of the source;
`board-registry.sh` never reads it. The comment form works because that grep is a source-text scan
with no comment awareness, while the Release assertion at `:952` scans compiled files, which never
carry comments. **Four** acceptance scripts read the file's path — `mac-shell.sh`, `m2-activity.sh`,
`m5-discover.sh`, `m7-evals-cleanup.sh` — which is why the path and the filename are preserved.

**The 400-line cap is a real risk in `ShellModel.swift` (366 today), and the first split seam named
here was wrong.** All six board properties are `lazy var` — stored properties, which Swift forbids in
an extension — so a `ShellModel+Boards.swift` holding them would not compile. If the cap is crossed,
the split moves *methods* (the command and keyboard routing) into an extension, which is legal, and
never raises the limit.

### Phase D — tests, then the gates

Test files: `InboxBoardTests`, `MacPairingTests`, `MacPairingWireTests`, `InboxEnvelopeTests`,
`PairingSheetTests`, plus the amendments enumerated in the spec.

Then: `make lint`, `make test`, `make build-mac`, the parity gate, and **one** acceptance script,
`scripts/acceptance/m6-inbox-pairing.sh`, covering the Inbox pane and the pairing sheet and nothing
else. It sources `board-registry.sh` like every other board script, launches with `open -g`, drives
by pid through the accessibility plane, asserts MCP Router never became frontmost, and quits.

---

## Red-green proving

`SWIFT_PRACTICES.md` §7: a test that has never failed is not known to work. Each of these is broken
deliberately, watched go red, and restored — recorded in the evidence file.

| # | Mutation | The test that must catch it |
|---|---|---|
| M1 | `MacPairing.decide` checks live before spent | `alreadyUsed` while a newer code is live |
| M2 | `randomCanonicalCharacters` draws from a wider alphabet | the `I`/`L`/`O`/`U` exclusion, asserted **on that function directly** — `issue` ends in a `preconditionFailure`, which is a process trap no test can catch, so a mutation routed through `issue` would crash the run rather than fail an assertion |
| M3 | `encode` writes `"type"` instead of `"t"` | wire conformance through I1's decoder |
| M4 | The Release branch of `ShellPairingFactory` reads the environment | A6 |
| M5 | `InboxEnvelope` decodes a missing `entry` to `""` | the named-failure test — the silent-empty read `SWIFT_PRACTICES.md` §2 forbids |
| M6 | Accept path passes `force: true` | `RecordingControlAPIClient`'s call assertion |
| M7 | `badge(for: .inbox)` counts the loaded snapshot rather than the rendered rows | A18, **after a decline** — the two are equal until an item is dispositioned, which is exactly why the assertion has to be made on a board that has been acted on |
| M8 | `installed` drops `.inbox` | the complement and set assertions |

**`RecordingControlAPIClient`** does not exist in the repo and is written in Phase B: a
`ControlAPIClient` decorator that counts calls per method, so A13 can assert `add` was called once
with `force == false` and that declining, loading and rendering called it zero times. A test that
merely observes a row disappearing cannot tell an install from a local mutation.

---

## What is deliberately not done

- No transport, no listener, no phone client (spec D-m6-a).
- `ScaffoldPane.swift` is not renamed (D-m6-c) — four other items' scripts read its path.
- The menu-bar popover gains no inbox band (D-m6-d) — M8's surface.
- M5's `DiscoverDetailSheet` and M7's files are **read and called, never edited**.
- `m6-inbox-pairing.sh` is **not** added to `make acceptance`, which lists only `shells.sh`,
  `control-client.sh` and `mac-shell.sh`. That is the house pattern rather than an omission: M2's,
  M5's and M7's board scripts are all absent from it too, because the target is the shell's own
  gate and a per-board script is run by the item that owns it. The plan gate suggested adding it;
  following it would have made this item the only one whose board script ran on every build.

---

## Plan gate

`codex: usage limit -> claude (downgrade)`. Adversarial in-family reviewer, verdict **AMEND**. Seven
findings, all dispositioned; three were live defects in code already written.

| # | Finding | Disposition |
|---|---|---|
| 1 | Phase C leaves the tree non-compiling; five test files reference the deleted types, and `ActivityBoardContractTests:204` goes red on the registry line alone | **Accepted.** Deletion, registration and every test amendment are now one commit. |
| 2 | `ShellModel+Boards.swift` cannot compile — `lazy var` is a stored property and Swift forbids those in extensions | **Accepted.** The seam is methods, not properties. |
| 3 | `ISO8601Instant.string` emits whole seconds while its parser accepts fractional, so a `Date()`-derived expiry round-trips lossily and A9 fails against a correct payload | **Accepted — a real defect.** Fixed at the source rather than by loosening the assertion: `issue` truncates the expiry to whole seconds, which is also the only precision a pairing window means. |
| 4 | `supportedVersions.max() ?? 1` reintroduces the literal and picks the wrong end of the set | **Accepted.** Replaced with `MacPairing.wireVersion`, plus a test that it is in `supportedVersions`. |
| 5 | `preconditionFailure` makes M2 a process trap no test can catch | **Accepted.** `randomCanonicalCharacters` extracted and tested directly; the precondition stays as an invariant nothing depends on reaching. |
| 6 | `decide(spent: Set<String>)` should be `Set<PairingCode>`; the "used in the Mac's own log line" claim is false | **Accepted both.** Typed set; the false sentence deleted rather than made true. |
| 7 | `ReadoutModel.swift` holds `badgeCount(from:)` and was missing from Phase C; `m6-inbox-pairing.sh` is not in the Makefile; "five scripts" is four | **Accepted for `ReadoutModel.swift` and the count (verified: four scripts). Rejected for the Makefile** — per-board scripts are deliberately outside `make acceptance`, as M2's, M5's and M7's all are. |
