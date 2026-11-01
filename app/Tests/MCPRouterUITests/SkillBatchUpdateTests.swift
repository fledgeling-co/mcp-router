#if os(macOS)
    import AppKit
    import MCPRouterKit
    import SwiftUI
    import Testing
    @testable import MCPRouterUI

    @Suite("Explicit plugin update review")
    @MainActor
    struct SkillBatchUpdateTests {
        @Test(
            "unreviewed offers do not promote; an explicit selection does and can be undone"
        )
        func requiresSelectionAndKeepsUndo() async throws {
            let client = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let board = SkillsBoardModel(client: client)
            await board.load()
            let offer = try #require(board.offers.first)
            #expect(!board.changes(for: offer).isEmpty)
            await board.promoteSelectedOffers([])
            #expect(client.calls.promotions.isEmpty)
            await board.promoteSelectedOffers([offer.name])
            #expect(client.calls.promotions == [offer.name])
            #expect(board.batchPromotions.count == 1)
            #expect(board.batchResults.first?.hasPrefix("Updated ") == true)
            await board.undoBatchPromotions()
            #expect(client.calls.undos == [offer.name])
            #expect(board.batchPromotions.isEmpty)
            #expect(board.batchResults.first?.hasPrefix("Restored ") == true)
        }

        @Test("unknown names and a router without the promotion route cause no write")
        func noInventedWrites() async {
            let client = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let board = SkillsBoardModel(client: client)
            await board.load()
            await board.promoteSelectedOffers(["not-listed"])
            #expect(client.calls.promotions.isEmpty)
            let oldClient = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.empty))
            let oldBoard = SkillsBoardModel(client: oldClient)
            await oldBoard.load()
            await oldBoard.promoteSelectedOffers(["trawl@fledgeling-plugins"])
            #expect(oldClient.calls.promotions.isEmpty)
        }

        @Test("one refused promotion preserves its reason and does not stop the next plugin")
        func partialBatch() async {
            let extra = ExtensionUpdateEntry(
                kind: .plugins, name: "other@market", state: "update-available",
                installed: "1.0.0", available: "2.0.0", hasUpdate: true, reason: "A newer cached version"
            )
            let missing = ExtensionUpdateEntry(
                kind: .plugins, name: "missing@market", state: "update-available",
                installed: "1.0.0", available: nil, hasUpdate: true, reason: "No version returned"
            )
            let client = RecordingControlAPIClient(
                wrapping: FixtureControlAPIClient(.populated), extraUpdates: [missing, extra],
                refusedPromotions: ["trawl@fledgeling-plugins"], refusedUndos: ["other@market"]
            )
            let board = SkillsBoardModel(client: client)
            await board.load()
            await board.promoteSelectedOffers(["trawl@fledgeling-plugins", "missing@market", "other@market"])
            #expect(client.calls.promotions.count == 2)
            #expect(board.batchResults.count == 3)
            #expect(board.batchResults[0].contains("cache entry changed"))
            #expect(board.batchResults[1].contains("No offered version was returned"))
            #expect(board.batchPromotions.map(\.name) == ["other@market"])
            await board.undoBatchPromotions()
            #expect(board.batchPromotions.map(\.name) == ["other@market"])
            #expect(board.batchResults[0].contains("restore is unavailable"))
        }

        @Test("the populated and empty review sheets render offscreen")
        func reviewSheetRenders() async throws {
            for scenario in [FixtureControlAPIClient.Scenario.populated, .empty] {
                let board = SkillsBoardModel(client: FixtureControlAPIClient(scenario))
                await board.load()
                let view = NSHostingView(rootView: SkillUpdateReviewSheet(board: board))
                let frame = NSRect(x: -10000, y: -10000, width: SkillsBoardMetrics.sheetWidth, height: 700)
                let window = NSWindow(
                    contentRect: frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.contentView = view
                view.frame = NSRect(origin: .zero, size: frame.size)
                view.layoutSubtreeIfNeeded()
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                #expect(bitmap.pixelsWide > 400)
                #expect(bitmap.pixelsHigh > 100)
                if let directory = ProcessInfo.processInfo.environment["MCPR_Q8_SHOTS"] {
                    let data = try #require(bitmap.representation(using: .png, properties: [:]))
                    try data
                        .write(to: URL(fileURLWithPath: directory)
                            .appendingPathComponent("updates-\(scenario).png"))
                }
                window.close()
            }
        }

        @Test("cached release notes use parsed Markdown in the changelog tab")
        func parsedChangelog() async throws {
            let board = SkillsBoardModel(client: FixtureControlAPIClient(.populated))
            await board.load()
            let document = try #require(board.changelogDocument(named: "trawl@fledgeling-plugins"))
            #expect(document.identity.version == "2.3.0")
            #expect(document.publishedTabs == [.changelog])
            #expect(document.blocks(for: .changelog)?.count == 2)
            #expect(board.changelogDocument(named: "missing") == nil)
        }
    }
#endif
