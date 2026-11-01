#if os(macOS)
    import AppKit
    import MCPRouterKit
    import SwiftUI
    import Testing
    @testable import MCPRouterUI

    @Suite("Cleanup full reason wrapping")
    @MainActor
    struct CleanupRowWrappingTests {
        private func candidates() async throws -> [CleanupBoardModel.Candidate] {
            let board = CleanupBoardModel(client: FixtureControlAPIClient(.cleanupLongReasons))
            await board.load()
            let normal = try #require(board.candidates.first { $0.kind == .server })
            let flagged = try #require(board.candidates.first { $0.provenance != nil })
            #expect(normal.reason.count > 250)
            #expect((flagged.provenance?.count ?? 0) > 200)
            return [normal, flagged]
        }

        private func height(_ candidate: CleanupBoardModel.Candidate, width: Double) -> Double {
            let view = NSHostingView(rootView: CleanupBoardRow(
                candidate: candidate, isSelected: false, inspect: {}, remove: {}, readFirst: {}
            )
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true))
            view.layoutSubtreeIfNeeded()
            return view.fittingSize.height
        }

        @Test("long normal and flagged rows grow at compact and default column widths")
        func fullTextDrivesRowHeight() async throws {
            let rows = try await candidates()
            for row in rows {
                let compact = height(row, width: 612)
                let regular = height(row, width: 812)
                #expect(compact > M7BoardMetrics.rowHeight * 2)
                #expect(regular > M7BoardMetrics.rowHeight * 2)
                #expect(compact >= regular)
            }
        }
    }
#endif
