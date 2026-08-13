# F1 — Swift workspace, shared kit, and the three targets

**Depends on:** nothing. Everything else depends on this.

Replace the single hand-rolled `app/MCPRouter.xcodeproj` with an XcodeGen-driven
workspace carrying three targets and one shared library:

- `MCPRouterKit` — models, control-API client, design tokens, formatting. Shared by
  both apps and by the Swift router's tests.
- `MCPRouter` (macOS 15+) — the app. **Direct distribution**: Developer ID, hardened
  runtime, notarized DMG, **no App Sandbox** (it spawns arbitrary MCP subprocesses and
  rewrites `~/.claude.json`, both of which the sandbox forbids). Entitlements must be
  written for this, not retrofitted.
- `MCPRouter iOS` (iOS 18+) — the companion. App Store/TestFlight, sandboxed, no
  entitlement it does not use.

Also owed: `.swiftformat` + `.swiftlint.yml`, a `Makefile`/`just` entry for
`generate → build → test`, a CI workflow that builds both targets and runs tests on
macOS runners, and `planning/practices/SWIFT_PRACTICES.md` — the two inherited practices
docs are TypeScript/Next.js and carry no Swift guidance at all, which is a real gap for
every runner after this one.

The existing 12 Swift files in `app/Sources/` are a partial scaffold from an earlier
session; treat them as a starting point to fold in, not as authority.
