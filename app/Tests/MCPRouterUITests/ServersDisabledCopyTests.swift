#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// M29, oracle lines 12 and 18 — the two strings this feature adds that a person reads or hears
    /// rather than sees as state.
    ///
    /// **Why they are asserted here rather than off a render.** Line 12's natural lane is
    /// `make mock-fidelity SURFACE=servers`, which exits 3 on `MeasureDump/main.swift:206` — a
    /// non-exhaustive switch that is byte-identical to `main`, so the break is inherited and not
    /// this item's to fix. Line 18 has no render lane at all: the mock marks `aria-disabled` on the
    /// row and every cell, and the app's analogue is deliberately **what is spoken**, because
    /// `.disabled(true)` would make the row unselectable and strand the `Enable` action sitting on
    /// it. Both values were private to a `View` and referenced by no test; both are now reachable.
    @Suite("M29 — the copy a disabled server produces")
    struct ServersDisabledCopyTests {
        private static func server(name: String = "sift", disabled: Bool) throws -> MCPServer {
            var decoded = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
            decoded.name = name
            decoded.disabled = disabled
            decoded.tools = 7
            return decoded
        }

        // MARK: - Oracle 12 · the held-change sheet's destructive button

        @Test("the sheet's destructive button names the action and the server")
        func theButtonNamesItsSubject() {
            #expect(HeldChangeSheet.disableLabel("sift") == "Disable sift")
            // The subject is interpolated rather than fixed: a label that read the same for every
            // server would be a sentence about no server in particular.
            #expect(HeldChangeSheet.disableLabel("warden") == "Disable warden")
        }

        @Test("the button dims with a readable reason when the server is already disabled")
        func theDimmedButtonSaysWhy() {
            #expect(
                HeldChangeSheet.disableReason(alreadyDisabled: true)
                    == "This server is already disabled."
            )
            #expect(
                HeldChangeSheet.disableReason(alreadyDisabled: false) == nil,
                "a live server's Disable button was dimmed"
            )
        }

        /// The binding, which the two tests above do not state on their own.
        ///
        /// A static that returns the right string proves nothing if `body` stopped calling it — the
        /// button could carry its own literal and both assertions would still pass. There is no
        /// accessor for a `Button`'s label on this host, so the binding is a fact about the source,
        /// and it is read the way `SheetShortcutGuardTests` reads a keyboard shortcut for the same
        /// reason. An out-of-family reviewer named this gap on the gap-fix diff.
        @Test("the sheet's destructive button is drawn from those two functions, not a literal")
        func theButtonIsWiredToThem() throws {
            let scanned = try SheetShortcutScan.allSheetViews()
            let sheet = try #require(
                scanned.first { $0.name == "HeldChangeSheet" },
                "HeldChangeSheet is no longer a scanned sheet view; this guard sees nothing"
            )
            let candidates = sheet.controls.filter(\.isDestructive)
            let destructive = try #require(
                candidates.first,
                "the held-change sheet has no destructive control"
            )
            #expect(
                destructive.declaration.contains("Self.disableLabel(serverName)"),
                "the Disable button stopped reading its label from disableLabel"
            )
            #expect(
                destructive.label.isEmpty,
                "the Disable button carries a literal label, which is the drift this guards"
            )
            // The dimmed reason reaches all three carriers — the dim itself, the visible help tag
            // and the spoken hint — from the one function, so none of them can word it separately.
            for carrier in ["disabled(", "help(", "accessibilityHint("] {
                #expect(
                    destructive.modifiers.contains { modifier in
                        modifier.contains(carrier)
                            && modifier.contains("Self.disableReason(alreadyDisabled: isDisabled)")
                    },
                    "\(carrier) on the Disable button does not read disableReason"
                )
            }
        }

        // MARK: - Oracle 18 · what the row says out loud

        @MainActor
        @Test("a disabled row speaks 'disabled by you' and 'tools withheld'")
        func theRowSpeaksTheWithheldCount() throws {
            let off = try ServerRowModel(
                server: Self.server(disabled: true), idleMs: 300_000, pendingAuth: nil
            )
            let spoken = Self.row(off).accessibilityValueText
            #expect(spoken.contains("disabled by you"))
            #expect(
                spoken.contains("tools withheld"),
                "the em-dash in the tools cell reached VoiceOver as punctuation, or not at all"
            )
            #expect(spoken == "disabled by you, tools withheld")

            // The row stays selectable, which is the whole reason the claim is carried in the
            // spoken value rather than in `.disabled(true)`: the `Enable` action lives on it.
            #expect(off.action == .enable)
            #expect(off.tools == nil)
        }

        @MainActor
        @Test("a live row speaks its own state and never claims a count is withheld")
        func aLiveRowMakesNoSuchClaim() throws {
            let on = try ServerRowModel(
                server: Self.server(disabled: false), idleMs: 300_000, pendingAuth: nil
            )
            let spoken = Self.row(on).accessibilityValueText
            #expect(!spoken.contains("tools withheld"))
            #expect(!spoken.contains("disabled by you"))
            #expect(spoken == on.subtitle.text)
        }

        /// A failed write replaces the state line on the row, and the spoken value follows it —
        /// otherwise a screen reader keeps reading a state the row has stopped showing.
        @MainActor
        @Test("a row reporting a failed write speaks the failure it is showing")
        func theSpokenValueFollowsTheVisibleLine() throws {
            let off = try ServerRowModel(
                server: Self.server(disabled: true), idleMs: 300_000, pendingAuth: nil
            )
            let failing = ServerRowView(
                row: off, isSelected: false, isWriting: false, canWrite: true,
                error: .routerNotRunning, select: {}, act: { _ in }
            )
            #expect(failing.accessibilityValueText
                == "\(ControlAPIError.routerNotRunning.headline), tools withheld")
        }

        /// Oracle 18's **binding**, which the three tests above do not state.
        ///
        /// `accessibilityValueText` returning the right sentence proves nothing if `body` stopped
        /// publishing it. A fresh-context verifier ran exactly that mutation — the single
        /// `.accessibilityValue(accessibilityValueText)` line deleted from `body` — and **all 1977
        /// tests stayed green**: every assertion above reads the property directly,
        /// `grep -rn 'accessibilityValue(' app/Tests/` returned nothing, and `.measured(…)` captures
        /// id, role, kind, frame, tokens, type and text but no accessibility value, so nothing else
        /// in the suite could have observed the loss. There is no accessor for a SwiftUI view's
        /// accessibility value on this host, so — exactly as for oracle 12's button label above —
        /// the binding is a fact about the source, and the source is what gets read. `DIS-17` is its
        /// red-green arm.
        @Test("the row publishes that value from body rather than only computing it")
        func theRowPublishesWhatItComputes() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/ServersBoardRow.swift"
            )
            // Two hops, because that file declares three views and `var body: some View` is
            // therefore ambiguous in it — `declarationBody` throws on an ambiguous marker rather
            // than picking one — while it is unambiguous inside this one struct.
            let view = try ShellTestSupport.declarationBody(of: "struct ServerRowView: View", in: source)
            let body = try ShellTestSupport.declarationBody(of: "var body: some View", in: view)

            // Exactly one publication, and it reads the named property rather than a second copy of
            // the sentence. Written as an equality on the whole population rather than a
            // `contains`: an inlined `row.tools == nil ? … : subtitleText` would render identically
            // and leave every assertion above green, which is the drift `DIS-16` guards one surface
            // over, and a `contains` would not see a second publication disagreeing with the first.
            let published = body.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix(".accessibilityValue(") }
            #expect(
                published == [".accessibilityValue(accessibilityValueText)"],
                "body stopped publishing accessibilityValueText: oracle 18 reaches no screen reader"
            )

            // The scoping has to actually scope, or the assertion above passes on the wrong text —
            // an empty extraction would satisfy an equality against an empty population too.
            #expect(body.contains("StatePlug(state: row.jack)"), "the extracted body starts short")
            #expect(body.contains("role: \"table-row\""), "the extracted body stops short")
            #expect(
                !body.contains("var accessibilityValueText"),
                "the extraction ran past body's end and is reading the property's own declaration"
            )
        }

        @MainActor
        private static func row(_ model: ServerRowModel) -> ServerRowView {
            ServerRowView(
                row: model, isSelected: false, isWriting: false, canWrite: true,
                error: nil, select: {}, act: { _ in }
            )
        }
    }
#endif
