# Reverify R22: daemon diagnostics bundle export

**Verdict: RETIRED.**

- **Scope.** DEF-361, retrospective verdict for `N7` (merge `5f63f24f`). Requirement REQ-035, cases CASE-0270 to CASE-0275.
- **Requirements, derived from documents alone.** Brief `planning/features-to-triage/daemon-diagnostics-bundle-export.md` (acceptance lines 16–20); spec `planning/specs/spec-R22.md` (§2, §3.1–§3.6, §4, §5, §6); plan `planning/plans/plan-R22.md`; LEDGER and ORCHESTRATOR rows R22. The code was not opened until this table was drafted.
- **Tree checked.** main at `fe3b09b9`. Relevant Swift paths are unchanged since `63d7e208`.
- **Why RETIRED.** `plan-retire-swift-router.md` (Feature inventory, row "R22 diagnostics") says **DROP** (decision 1). The two routes exist only in the Swift router. The brief's two deferred surfaces, the menu item and the zip archive (R22-C1 and R22-C2), were never built, so there is nothing to retire on the client side. Same caveat as F5: decision 1 is still listed for the owner to confirm.

## Requirements

| # | Requirement | Source | Verdict | Evidence |
|---|---|---|---|---|
| B1 | Export Diagnostics action in the application menu and settings view | brief line 16; spec §2 R22-C1 | RETIRED | Never built. `export diagnostics` (case-insensitive) matches nothing in `app/Sources` or `app/MCPRouter` on `fe3b09b9`. |
| B2 | Archive includes recent router logs, upstream statuses and process summaries | brief line 17 | RETIRED | Preview categories: `categories.append(categoryValue("routerLog", available: true, count: lines.count))`, `app/Sources/RouterCore/Control/ControlDiagnosticsJSON.swift:29` at `fe3b09b9`; server and live-upstream counts at lines 23–24. The single zip archive is R22-C2 and was never built (spec §2: the router answers a document and the app writes the file). |
| B3 | Sensitive values, tokens and personal file paths are redacted | brief line 18 | RETIRED | Layer 1, structural: `` `envKeys` `` / `and never a value`, `app/Sources/RouterCore/Diagnostics/DiagnosticsBundle.swift:17` at `fe3b09b9`. Layer 2, by value: `SecretNeedles.variants(of: needle.literal)`, `app/Sources/RouterCore/Diagnostics/SecretRedactor.swift:41` at `fe3b09b9`. Home paths: `public struct HomePathElision: Sendable {`, `app/Sources/RouterCore/Diagnostics/SecretRedactor.swift:122` at `fe3b09b9`. |
| B4 | Bundle generated in under two seconds, with a save prompt | brief line 19 | RETIRED | Not built (R22-C2). No timing exists. |
| B5 | User previews categories and confirmed redactions before writing | brief line 20 | RETIRED | Preview route: `case ("/diagnostics", "GET"):`, `app/Sources/RouterCore/Control/ControlDiagnostics.swift:34` at `fe3b09b9`. The write confirmation (the menu and save panel) is R22-C1 and was never built. |
| S3.1 | Layer 1 never places an env value, header value, URL userinfo or query value in the document | spec §3.1 | RETIRED | `authority = "<redacted:userinfo>@"`, `app/Sources/RouterCore/Diagnostics/DiagnosticsBundle.swift:126` at `fe3b09b9`, and `"=<redacted:query>"`, `app/Sources/RouterCore/Diagnostics/DiagnosticsBundle.swift:133` at `fe3b09b9`. A userinfo or query value is replaced with a marker, not gathered. |
| S3.2 | Layer 2 removes every known secret value from every surviving string, once, at the end | spec §3.2 | RETIRED | `Built raw, then passed through layer 2 and layer 3`, `app/Sources/RouterCore/Control/ControlDiagnosticsJSON.swift:78` at `fe3b09b9`. Layer 2 keeps object keys as well as values: `layer 2 keeps object keys and redacts values`, line 107. |
| S3.3 | Literal, percent-encoded and base64 forms are needles | spec §3.3 | RETIRED | `static func variants(of literal: String) -> [String] {`, `app/Sources/RouterCore/Diagnostics/SecretNeedles.swift:135` at `fe3b09b9`. |
| S3.4 | Needles shorter than 8 characters are not used, and are named in `unscrubbable` | spec §3.4 | RETIRED | `public static let minimumNeedleLength = 8`, `app/Sources/RouterCore/Diagnostics/SecretNeedles.swift:61` at `fe3b09b9`. `} else if value.count < minimumNeedleLength {`, line 94. |
| S3.5 | A withheld value is a bucket (`empty`, `short`, `present`), not a character count | spec §3.5 | RETIRED | `if value.count < SecretNeedles.minimumNeedleLength { return .short }`, `app/Sources/RouterCore/Diagnostics/DiagnosticsBundle.swift:53` at `fe3b09b9`. |
| S3.6 | No new optional dependency on `ControlDeps` | spec §3.6 | RETIRED | `git grep -i diagnostic` in `app/Sources/RouterCore/Control/ControlPorts.swift` on `fe3b09b9` returns nothing. |
| S4a | `POST /diagnostics/bundle` mutates nothing, and the verb selects the token gate | spec §4 | RETIRED | `return method == "POST" || method == "DELETE" || method == "PATCH"`, `app/Sources/RouterCore/Control/ControlAPIRequest.swift:86` at `fe3b09b9`. Route: `case ("/diagnostics/bundle", "POST"):`, `app/Sources/RouterCore/Control/ControlDiagnostics.swift:36` at `fe3b09b9`. |
| S4b | The preview discloses nothing that `GET /servers` does not | spec §4 | RETIRED | Preview route is the GET at row B5. The preview's log canary check (CASE-0274) lives in `r22-diagnostics.sh`, which did not run (Tests). |
| S4c | Routes are exact matches; a closed family | spec §4 | RETIRED | The only two arms are `case ("/diagnostics", "GET"):`, `app/Sources/RouterCore/Control/ControlDiagnostics.swift:34` at `fe3b09b9`, and `case ("/diagnostics/bundle", "POST"):`, `app/Sources/RouterCore/Control/ControlDiagnostics.swift:36` at `fe3b09b9`. A default arm returns `nil`. |
| S4d | An unreadable log is reported `available: false` with a reason, not as an empty array | spec §4 | RETIRED | `An unreadable log is reported as`, `app/Sources/RouterCore/Control/ControlDiagnosticsJSON.swift:260` at `fe3b09b9`. `JSONMember(key: "available", value: .bool(false)),` at line 272. |
| S5 | Socket lane, unit suite and eight arms | spec §5 | RETIRED | See Tests. None ran. |
| S6a | DEF-070: `GET /servers` publishes argv whole | spec §6 | RETIRED, with a note | The spec records DEF-070 as filed and not fixed. `planning/test-campaign/inventory.json` now reads `fixed · in-test`. On main the TypeScript `GET /servers` path does apply the argv scrub: `args: redactArgs(u.args, needles)`, `src/control.ts:297` at `fe3b09b9`. This audit did not verify that the TypeScript fix covers every case the Swift residual named. |
| S6b | A token minted after the config was written has no needle | spec §6 | RETIRED | Not re-checked. It is a residual the spec declares, and the code is unreachable on this tree. |

## Shipped clients

No client calls `/diagnostics` or `/diagnostics/bundle`. The Mac and Windows hits for `diagnostics` are `ControlTokenStore.swift` (client-side diagnostics, not a call) and the Windows test fixture. No DEF is filed from this item.

## Tests and lanes

- `swift test` (see the F5 report): `warning: No matching test cases were run`, `EXIT=0`. `ControlDiagnosticsTests` is not in any declared target. Not run.
- `scripts/acceptance/r22-diagnostics.sh`: exit 2. `environment: no MCPRouterCLI at /Volumes/LLMs/Dev/mcp-router-wt/reverify-3/app/.build/debug/MCPRouterCLI (run: make build-cli-debug)`.
- `planning/test-campaign/bin/arm-r22-diagnostics.sh` is present but was not run; it drives the Swift daemon.
- `planning/test-campaign/cases.json` lists CASE-0270 with `status: pass`. No run on this tree backs it.

## Open

1. Owner confirmation of plan decision 1, as in F5.
2. DEF-070 status. The spec (filed, not fixed) and `inventory.json` (`fixed · in-test`) disagree. Owner to confirm which closure applies, and whether the TypeScript fix covers the Swift residual.
3. R22-C1 and R22-C2 were never built, and nothing in the plan schedules them. If the owner wants the diagnostics bundle on the TypeScript router, it is a new item.
