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
            //
            // Brace-balanced rather than split on an indented `}`: see `declarationBody`, whose two
            // silent-green failure modes an out-of-family pair found in the split form this used.
            let card = try ShellTestSupport.declarationBody(
                of: "private var card: some View",
                in: source
            )
            #expect(card.contains("ReadoutGeometry.cardRadius"), "the card is not at §2's card radius")
            #expect(card.contains("ColorToken.f3"), "the card has no plate")
            #expect(card.contains("ColorToken.line"), "the card has no bezel")
            // **That the card is DECLARED is not that it is drawn**, and both reviewing families
            // named the same surviving mutation: delete `.background(card)` from the body and the
            // readout renders uncarded again — M27's original defect, restored — while this test,
            // every source scan and the accessibility gate all stay green. A card nothing attaches
            // is a private property Swift does not even warn about.
            #expect(
                source.contains(".background(card)"),
                "the card is declared and never attached to the readout"
            )
            // §2's "card radius 10–14", reached from tokens rather than typed.
            #expect(ReadoutGeometry.cardRadius >= 10)
            #expect(ReadoutGeometry.cardRadius <= 14)
        }

        @Test("the sidebar gives the card its margins and drops the rule that stood in for it")
        func theCardHasMarginsAndNoDividerAboveIt() throws {
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Sidebar.swift")
            // All four edges rather than three. The first form padded horizontally and at the
            // bottom, so the card sat flush against the last nav row — the divider that used to
            // hold them apart went with the card that replaced it, and nothing took its place.
            #expect(source.contains(".padding(ReadoutGeometry.cardMargin)"))
            #expect(
                !source.contains(".padding(.bottom, ReadoutGeometry.cardMargin)"),
                "the card is padded on three edges, so its top margin is missing"
            )
            // One `Divider()` remains in the sidebar — the one above the foot line. Two would mean
            // the rule above the readout survived the card that replaced it.
            #expect(source.components(separatedBy: "Divider()").count - 1 == 1)
            #expect(ReadoutGeometry.cardMargin > 0)
        }

        // MARK: - What the accessibility tree publishes for the count row

        @Test("the count row publishes its label and its reading as one element")
        func theCountRowPublishesOneCombinedElement() throws {
            // Three forms, and this branch shipped two of the three before landing here. The
            // history is the point, because each wrong one was green on some gate.
            //
            // `.ignore` shipped originally and discarded the label: one element carrying the counts
            // sentence, `Child processes` on screen and absent from the accessibility plane — the
            // very reading the campaign's differential took when it reported the label missing.
            //
            // No merge at all fixed the visibility and cost a reader a swipe: two stops for one
            // metric, the first carrying no value and the second naming the quantity differently.
            // It was taken because `.combine` went red on A35's assertion in `mac-shell.sh`.
            //
            // `.combine` is correct and A35 was the thing that was wrong. That gate matches the
            // destination rows as a prefix and says why in its own comment — a row carrying a badge
            // announces as one sentence, so the assertion has to allow for it — while the readout's
            // line was anchored whole. It could be, because this row had no label to combine with;
            // the anchor recorded the absence M27 exists to fix rather than a decision against a
            // combined form. Widened to that same tolerance, and `.combine` is what ships.
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Readout.swift")
            let row = try ShellTestSupport.declarationBody(
                of: "private func counts(running: Int, declared: Int, note: String?) -> some View",
                in: source
            )
            #expect(
                row.contains(".accessibilityElement(children: .combine)"),
                "the count row publishes two stops for one metric again"
            )
            #expect(
                !row.contains(".accessibilityElement(children: .ignore)"),
                "the count row merges again, which hides its label from every AX instrument"
            )
            // The scoping has to actually scope, or both assertions above pass on the wrong text.
            // Anchored at BOTH ends: `childProcessesLabel` is the row's first line and would still
            // be present in a body truncated before the modifier this test is really about, so on
            // its own it proves nothing the assertions above need.
            #expect(row.contains("ReadoutCopy.childProcessesLabel"))
            #expect(row.contains("TraceStrip(points: tracePoints)"), "the extracted body stops short")
            #expect(!row.contains("struct ReadoutMessage"))
            // The numeral still carries the sentence, which is the element A35 reads.
            #expect(row.contains(".accessibilityLabel("))
            #expect(row.contains("ReadoutCopy.accessibilityLabel(running: running, declared: declared)"))
            #expect(
                ReadoutCopy.accessibilityLabel(running: 3, declared: 8)
                    == "3 of 8 declared servers running"
            )
            // A35's own line, widened rather than weakened — and pinned here, because the product
            // change above is only correct if the gate tolerates the head it now produces. A gate
            // and the render that has to satisfy it drifting apart is what cost this branch a
            // commit already.
            let gate = try ShellTestSupport.repoFile("scripts/acceptance/mac-shell.sh")
            #expect(
                gate.contains("'^(Child processes, )?[0-9]+ of [0-9]+ declared servers running$'"),
                "A35 anchors the readout label whole again, which rejects the combined row"
            )
        }

        @Test("the scoped source readers fail loudly rather than returning plausible text")
        func theDeclarationReaderCannotPassVacuously() throws {
            // The guard above is only worth its assertions if the extractor underneath it throws
            // where it used to shrug. The split form it replaced returned a non-nil string for a
            // marker that was not in the file at all, so every `#require` diagnostic written
            // against it was unreachable — an out-of-family pair found that independently.
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Readout.swift")
            #expect(throws: ShellTestSupport.OracleError.self) {
                _ = try ShellTestSupport.declarationBody(of: "private func noSuchThing(", in: source)
            }
            // Ambiguity is a failure too: two matches means the reader picks a declaration by
            // accident, which is how a scoped gate ends up measuring the wrong function.
            #expect(throws: ShellTestSupport.OracleError.self) {
                _ = try ShellTestSupport.declarationBody(of: "func ", in: source)
            }
            // And it balances rather than stopping at the first member-indented brace: the card's
            // body contains a nested `.overlay(…)` and must still reach its own bezel.
            let card = try ShellTestSupport.declarationBody(of: "private var card: some View", in: source)
            #expect(card.contains("ColorToken.line"))
            #expect(!card.contains("private func counts("))
        }

        // MARK: - The count spends --live only where --live is true

        @Test("a count of zero is not painted in the running colour")
        func zeroIsNotPaintedLive() throws {
            // The contradiction this closes was created by M27 itself, which is why it belongs to
            // M27: the design text written in 418357b refuses the mock's `--live` foot dot on the
            // ground that a green mark beside a card reading `0 of 4` paints "a child process is
            // running" where none is — while the numeral in that very card was painted `--live`
            // unconditionally. Both out-of-family reviews found it.
            //
            // `.populated(running: 0, declared: m)` is reachable whenever servers are declared and
            // all of them are idle, which is this app's ordinary morning state rather than a corner.
            #expect(ReadoutTint.counts(running: 0) == .t1)
            #expect(ReadoutTint.counts(running: 1) == .live)
            #expect(ReadoutTint.counts(running: 4) == .live)
            // Structural, because the arithmetic above passes against a view that ignores the rule.
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Readout.swift")
            #expect(source.contains("ReadoutTint.counts(running: running)"))
            #expect(
                !source.contains(".foregroundStyle(ColorToken.live.color)"),
                "the counts numeral paints --live unconditionally again"
            )
            // And the registry says what the render now does. §2's exclusivity is only checkable
            // because this list is the one place an indicator use is declared.
            #expect(
                ShellChrome.indicatorUses.contains {
                    $0.token == .live && $0.element.contains("above zero")
                },
                "the indicator registry still claims the count is --live unconditionally"
            )
        }

        // MARK: - The card's interior, which the skeleton has to fill exactly

        @Test("the skeleton is given the card's interior, not the wrapper's old one")
        func theSkeletonFillsTheCardsInterior() throws {
            // The regression this catches, found by reading rather than by a failing check: the
            // readout's vertical padding was `spacing` until M27 put it inside a card, so
            // `height - spacing * 2` WAS the interior and the skeleton subtracted that. The card
            // pads by `cardPadding`, and the stale subtraction left the skeleton 8pt taller than
            // the space it sits in — visible as the one state whose only job is to occupy the
            // populated form's footprint, drawn overflowing it.
            //
            // Stated as arithmetic first: the populated form is two dense rows, the trace, and the
            // two gaps between them, and the interior is exactly that. If either side moves without
            // the other, this is red.
            #expect(
                ReadoutGeometry.interiorHeight
                    == MetricToken.tableRows.leadingScalar * 2
                    + ReadoutGeometry.traceHeight
                    + ReadoutGeometry.spacing * 2
            )
            #expect(
                ReadoutGeometry.interiorHeight
                    == ReadoutGeometry.height - ReadoutGeometry.cardPadding * 2
            )
            // And structurally, because the arithmetic above passes against a skeleton that ignores
            // the constant entirely. `spacing` and `cardPadding` are 4 and 8, so a skeleton that
            // went back to subtracting `spacing` is a different number and this is red on it.
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Readout.swift")
            #expect(source.contains(".frame(height: ReadoutGeometry.interiorHeight"))
            #expect(
                !source.contains("ReadoutGeometry.height - ReadoutGeometry.spacing"),
                "the skeleton subtracts the wrapper's old padding instead of the card's"
            )
        }

        @Test("the foot's left edge is the card's label edge")
        func theFootAlignsWithTheCardsContent() throws {
            // One left edge down the whole sidebar foot. `prototype.html` sets the card's margin and
            // the foot's padding independently and they do not line up; this is the better reading
            // of the same design rather than a new number.
            #expect(
                SidebarFootGeometry.leading == ReadoutGeometry.cardMargin + ReadoutGeometry.cardPadding
            )
            #expect(SidebarFootGeometry.height > 0)
            // The line above restates `leading`'s own definition and would hold against a view that
            // never applies it — an out-of-family review named exactly that. So: the view applies
            // it, and the height with it.
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/SidebarFoot.swift")
            #expect(source.contains(".padding(.horizontal, SidebarFootGeometry.leading)"))
            #expect(source.contains(".frame(height: SidebarFootGeometry.height)"))
        }
    }
#endif
