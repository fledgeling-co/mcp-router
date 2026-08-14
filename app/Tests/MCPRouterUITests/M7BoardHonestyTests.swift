#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The two panes' standing rule, asserted where it is easiest to break by accident.
    ///
    /// M7's boards render figures the router supplies and nothing else. The failure mode is never a
    /// wrong calculation — it is an optional folded to a default so a view compiles, which turns
    /// "the router did not say" into a confident zero. Three of those were live in this item before
    /// this suite existed, and all three were in a *view*, past the point every Kit test can reach.
    ///
    /// These are source guards rather than behavioural tests because a SwiftUI `body` is not
    /// inspectable from a unit test. That is a real limit and worth stating: they prove the
    /// substitution is not written, not that the pixel is absent.
    @Suite("M7 — no figure the router did not observe")
    struct M7BoardHonestyTests {
        /// The observation track draws a bar whose length is a measurement.
        ///
        /// `window?.days ?? 0` fed a zero-length fill for a window the router could not report,
        /// while the mono label beside it correctly read "window unknown" — the drawing and the text
        /// stating different things about the same fact. A bar is a claim; an empty bar claims
        /// nothing was recorded, which is not what an unparsed `since` means.
        @Test("the observation track substitutes no day count for an unknown window")
        func trackDoesNotSubstituteZeroDays() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/CleanupBoardRow.swift"
            )
            #expect(
                !source.contains("window?.days ?? 0"),
                "the track filled to zero for a window the router never reported"
            )
            // And the fill is inside an `if let`, so there is no path that draws it without one.
            #expect(source.contains("if let window {"))
        }

        /// The badge-reconciliation line counts servers, and folds an absent reading to zero.
        ///
        /// Rendered unconditionally it told a reader whose router never answered that the sidebar
        /// counts zero never-used servers — the shell's own `staleKeepsBadgesAndDropsCounts` rule,
        /// broken on a different surface.
        @Test("the badge note is withheld until a reading exists rather than counting from nothing")
        func badgeNoteWaitsForAReading() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/CleanupBoard.swift"
            )
            let note = try #require(source.range(of: "CleanupPresentation.badgeNote"))
            let before = source[source.startIndex ..< note.lowerBound]
            #expect(
                before.hasSuffix("if board.state.reading != nil {\n                    Text("),
                "the badge note renders without a reading behind its count"
            )
        }

        /// The reset dialog's consequence is the disclosure for an act with no restore endpoint.
        @Test("the reset dialog passes the observed call count through, nil and all")
        func resetDialogDoesNotDefaultItsCount() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/CleanupSheets.swift"
            )
            #expect(
                !source.contains("recordedCalls ?? 0"),
                "the reset dialog said 0 calls for a count the router never reported"
            )
            #expect(source.contains("calls: board.state.reading?.recordedCalls"))
        }

        /// An irreversible action is never offered without the consequence that justifies it.
        @Test("removal is disabled when its consequence cannot be stated")
        func removalWithoutAConsequenceIsDisabled() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/CleanupSheets.swift"
            )
            #expect(source.contains(".disabled(candidate == nil)"))
            #expect(source.contains("CleanupPresentation.consequenceUnavailable"))
        }

        /// The rejected metaphor, held by a test rather than by memory.
        ///
        /// It has been raised and rejected more than once, and the cheapest way for it to come back
        /// is a well-meaning icon change nobody reads as a product decision.
        @Test("no trash metaphor reaches either pane")
        func noTrashMetaphor() throws {
            let files = [
                "app/Sources/MCPRouterUI/Boards/CleanupBoard.swift",
                "app/Sources/MCPRouterUI/Boards/CleanupBoardRow.swift",
                "app/Sources/MCPRouterUI/Boards/CleanupSheets.swift",
                "app/Sources/MCPRouterUI/Boards/CleanupBoardModel.swift"
            ]
            for file in files {
                let source = try ShellTestSupport.repoFile(file)
                // Only what would reach the screen: a `//` line saying the metaphor is banned is the
                // opposite of the defect, so comments are stripped before the scan.
                let rendered = source
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")
                    .lowercased()
                for word in ["trash", "\"bin\"", "recycle", "wastebasket", "rubbish"] {
                    #expect(!rendered.contains(word), "\(file) reintroduces the trash metaphor")
                }
            }
        }
    }
#endif
