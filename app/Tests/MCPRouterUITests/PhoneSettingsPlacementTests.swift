#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// DEF-025 and DEF-028 — where the Settings recovery action sits, and how the empty state reads.
    ///
    /// Both were recorded open rather than fixed, and for the same reason: `PhoneMessageBlock` draws
    /// nine states and each fix is right for a subset of them. The owner authorised both on
    /// 2026-08-20, so each is now applied at the call site that wants it rather than as a mode on
    /// the shared block.
    ///
    /// Source-level, for the reason `CleanupRowActionsTests` gives: the claim is about which view
    /// owns a control across every state, and a rendered assertion over one state leaves the rest
    /// unchecked.
    @Suite("Phone settings — where the action sits and how the empty state reads")
    struct PhoneSettingsPlacementTests {
        private static let source = "app/Sources/MCPRouterUI/Phone/PairedMacSettingsView.swift"

        private static func read() throws -> String {
            try String(
                contentsOf: ShellTestSupport.repoRoot().appending(path: source),
                encoding: .utf8
            )
        }

        /// One type's source, from its declaration to the next `struct` or the end of the file.
        private static func declaration(of type: String) throws -> String {
            let text = try read()
            let start = try #require(
                text.range(of: "struct \(type): View {"),
                "\(Self.source) declares no `\(type)` — this test names the wrong thing"
            )
            let rest = text[start.upperBound...]
            let next = rest.range(of: "\nstruct ") ?? rest.range(of: "\npublic struct ")
            return String(next.map { rest[..<$0.lowerBound] } ?? rest)
        }

        /// The same, with every comment line removed.
        ///
        /// **A predicate satisfied by the prose explaining it is not a predicate.** These views
        /// carry long comments naming the very symbols asserted below — `PhoneEmptyState` explains
        /// itself by naming `PhoneMessageBlock` — so a raw-text match would stay green after the
        /// code was deleted.
        private static func code(of type: String) throws -> String {
            try declaration(of: type)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }

        /// DEF-025. `i1-phone-pairing.html` §L draws the recovery action as a sibling AFTER the
        /// card, on all five Settings states that carry one.
        @Test("the message block draws no action of its own")
        func theBlockDrawsNoAction() throws {
            let block = try Self.code(of: "PhoneMessageBlock")
            #expect(
                !block.contains("entry.actionLabel"),
                "PhoneMessageBlock still draws its own action, so the control sits inside the card"
            )
            #expect(
                !block.contains("entry.secondaryActionLabel"),
                "PhoneMessageBlock still draws its own secondary action"
            )
        }

        /// The action has to exist somewhere, or DEF-025 would be "fixed" by deleting the control.
        /// This is the half that stops the test above passing on a Settings pane with no recovery.
        @Test("the action moved to a sibling rather than being deleted")
        func theActionMovedRatherThanVanished() throws {
            let actions = try Self.code(of: "PhoneBlockActions")
            #expect(
                actions.contains("entry.actionLabel") && actions.contains("PhoneProminentButtonStyle"),
                "PhoneBlockActions draws no primary action, so the recovery has gone rather than moved"
            )
            #expect(
                actions.contains("entry.secondaryActionLabel"),
                "PhoneBlockActions draws no secondary action"
            )
        }

        /// And the Settings view has to place it, or the sibling is never drawn.
        @Test("the unreadable state places the action below its block")
        func theUnreadableStatePlacesTheAction() throws {
            let view = try Self.code(of: "PairedMacSettingsView")
            #expect(
                view.contains("PhoneBlockActions("),
                "PairedMacSettingsView never places PhoneBlockActions, so unreadable offers no recovery"
            )
        }

        /// DEF-028. §B draws the never-paired state as `.pempty` — centred, with a glyph above the
        /// headline — and it is the ONLY Settings state the design centres.
        @Test("the never-paired state is centred and carries its illustration")
        func theNeverPairedStateIsCentred() throws {
            let empty = try Self.code(of: "PhoneEmptyState")
            #expect(
                empty.contains("multilineTextAlignment(.center)"),
                "PhoneEmptyState is not centred, so the never-paired state still reads as a notice"
            )
            #expect(
                empty.contains("PhoneMetric.emptyGlyph"),
                "PhoneEmptyState draws no illustration; §B puts a glyph above the headline"
            )
        }

        /// The centring must not have been applied to the shared block, which draws eight other
        /// states the design does not centre. This is the assertion that makes the fix a fix rather
        /// than one state's treatment applied to nine.
        @Test("centring did not leak into the block the other eight states use")
        func centringDidNotLeakIntoTheSharedBlock() throws {
            let block = try Self.code(of: "PhoneMessageBlock")
            #expect(
                !block.contains("multilineTextAlignment(.center)"),
                "PhoneMessageBlock centres its text, so eight states the design left-aligns are centred"
            )
        }

        /// And the never-paired case has to use it.
        @Test("the never-paired case renders the empty state, not the notice block")
        func theNeverPairedCaseUsesTheEmptyState() throws {
            let view = try Self.code(of: "PairedMacSettingsView")
            #expect(
                view.contains("PhoneEmptyState("),
                "PairedMacSettingsView still renders never-paired through PhoneMessageBlock"
            )
        }
    }
#endif
