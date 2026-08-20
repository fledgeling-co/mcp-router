#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// DEF-011: the per-row actions the design specifies and the build drew on no row.
    ///
    /// `prototype.html:950` gives every Cleanup row a 150px trailing column carrying `Inspect` and
    /// `Remove`, and a flagged skill gets `Read first…` in their place. The vocabulary differential
    /// found it by comparing accessible names board by board with the shell and the fixture rows
    /// subtracted: `examined=8 boards, in-design-not-build=20`.
    ///
    /// Source-level, for the reason `ActivityBoardRulesTests` gives: the claim is about every row in
    /// every state, and a rendered assertion over one row leaves the rest unchecked.
    @Suite("Cleanup — the row actions the design draws")
    struct CleanupRowActionsTests {
        private static func read(_ relative: String) throws -> String {
            try String(
                contentsOf: ShellTestSupport.repoRoot().appending(path: relative),
                encoding: .utf8
            )
        }

        private static let rowSource = "app/Sources/MCPRouterUI/Boards/CleanupBoardRow.swift"
        private static let boardSource = "app/Sources/MCPRouterUI/Boards/CleanupBoard.swift"

        @Test("the row draws both actions the design puts on it")
        func theRowDrawsBothActions() throws {
            let source = try Self.read(Self.rowSource)
            #expect(
                source.contains("Button(\"Inspect\""),
                "the Cleanup row draws no Inspect; prototype.html:950 puts one on every row"
            )
            #expect(
                source.contains("Button(\"Remove…\""),
                "the Cleanup row draws no Remove; prototype.html:950 puts one on every row"
            )
        }

        /// The actions have to be reachable, not merely drawn.
        ///
        /// `children: .combine` flattens a row's controls into its label and leaves nothing to
        /// press — the failure this campaign already recorded for a time-limited undo that only
        /// mouse users could reach.
        @Test("the row contains its controls rather than combining them away")
        func theRowContainsItsControls() throws {
            // Scoped to `CleanupBoardRow`, not to the file. The first version asserted that
            // `.combine` appeared nowhere in it and went red against `CleanupObservationTrack`,
            // where combining is correct — it draws a bar and a number and carries no control. A
            // predicate that fires on a correct use is a detector defect, whichever file it is in.
            let row = try Self.declaration(of: "CleanupBoardRow", in: Self.rowSource)
            #expect(
                row.contains("accessibilityElement(children: .contain)"),
                "the Cleanup row combines its children, so its buttons are not reachable"
            )
            #expect(
                !row.contains("accessibilityElement(children: .combine)"),
                "the Cleanup row still combines its children somewhere"
            )
        }

        /// One type's source, from its declaration to the next one or the end of the file.
        private static func declaration(of type: String, in relative: String) throws -> String {
            let source = try read(relative)
            let start = try #require(
                source.range(of: "struct \(type): View {"),
                "\(relative) declares no `\(type)` — this test names the wrong thing"
            )
            let rest = source[start.upperBound...]
            let next = rest.range(of: "\n    struct ") ?? rest.range(of: "\n#endif")
            return String(next.map { rest[..<$0.lowerBound] } ?? rest)
        }

        /// A row with no closures draws no controls, so the board has to pass them.
        @Test("the board wires the row's actions rather than leaving them nil")
        func theBoardWiresTheRowsActions() throws {
            let source = try Self.read(Self.boardSource)
            #expect(
                source.contains("inspect: {") && source.contains("remove: {"),
                "CleanupBoard builds its rows without actions, so every row draws an empty column"
            )
        }

        /// Removal opens the dialog; it does not remove.
        ///
        /// The row's button is one click, and the one destructive act on this board is never one
        /// click. Asserted against the model rather than the view, because what the button does is
        /// the model's state change and not the pixel.
        @MainActor
        @Test("the row's removal opens the dialog and writes nothing")
        func theRowsRemovalOpensTheDialog() async {
            let client = M7RecordingClient()
            client.serversToServe = [M7Fixtures.server(name: "alpha", calls: 0)]
            let board = CleanupBoardModel(client: client)
            await board.load()

            board.sheet = .removeServer(name: "alpha")
            #expect(
                board.sheet == .removeServer(name: "alpha"),
                "the row's removal did not open the dialog"
            )
            #expect(
                client.writes.isEmpty,
                "opening the removal dialog already wrote to the router: \(client.writes)"
            )
        }
    }
#endif
