import Foundation
import Testing
@testable import MCPRouterKit

/// The Settings window's copy, and the honesty rule that decides which of the mock's thirty rows
/// this product is allowed to draw.
@Suite("Settings pane copy and honesty")
struct SettingsPaneCopyTests {
    /// `M7DesignedStateTests`' bar, reused rather than re-derived: a sentence that is present but
    /// useless is the failure, so "non-empty" is not the test.
    private static func assertUsable(_ text: String, _ label: String) {
        #expect(!text.isEmpty, "\(label) has no copy at all")
        #expect(text.count >= 12, "\(label) is too short to say anything: '\(text)'")
        for placeholder in ["TODO", "TBD", "lorem", "FIXME", "isn't built yet", "Coming soon"] {
            #expect(
                !text.lowercased().contains(placeholder.lowercased()),
                "\(label) is a placeholder, not copy: '\(text)'"
            )
        }
    }

    /// A label is not a sentence, so the twelve-character bar is applied to the sentences only.
    /// `Router` is six characters and is exactly the right label; what a title must not be is empty
    /// or a placeholder.
    private static func assertLabel(_ text: String, _ label: String) {
        #expect(!text.isEmpty, "\(label) has no copy at all")
        for placeholder in ["TODO", "TBD", "lorem", "FIXME", "Untitled", "Pane"] {
            #expect(
                text.lowercased() != placeholder.lowercased(),
                "\(label) is a placeholder, not a label: '\(text)'"
            )
        }
    }

    @Test("every pane opens with a name and a line saying what it governs")
    func everyPaneIntroducesItself() {
        for pane in SettingsPane.allCases {
            Self.assertLabel(pane.title, "\(pane.rawValue) title")
            Self.assertUsable(pane.subtitle, "\(pane.rawValue) subtitle")
        }
        // Seven distinct subtitles: a pane that borrowed another's line would be describing a
        // surface it is not.
        #expect(Set(SettingsPane.allCases.map(\.subtitle)).count == 7)
    }

    /// The three panes §4 empties draw a governing sentence; the four that draw real controls do
    /// not, and both directions are asserted so a pane cannot quietly become an empty one.
    @Test("exactly the three panes with nothing to build carry a governing sentence")
    func governanceIsOnExactlyTheEmptiedPanes() {
        let governed = SettingsPane.allCases.filter { SettingsPaneCopy.governance(for: $0) != nil }
        #expect(governed == [.harnesses, .analyst, .updates])
        for pane in governed {
            let sentence = try? #require(SettingsPaneCopy.governance(for: pane))
            Self.assertUsable(sentence ?? "", "\(pane.rawValue) governance")
        }
        for pane in [SettingsPane.router, .security, .menuBar, .advanced] {
            #expect(
                SettingsPaneCopy.governance(for: pane) == nil,
                "\(pane.title) draws real controls and must not also say it governs nothing"
            )
        }
    }

    /// A governing sentence has a job beyond being long enough: it must say **where the thing is
    /// decided**, or that it is not decided anywhere in this build. A sentence that merely restates
    /// the pane's name would pass every length check above.
    @Test("each governing sentence names where the thing is set, or says it is not built")
    func governanceSaysWhereOrSaysNot() {
        #expect(SettingsPaneCopy.harnessesGovernance.contains("mcp-router harnesses"))
        #expect(SettingsPaneCopy.harnessesGovernance.contains("mcp-router watch"))
        #expect(SettingsPaneCopy.analystGovernance.contains("This build has no session analyst"))
        #expect(SettingsPaneCopy.updatesGovernance.contains("This build checks for nothing"))
    }

    // MARK: - The honesty rule

    /// Every user-facing string this window can draw, in one place, so a rule below cannot silently
    /// stop covering a pane somebody added copy to.
    static var everyRenderedString: [String] {
        SettingsPane.allCases.flatMap { [$0.title, $0.subtitle] }
            + SettingsPane.allCases.compactMap(SettingsPaneCopy.governance(for:))
            + [
                SettingsPaneCopy.routerGroup, SettingsPaneCopy.warmSetGroup,
                SettingsPaneCopy.menuBarGroup, SettingsPaneCopy.controlTokenGroup,
                SettingsPaneCopy.pairedDevicesGroup, SettingsPaneCopy.filesGroup,
                SettingsPaneCopy.endpointLabel, SettingsPaneCopy.homeLabel,
                SettingsPaneCopy.idleLabel, SettingsPaneCopy.sinceLabel,
                SettingsPaneCopy.copyEndpointAction, SettingsPaneCopy.statusItemLabel,
                SettingsPaneCopy.pairedDevicesLabel, SettingsPaneCopy.pairedDevicesNone,
                SettingsPaneCopy.pairedDevicesAction, SettingsPaneCopy.pairedDevicesHelp,
                SettingsPaneCopy.logLabel, SettingsPaneCopy.configurationLabel,
                SettingsPaneCopy.filesHelp, SettingsPaneCopy.buildIdentityUnknown,
                SettingsPaneCopy.routerFactsUnavailable
            ]
    }

    /// **The test that fails if a later runner re-adds the mock's rows from the mock.**
    ///
    /// `spec-M15.md`'s fifth assumption is that a control naming a capability this product does not
    /// have is not built, even where the mock draws it. **Twenty-two of the mock's thirty rows are
    /// therefore absent** — the eight built are Endpoint, Idle window, Warm set, Control token,
    /// Paired devices, Show in the menu bar, Router log and Configuration, three of them drawn as
    /// observed facts with the mock's own control left off — and each absent row's label is
    /// forbidden here by name, not by a vague pattern, because a vague pattern is what gets narrowed
    /// until it matches nothing.
    ///
    /// The count was **thirteen here and in three other places** until M15's gap-fix counted the
    /// mock's `.form-row` elements directly; the list below was sixteen entries and covered fifteen
    /// of the twenty-two, so the sentence and the rule under it disagreed and neither could see it.
    /// Twenty-three entries now: the twenty-two row labels plus `Rotate`, which is a control inside
    /// a row that *is* built.
    ///
    /// Each label is paired with the artifact that already recorded the absence, so the reason
    /// travels with the rule rather than living in a plan nobody reads next year.
    @Test("no pane names a control this product does not have")
    func absentCapabilitiesAreNotNamed() {
        let forbidden: [(String, String)] = [
            ("Start at login", "no login-item mechanism exists in either target"),
            ("Child PATH", "/servers carries no PATH field — Models.swift:114-121"),
            ("Adopt new servers automatically", "no harnesses endpoint — ControlToken.swift:13-19"),
            ("Warn about duplicates", "no harnesses endpoint — ControlToken.swift:13-19"),
            ("Reconcile without asking", "RouterCore and CLI-driven, not a preference"),
            ("Check for drift", "no harnesses endpoint to read an interval from"),
            ("Analyse my sessions", "the product has no analyst in any form"),
            ("Primary model", "no model is ever called on the user's behalf"),
            ("Fallback model", "no model is ever called on the user's behalf"),
            ("Harnesses to read", "the product has no analyst in any form"),
            ("Frequency", "there is no analyst run to schedule"),
            ("Notify me about findings", "nothing generates a finding to notify about"),
            ("Check for skill updates", "no update checking exists"),
            ("Install updates automatically", "no update checking exists"),
            ("Hold a version that wants more", "no update checking exists"),
            ("Update the app itself", "no update checking exists"),
            ("Rotate", "there is no rotate endpoint — SettingsWindowModel.forget()"),
            ("Hold schema changes", "the behaviour ships; the setting does not"),
            ("Keep call history for", "no retention window exists"),
            ("Show the Dock icon", "no activation-policy control exists"),
            ("Approve from the popover", "the popover ships; the preference does not"),
            ("Rebuild the tool cache", "re-indexing is per-server; there is no bulk endpoint"),
            ("Restore direct configuration", "no such endpoint")
        ]
        for text in Self.everyRenderedString {
            for (label, why) in forbidden {
                #expect(
                    !text.contains(label),
                    "'\(label)' is drawn, and \(why) — spec-M15 §2 assumption 5"
                )
            }
        }
    }

    /// The two shapes of invented *value* the mock carries, as opposed to an invented control.
    ///
    /// A byte size and a version string are the two figures the mock states that nothing in this
    /// process observes, and both are the failure `DESIGN.md` §6 names. Matched case-sensitively so
    /// the word "megabyte" in a doc comment arguing that none may be shown is not the thing caught —
    /// these are the rendered strings, not the source.
    @Test("no pane states a byte size or a version nobody observed")
    func noInventedFigures() {
        for text in Self.everyRenderedString {
            for unit in ["MB", "KB", "GB", "TB"] {
                #expect(!text.contains(unit), "a byte figure reached the copy: '\(text)'")
            }
            #expect(
                text.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) == nil,
                "a version string reached the copy: '\(text)'"
            )
        }
    }

    /// The build line is the one place a version legitimately appears, and it appears only when the
    /// process actually carries one.
    @Test("the build identity states a version only when the bundle carries one")
    func buildIdentityInventsNothing() {
        #expect(BuildIdentity(name: nil, version: nil, build: nil).summary == nil)
        #expect(BuildIdentity(name: "MCP Router", version: nil, build: "42").summary == nil)
        #expect(BuildIdentity(name: "MCP Router", version: "1.4.0", build: nil).summary
            == "MCP Router 1.4.0")
        #expect(BuildIdentity(name: "MCP Router", version: "1.4.0", build: "2026.08.19").summary
            == "MCP Router 1.4.0 (build 2026.08.19)")
        // The mock's footer also claims the build is signed and notarised. Nothing observes that,
        // and every build in this repository is unsigned, so the clause is not carried.
        let summary = BuildIdentity.measured.summary ?? ""
        #expect(!summary.contains("notarised"))
        #expect(!summary.contains("sandbox"))
    }
}
