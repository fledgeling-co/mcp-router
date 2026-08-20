#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// M27 — the two elements at the foot of the shared sidebar: the loopback line the build had
    /// lost entirely, and the card and label the child-process count had lost.
    ///
    /// Both are *shell* elements rather than board elements, which is what "in the shared wrapper"
    /// means and why the on-glass lane in `scripts/acceptance/mac-shell.sh` walks all eight
    /// destinations rather than one.
    @Suite("Mac shell — the sidebar foot")
    struct SidebarFootTests {
        // MARK: - The line, driven through the real model

        @MainActor
        @Test("the running shell's foot carries the port the router answered on")
        func theModelFeedsTheObservedAddress() async throws {
            let model = try ShellTestSupport.model(.populated)
            await model.refresh(at: Date(timeIntervalSince1970: 1_000_000))
            let response = try await model.client.servers()
            #expect(
                LoopbackFoot.reading(for: model.trackerState) == .address("127.0.0.1:\(response.port)")
            )
            #expect(SidebarFootPresence.isDrawn(LoopbackFoot.reading(for: model.trackerState)))
        }

        @MainActor
        @Test("a router that never answered leaves no address, and no rule across the sidebar")
        func offlineDrawsNeitherLineNorDivider() async throws {
            let model = try ShellTestSupport.model(.offline)
            await model.refresh(at: Date(timeIntervalSince1970: 1_000_000))
            let reading = LoopbackFoot.reading(for: model.trackerState)
            #expect(reading == .absent)
            // The divider travels with the line. A rule ruling off the bottom of an empty sidebar
            // reads as a surface that failed to draw rather than one with nothing to say.
            #expect(!SidebarFootPresence.isDrawn(reading))
        }

        @Test("the skeleton is drawn while the first poll is outstanding")
        func loadingKeepsTheLinesPlace() {
            #expect(SidebarFootPresence.isDrawn(.awaitingFirstAnswer))
        }

        // MARK: - The line spends no indicator colour

        @Test("the foot draws none of the four exclusive indicator colours")
        func theFootIsNeverAnIndicatorColour() throws {
            // The decision this pins: `prototype.html` paints the foot's dot `--live`, and `--live`
            // is already spent — correctly — on the child-process count in the card directly above.
            // A `--live` dot beside a card reading `0 of 4` paints "a child process is running"
            // where none is. The dot is gone rather than recoloured, because a neutral dot still
            // asserts a state, and `ControlAPIError` owns the words for that state (§6).
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/SidebarFoot.swift")
            for token in ["ColorToken.live", "ColorToken.attention", "ColorToken.fail", "ColorToken.accent"] {
                #expect(!source.contains(token), "the sidebar foot draws \(token)")
            }
            #expect(
                !ShellChrome.indicatorUses.contains { $0.element.contains("foot") },
                "the foot was registered as an indicator use — it draws none"
            )
        }

        // MARK: - The sidebar composes it from the one poll

        @Test("the sidebar reads the address from the tracker, not from a constant")
        func theSidebarReadsTheTrackerState() throws {
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Sidebar.swift")
            #expect(source.contains("LoopbackFoot.reading(for: model.trackerState)"))
            #expect(source.contains("SidebarFootPresence.isDrawn"))
        }

        // MARK: - The card and the label

        @Test("the count is labelled what it is, and not what the group header says")
        func theCountCarriesTheDesignsLabel() {
            #expect(ReadoutCopy.childProcessesLabel == "Child processes")
            // The label it replaced collided with the sidebar's own `Running` group header two rows
            // above, which is a different thing entirely.
            #expect(ReadoutCopy.childProcessesLabel != DestinationGroup.running.rawValue)
        }

        @Test("the readout is drawn inside the card the design of record draws")
        func theReadoutIsCarded() throws {
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Readout.swift")
            // Scoped to the card's own declaration rather than to the file. Read across the whole
            // file this assertion was **not discriminating**: `ReadoutSkeleton` already draws
            // `ColorToken.f3`, so a card whose plate had been swapped for another fill still
            // contained the string and the check stayed green. Measured — that mutation survived
            // the file-wide form and is red against this one.
            let afterDeclaration = try #require(
                source.components(separatedBy: "private var card: some View {").last,
                "the readout has no card declaration at all"
            )
            // The declaration's own body, which ends at the property's closing brace. Taking
            // everything after the marker would sweep `ReadoutSkeleton` back in and reopen the
            // hole this scoping closes.
            let card = try #require(
                afterDeclaration.components(separatedBy: "\n        }").first,
                "the card declaration is never closed"
            )
            #expect(card.contains("ReadoutGeometry.cardRadius"), "the card is not at §2's card radius")
            #expect(card.contains("ColorToken.f3"), "the card has no plate")
            #expect(card.contains("ColorToken.line"), "the card has no bezel")
            // §2's "card radius 10–14", reached from tokens rather than typed.
            #expect(ReadoutGeometry.cardRadius >= 10)
            #expect(ReadoutGeometry.cardRadius <= 14)
        }

        @Test("the sidebar gives the card its margins and drops the rule that stood in for it")
        func theCardHasMarginsAndNoDividerAboveIt() throws {
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Sidebar.swift")
            #expect(source.contains("ReadoutGeometry.cardMargin"))
            // One `Divider()` remains in the sidebar — the one above the foot line. Two would mean
            // the rule above the readout survived the card that replaced it.
            #expect(source.components(separatedBy: "Divider()").count - 1 == 1)
            #expect(ReadoutGeometry.cardMargin > 0)
        }

        @Test("the foot's left edge is the card's label edge")
        func theFootAlignsWithTheCardsContent() {
            // One left edge down the whole sidebar foot. `prototype.html` sets the card's margin and
            // the foot's padding independently and they do not line up; this is the better reading
            // of the same design rather than a new number.
            #expect(
                SidebarFootGeometry.leading == ReadoutGeometry.cardMargin + ReadoutGeometry.cardPadding
            )
            #expect(SidebarFootGeometry.height > 0)
        }
    }
#endif
