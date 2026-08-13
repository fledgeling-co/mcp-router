# SWIFT_PRACTICES.md

**Audience: AI coding assistants writing or modifying Swift in this repo.** This is an operating
spec, not background reading — load it before you generate Swift and apply it *as you write*.

It exists because the two inherited practices documents (`CODING_PRACTICES.md`,
`NEW_PROJECT_BEST_PRACTICES.md`) are TypeScript/NestJS/Next.js and carry no Swift guidance at all.
Where they state a rule that is about engineering rather than a language — diff scope, no faked
tests, trust boundaries get runtime validation, a behaviour change updates its spec in the same
change — **those still bind here**, and this document does not repeat them.

## How to use this document (agent protocol)

1. **Apply while generating.** Treat every rule as a constraint on the code you emit, not a
   post-hoc lint.
2. **Severity keywords are load-bearing.** **MUST / NEVER** are hard constraints — violating one is
   a bug, not a style choice. **SHOULD / PREFER / AVOID** are strong defaults; deviate only with a
   stated reason.
3. **Precedence:** `DESIGN.md` (for anything that renders) > this document > `CODING_PRACTICES.md`
   (for the language-agnostic rules) > your own inference.
4. **Never silently skip a rule.** If one genuinely doesn't apply, say so in your response or a
   code comment. An unexplained deviation reads as a mistake to the next reviewer.
5. **Self-review before you report done.** Run §9 over your diff and state which files you covered.
6. **No invented APIs.** Every symbol, entitlement, build setting and path you reference must exist
   in this repo or in a pinned dependency. Swift's stdlib and SwiftUI both changed shape recently
   and a plausible-looking API is often from the wrong version — check before citing.

---

## 1. Language and concurrency

- The whole workspace is **Swift 6 language mode** with `SWIFT_STRICT_CONCURRENCY: complete`. Never
  lower either to make code compile. A concurrency error is telling you the ownership is wrong.
- Types crossing an isolation boundary **MUST** be `Sendable`. Prefer value types and `let`; reach
  for an `actor` when you genuinely have mutable shared state, not as a way to silence a warning.
- **NEVER** use `@unchecked Sendable` to get past a diagnostic. It is a promise you are making to
  the compiler, and it is only honest when the type has no mutable state or guards it with its own
  lock — say which in a comment.
- UI state is `@MainActor`. Annotate the type, not each method.
- **AVOID** `Task { }` inside a view body or an initializer. Use `.task { }`, which is cancelled
  when the view goes away — a detached task outlives the thing that wanted it.
- **NEVER** block a thread waiting on async work (`DispatchSemaphore` around a `Task`). It
  deadlocks under Swift concurrency's cooperative pool.

## 2. Boundaries and decoding

The router is a separate process speaking JSON over loopback. Everything it sends is a trust
boundary, and the shape can change under you when the router is upgraded independently of the app.

- **A closed set on the wire is a closed set in Swift.** Model it as an enum so an unrecognised
  value **fails decoding**. Do not decode into `String` and switch with a `default` that guesses.
- **Decoding MUST fail loudly on a shape it does not recognise.** The TypeScript router shipped a
  bug where a flat `servers.json` loaded **zero servers with no error at all** — the reader looked
  for a key that wasn't there and found an empty collection. A silent empty result is the worst
  failure mode available: it looks exactly like "you have no servers". Never write a decode path
  whose failure mode is emptiness.
- **NEVER** `try?` a decode and fall back to a default. Either handle the error or propagate it.
- Give every DTO an explicit `CodingKeys` when a wire name differs from the Swift name, rather than
  renaming the Swift property to match the wire.
- **The control API's `command`, `args` and `env` are never writable.** A control API that can
  rewrite a command line can run anything on the machine. Enforce this **structurally** — the PATCH
  type has no such field — and assert it against the **encoded JSON**, not the Swift type:
  reflection sees only stored properties and would miss a computed property or a `CodingKeys`
  mapping that still puts the key on the wire.

## 3. Errors

- Model errors as an `enum` conforming to `Error`, with a case per thing the caller can actually do
  something different about.
- **The offline case is first-class.** The router is loopback, so unreachable does not mean the
  network is down — it means the daemon is not running on this machine. `ControlAPIError` carries
  `routerNotRunning` as its own case for exactly this reason, and every surface renders it as its
  own state (`DESIGN.md` §5), never as a generic error banner.
- Every user-facing error string states **what happened and what to do**, sits next to the thing
  that failed, does not blame the user, and does not emote (`DESIGN.md` §6).
- **NEVER** `try!` or force-unwrap outside tests. SwiftLint is configured to make
  `force_unwrapping` an **error**. In tests a force-unwrap is a deliberate assertion and is fine.
- **NEVER** swallow an error to keep a UI tidy. If a surface cannot show it, log it and show the
  degraded state honestly.

## 4. SwiftUI

- One owner per piece of state: `@State` for state a view creates, `@Binding` for state it is lent,
  `@Observable` for a model shared across views. **AVOID** duplicating server state into `@State` —
  derive it in the body or `@Observable` it once.
- **NEVER** perform work in `body`. It runs arbitrarily often; anything expensive belongs in
  `.task`, a model, or a cached value.
- Give every list row a **stable identity**. Index-based identity bleeds state between rows when
  the collection reorders — and this product's lists reorder constantly as servers start and stop.
- Every data surface ships the **nine states** in `DESIGN.md` §5, not just the populated one, with
  real copy for the unhappy paths. A populated-only screen is a third of a design.
- Motion animates **transform and opacity only** and honours `accessibilityReduceMotion`. **NEVER
  animate opacity from 0 on entry** — content is unreadable for half the fade.

## 5. Design tokens

- **NEVER hardcode a colour, size, radius or line height.** Read `ColorToken`, `TypeToken`,
  `MetricToken` from `MCPRouterKit`. `DesignTokenParityTests` compares those against `DESIGN.md` in
  both directions and fails on drift, so a hardcoded literal is invisible to the one check that
  would have caught it being wrong.
- The four indicator colours (`--accent`, `--live`, `--attn`, `--fail`) are **exclusive to their
  meanings**. One amber dot in a menu bar only means something because nothing else is allowed to
  be amber. Never use one decoratively.
- Nothing renders off the eight-role type ladder. 13pt body is the single loudest
  native-versus-web discriminator.
- **No number is displayed that the router does not observe.** There is no fabricated memory saving
  anywhere in this product. If you want to show a figure, first find where the router measures it.

## 6. Secrets, entitlements, and process boundaries

- Tokens, credentials and anything derived from them go in the **Keychain**. **NEVER**
  `UserDefaults`, never a plist, never a file next to the app.
- **NEVER** log a token, an `Authorization` header, or a whole config object. Log the shape, not
  the value.
- **Entitlement minimalism, per platform.** Declare nothing the target does not use. Note that an
  App Sandbox permission such as `com.apple.security.network.client` grants nothing at all when
  `com.apple.security.app-sandbox` is `false` — carrying it on the unsandboxed macOS target would
  be an unused entitlement, which is why it is absent.
- The macOS app is **deliberately unsandboxed** (Developer ID, hardened runtime, notarized DMG): it
  spawns arbitrary MCP subprocesses and rewrites `~/.claude.json`, both of which App Sandbox
  forbids. Do not "fix" this by adding the sandbox. iOS is the opposite and is sandboxed.
- Subprocess arguments **MUST** be passed as an argument array, never interpolated into a shell
  string.

## 7. Testing

- **Swift Testing** (`import Testing`, `@Test`, `#expect`) for new tests.
- **A suite that runs zero tests is a failure, not a pass.** Swift Testing exits 0 when nothing
  matched, so a target that silently stops finding its test files reports success forever. `make
  test` counts `swift test list` before running and fails on zero — never route around that.
- **A test that has never failed is not known to work.** For any test whose whole job is to catch
  drift or a regression, deliberately break the thing it guards, watch it go red, then restore.
  Record that you did. This is the difference between a gate and a decoration.
- **NEVER** weaken a test to make a change pass — no deleted assertions, no loosened tolerances, no
  `.disabled()`. If the test is wrong, fix the test and say why in the same change.
- Test the boundary values, not the middle. Off-by-one at a unit boundary is the bug that ships.
- Prefer a real value over a mock. Mock only at a process or network boundary.

## 8. Project and build hygiene

- **`app/project.yml` is the source of truth; the `.xcodeproj` is generated and untracked.** Never
  hand-edit the project, and never commit it — a tracked `project.pbxproj` is a merge conflict for
  every runner working in parallel. Run `make generate` after checkout.
- One `make` entry point. CI runs the **same targets**, never its own copy of the commands — a CI
  that re-implements the build is a CI that drifts until only one of the two is trusted.
- **Pin external Swift packages to an EXACT version, never a range.** The Swift MCP SDK is pre-1.0
  and its README warns that a minor bump may break the API.
- Keep `MCPRouterKit` free of SwiftUI and of any UI framework, so the router's own tests can import
  it.
- Builds are **unsigned** locally and in CI. The release posture is configured in the `Release`
  configuration but is never *required* to build, so nobody is blocked on credentials.

## 9. Agent self-review (run before reporting the change done)

Check each against the files you actually touched, and state which files you covered.

- **Concurrency:** nothing lowered `SWIFT_STRICT_CONCURRENCY`; no `@unchecked Sendable` without a
  stated reason; no semaphore blocking async work (§1).
- **Boundaries:** every wire enum is closed and fails on an unknown value; no decode path whose
  failure mode is an empty result; no `try?`-and-default (§2).
- **The command-line guarantee:** nothing you added lets `command`, `args` or `env` reach a PATCH
  body — checked against the encoded JSON, not the type (§2).
- **Errors:** no force-unwrap or `try!` outside tests; the offline case is still distinguishable;
  every new user-facing string says what to do (§3).
- **Tokens:** no hardcoded colour, size or radius; no indicator colour used decoratively; no
  displayed number the router does not observe (§5).
- **Secrets:** nothing secret in `UserDefaults` or a log line; no entitlement added that the target
  does not use (§6).
- **Tests:** any drift/regression guard you added has been **seen to fail**; no assertion weakened;
  the test count did not silently drop (§7).
- **Gates actually run:** `make all` executed and green — report the output, don't assert it.
- **Diff scope:** every changed line traces to the task; no drive-by reformatting; the generated
  project is not staged (§8, and `CODING_PRACTICES.md` §5).

## Sources

- `DESIGN.md` — authoritative for everything that renders; §2 tokens, §3 native floor, §5 states,
  §6 words, §7 motion.
- `planning/practices/CODING_PRACTICES.md` — the language-agnostic engineering rules, which still
  bind.
- Swift 6 migration guide (strict concurrency, `Sendable`), Swift Testing documentation.
- Apple: Hardened Runtime, App Sandbox, Keychain Services; the macOS Human Interface Guidelines.
- Traps recorded from this repo's own TypeScript router: the flat-`servers.json` silent-empty read
  (§2) and the two CLI config key shapes it has to tolerate.
