# DEF-008 — native iOS tab identifiers

The five native tabs publish `tab-discover`, `tab-triage`, `tab-queue`, `tab-library` and
`tab-settings` on an owned iPhone 17 Pro Simulator running iOS 27.0, built with SDK 27.1.
Published accessibility labels remain Discover, Triage, Queue, Library and Settings.

| Implementation | Native observation |
|---|---|
| Original `tabItem` views | Five empty identifiers; correct labels; one XCUITest failed |
| Modern `SwiftUI.Tab` with `TabContent.accessibilityIdentifier` | Five empty identifiers; correct labels; one XCUITest failed |
| Modern tabs with scoped public UIKit fallback | One XCUITest passed: four inventories, fifteen target transitions from another destination, revisits and one app relaunch |
| Hosted native invariants | Four tests passed: five system tabs, no badges, scoped identifier mutation and mapping refusal |

The fallback traverses only its own controller ancestry. It changes `UITabBarItem` identifiers
on the main actor after all five ordered titles match. Selection, tint and badge values are
unchanged by the bridge. The shared presentation target also builds on macOS.

The [observation record](DEF008-tab-identifiers/observations.json) retains source hashes,
XCTest summaries and five attributed screenshots, all visually inspected. Raw result bundles
remain under `/tmp/mcpr-tab-identifiers-20261102/`:

- `baseline-assertions.xcresult`: original implementation, one expected assertion failure.
- `modern-tab.xcresult`: public TabContent modifier alone, one assertion failure.
- `uikit-identifiers.xcresult`: one passing XCUITest.
- `native-tab-invariants-verified.xcresult`: four passing hosted tests.

The XCUITest command used `xcodebuild -scheme MCPRouterIOSGlass` with
`-only-testing:MCPRouterIOSUITests/PhoneTabIdentifierTests`, the owned device ID in
`device.txt`, ad-hoc Simulator signing and an isolated derived-data directory.
The hosted run selected `PhoneTabIdentityBridgeTests` and the existing
`PhoneSurfaceTests/testTabBarCarriesNoBadges` and `testShellRendersFiveSystemTabs`.

Simulator.app was not running after the checks. Verification issued no host-app activation.
The host foreground changed from Chrome to a Warden test host during concurrent work;
that observation is retained without attributing it to this lane. A Finder reveal ran afterward
to show this new ledger, as required by the supplied AGENTS.md.

Physical devices, other iOS runtimes and VoiceOver speech output were not measured.
Fixture catalogue data is not live-service acceptance. Historical campaign records are unchanged.
