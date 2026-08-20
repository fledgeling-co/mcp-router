#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterUI

    /// DEF-015: the detail pane must not pass its boards' minimum width up to the split view.
    ///
    /// Every board draws fixed-width columns, so each row reports a hard minimum. Without a break
    /// in that chain `NavigationSplitView` reports the widest board's sum as its own minimum, the
    /// window proposes 980pt anyway — this app opts into no minimum size and `windowResizability`
    /// defaults to `.automatic` — and SwiftUI places the oversized child **centred**. Measured on
    /// glass at a 980pt window: `AXSplitGroup` read 988pt on Checks, 1044pt on Skills and 1119pt on
    /// Discover, each with its origin moved left by exactly half the excess. The sidebar paid for
    /// the detail pane's columns, rendering its section headers as `unning` and `brary`.
    ///
    /// Source-level, because the thing being asserted is a layout *contract* rather than one
    /// rendered frame: the running-app measurement lives in `capture-mac-glass.sh`, which reads
    /// every board's split group against its window and now fails on any overflow. This test is
    /// what makes a revert visible in `make test`, seconds after it is typed rather than on the
    /// next glass run.
    @Suite("Shell — the detail pane does not force the window wider than it is")
    struct ShellDetailWidthTests {
        @Test("the detail column breaks the boards' minimum-width chain")
        func theDetailColumnDoesNotReportABoardsMinimum() throws {
            let source = try String(
                contentsOf: ShellTestSupport.repoRoot()
                    .appending(path: "app/Sources/MCPRouterUI/Shell/ShellWindow.swift"),
                encoding: .utf8
            )
            let detail = try #require(
                source.range(of: "} detail: {"),
                "ShellWindow no longer has a detail column — this test names the wrong thing"
            )
            let end = try #require(
                source.range(of: ".navigationTitle(", range: detail.upperBound ..< source.endIndex),
                "ShellWindow's detail column no longer ends at `.navigationTitle` — re-anchor this"
            )
            // **Comments stripped before matching, and this was found by arming rather than by
            // reading.** The first version searched the raw slice, and the modifier it looks for is
            // named in the doc comment three lines above it — so deleting the modifier left the
            // assertion green. A predicate satisfied by the prose explaining it is not a predicate.
            let column = source[detail.upperBound ..< end.lowerBound]
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            #expect(
                column.contains("minWidth: 0"),
                """
                the detail column passes its boards' minimum width up to the split view, so a board \
                wider than the window is drawn centred and clipped at both edges — the sidebar's \
                own labels included. DEF-015.
                """
            )
            #expect(
                column.contains("alignment: .leading"),
                """
                the detail column does not say who loses when the content still does not fit, so \
                SwiftUI centres it and the sidebar is cut before the board's trailing chrome
                """
            )
        }

        /// The other half: something in the controls row has to be able to give.
        ///
        /// Both boards put a `.fixedSize()` segmented picker next to a search field. The picker
        /// cannot compress by a point — that is what `.fixedSize()` means, and it is right, because
        /// a segmented control has nowhere to put a truncated label. So the field is the only
        /// control in the row that can give anything back, and a fixed width on it made the row's
        /// minimum larger than the detail pane at a 980pt window.
        ///
        /// Measured before and after on glass: Discover's content wanted 823pt against a 684pt
        /// pane and Skills' wanted 748pt; with the field flexing, every board's split group reads
        /// 980 of 980 and nothing but a scrollbar sits past the pane edge.
        ///
        /// Named per board rather than looped over every file, because these two are the boards the
        /// measurement covers. A third board growing this problem is a new measurement, not a case
        /// this test silently already made.
        @Test("the boards whose controls row overflowed let their search field give way")
        func theCrowdedControlsRowsCanCompress() throws {
            for (board, metrics) in [
                ("app/Sources/MCPRouterUI/Boards/DiscoverBoard.swift", "DiscoverBoardMetrics"),
                ("app/Sources/MCPRouterUI/Boards/SkillsBoard.swift", "SkillsBoardMetrics")
            ] {
                let source = try String(
                    contentsOf: ShellTestSupport.repoRoot().appending(path: board),
                    encoding: .utf8
                )
                let code = source
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")
                #expect(
                    !code.contains(".frame(width: \(metrics).searchWidth)"),
                    """
                    \(board) pins its search field to one width, so the controls row cannot give \
                    anything back and the board lays out wider than its pane. DEF-015.
                    """
                )
                #expect(
                    code.contains("minWidth: \(metrics).searchMinWidth"),
                    "\(board) declares no floor for its search field, so it can compress to nothing"
                )
                #expect(
                    code.contains("idealWidth: \(metrics).searchWidth"),
                    """
                    \(board) does not say what width its search field wants, so it renders at its \
                    floor even where the pane has room for the full field
                    """
                )
            }
        }
    }
#endif
