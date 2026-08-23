#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// DEF-016 and DEF-012: the entry point the design puts in a board header, and what it is called.
    ///
    /// `prototype.html:716` draws `Reset history…` in Activity's header right slot, **outside** the
    /// rows conditional, so the design specifies it in the empty state as much as the populated one.
    /// The build drew no control there at all, and the witness pass and the control differential
    /// found it independently — `designControls=1 buildControls=0` for that board.
    ///
    /// These are source-level and behavioural rather than rendered, for the reason
    /// `ActivityBoardRulesTests` gives at length: a rendered assertion over one state leaves the other
    /// eight unchecked, and the claim here is about the header in every state.
    @Suite("Activity — the reset entry point the design specifies")
    struct ActivityResetEntryPointTests {
        private static let boardSource = "app/Sources/MCPRouterUI/Activity/ActivityBoard.swift"

        /// Through `ShellTestSupport.repoRoot()` rather than by counting `..` from `#filePath`.
        /// The hand-counted version was written first and was one level short, so every path
        /// resolved under `app/app/` and three tests reported "no such file" about files that were
        /// there — a locator failure wearing a finding's clothes.
        private static func read(_ relative: String) throws -> String {
            let root = try ShellTestSupport.repoRoot()
            return try String(contentsOf: root.appending(path: relative), encoding: .utf8)
        }

        /// The header carries the action, and it is not inside the rows branch.
        ///
        /// The second half is the part that matters and the part a "does the string appear" check
        /// misses: a control drawn only when there are rows is absent from the empty state, which is
        /// exactly where somebody reaches for it.
        @Test("the reset action is in the header, not inside a populated-only branch")
        func theResetActionIsInTheHeader() throws {
            let source = try Self.read(Self.boardSource)
            let header = try #require(
                source.range(of: "private var header: some View {"),
                "ActivityBoard no longer has a `header` — this test names the wrong thing"
            )
            let content = try #require(
                source.range(of: "private var content: some View {"),
                "ActivityBoard no longer has a `content` — this test names the wrong thing"
            )
            let headerBody = String(source[header.upperBound ..< content.lowerBound])
            #expect(
                headerBody.contains("CleanupPresentation.resetLabel"),
                """
                the header draws no reset action; the design puts one in its right slot at \
                prototype.html:716, and DEF-016 is that it was missing
                """
            )
            #expect(
                headerBody.contains("model.request(.resetCallHistory)"),
                """
                the header's reset action opens nothing. M18 routed it through SheetGate \
                rather than assigning the sheet directly, so this reads the request; the \
                sheet it opens is asserted at the model seam in SheetGateRoutingTests
                """
            )
        }

        /// The label is the design's, in both places that carry this act.
        ///
        /// `Reset call history…` is a different slot's wording — the Danger section of Settings at
        /// `prototype.html:999`, which this app does not draw — and shipping it in a board header was
        /// DEF-012.
        @Test("both boards call it what the design calls it in a header")
        func theHeaderLabelIsTheDesigns() {
            #expect(
                CleanupPresentation.resetLabel == "Reset history…",
                """
                the header action is called \(CleanupPresentation.resetLabel); prototype.html:716 \
                and :930 both call it 'Reset history…'
                """
            )
        }

        /// DEF-012's other half: one string, three call sites, no drift.
        @Test("the marketplaces action is named once and reused")
        func theMarketplacesActionIsNamedOnce() throws {
            #expect(
                SkillPresentation.marketplacesAction == "Add marketplace…",
                """
                the Skills action is called \(SkillPresentation.marketplacesAction); \
                prototype.html:786 calls it 'Add marketplace…'
                """
            )
            for file in [
                "app/Sources/MCPRouterUI/Boards/SkillsBoard.swift",
                "app/Sources/MCPRouterKit/Shell/MenuCommand.swift"
            ] {
                let source = try Self.read(file)
                #expect(
                    !source.contains("\"Manage marketplaces…\"") && !source.contains("\"Add marketplace…\""),
                    """
                    \(file) still writes the marketplaces label as a literal, so the menu item and \
                    the button that open the same sheet can drift apart again — which is what \
                    DEF-012 found
                    """
                )
            }
        }

        /// Opening the dialog sends nothing; confirming sends exactly one reset.
        ///
        /// Counted rather than flagged, because "the dialog sent one" and "it sent one per keystroke"
        /// are the same Bool and different products.
        @MainActor
        @Test("the dialog resets only when confirmed, and once")
        func theDialogResetsOnlyWhenConfirmed() async {
            let client = RecordingUsageClient()
            let subject = ActivityModel(client: client, source: nil, clock: { Date() })
            await subject.load()

            // Read out of the actor before asserting: `#expect`'s condition is an autoclosure that
            // does not support concurrency, so `await client.resets` inside it does not compile.
            subject.sheet = RouterSheet.Activity.resetHistory
            var resets = await client.resets
            #expect(resets == 0, "opening the dialog already reset the history")

            subject.sheet = nil
            resets = await client.resets
            #expect(resets == 0, "cancelling the dialog reset the history anyway")

            await subject.resetHistory()
            resets = await client.resets
            #expect(resets == 1, "confirming the dialog sent \(resets) resets")
            #expect(subject.sheet == nil, "the dialog stayed open after the reset it asked for")
            #expect(subject.writeError == nil, "the reset reported an error against a client that took it")
        }
    }
#endif
