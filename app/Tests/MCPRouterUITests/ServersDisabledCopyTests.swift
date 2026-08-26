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

        @MainActor
        private static func row(_ model: ServerRowModel) -> ServerRowView {
            ServerRowView(
                row: model, isSelected: false, isWriting: false, canWrite: true,
                error: nil, select: {}, act: { _ in }
            )
        }
    }
#endif
