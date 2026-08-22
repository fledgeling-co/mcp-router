#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// What the board may **claim**, as against what it may draw it in.
    ///
    /// Split from `ActivityBoardRulesTests` on that line. That suite is the board's visual language —
    /// which colours it paints, whether a mark is drawn or spelled, which text is in the instrument
    /// voice, how tall a row is, how a row enters. This one is about the board's *assertions to the
    /// reader*: that every rendered field traces to a wire property the spec names, that it does not
    /// nest a scroll view inside another, that an offer it cannot perform is dimmed rather than inert,
    /// and that it is registered rather than merely written.
    ///
    /// These are **source-level** gates rather than rendered assertions, for the reason
    /// `ShellAppearanceTests` gives: each is a property of the whole surface, and checking it by
    /// rendering one view leaves the rest unchecked. Each is checkable in both directions against an
    /// oracle this code did not write — `planning/specs/spec-M2.md` for the fields, `DESIGN.md` for
    /// the voice.
    @Suite("Activity — what the board may claim")
    struct ActivityBoardContractTests {
        // MARK: - B4 · every rendered string has a named source field

        /// The oracle is the spec's table, parsed. A survey of the view would pass by whatever the
        /// surveyor chose to enumerate; this fails when the code grows a field the document does not
        /// list, and equally when the document lists one the code does not render.
        @Test("the row's field mapping equals the spec's data table, in both directions")
        func rowFieldsMatchTheSpecTable() throws {
            let spec = try ShellTestSupport.repoFile("planning/specs/spec-M2.md")
            let section = try #require(
                spec.range(of: "## Where the data comes from")
                    .map { String(spec[$0.upperBound...]) }
            )
            // Stop at the next heading. Reading to the end of the file swept the acceptance tables,
            // the state matrix and the change table into "documented fields", which made the
            // comparison meaningless in the direction that matters.
            let table = section.range(of: "\n## ").map { String(section[..<$0.lowerBound]) } ?? section

            var documented = Set<String>()
            for line in table.split(separator: "\n") {
                guard line.hasPrefix("|") else { continue }
                let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard cells.count > 2 else { continue }
                let name = cells[1]
                guard !name.isEmpty, name != "On screen", !name.hasPrefix("---") else { continue }
                // The subtitle rows are the header's, not the row's; the row's own fields are the
                // ones `ActivityRowField` covers.
                guard !name.hasPrefix("subtitle") else { continue }
                documented.insert(name)
            }

            let implemented = Set(ActivityRowField.allCases.map(\.rawValue))
            #expect(!documented.isEmpty, "the spec's data table was not found or not parsed")
            #expect(
                implemented == documented,
                """
                fields the row renders with no row in the spec's table: \
                \(implemented.subtracting(documented).sorted()); \
                rows in the table the mapping does not implement: \
                \(documented.subtracting(implemented).sorted())
                """
            )
        }

        @Test("every field names at least one CallRecord property that exists on the wire")
        func fieldsNameRealWireProperties() throws {
            let models = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterKit/Control/Models.swift"
            )
            let callRecord = try #require(
                models.range(of: "public struct CallRecord")
                    .map { String(models[$0.upperBound...].prefix(600)) }
            )
            for field in ActivityRowField.allCases {
                for property in field.recordFields {
                    #expect(
                        callRecord.contains("var \(property):"),
                        "\(field.rawValue) claims CallRecord.\(property), which is not on the wire"
                    )
                }
            }
        }

        // MARK: - B41 · one scroll view, not two

        @Test("the board is not nested inside the shell's content scroll view")
        func boardOptsOutOfTheShellScroll() throws {
            let shell = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Shell/ShellWindow.swift"
            )
            // The placeholder branch keeps the shell's scroll view; the board branch does not.
            let boardBranch = try #require(
                shell.range(of: "private var board: some View")
                    .map { String(shell[$0.upperBound...].prefix(700)) }
            )
            #expect(
                !boardBranch.contains("ScrollView"),
                "a board inside the shell's scroll view puts one scroll view in another"
            )
            #expect(shell.contains("ActivityBoard(model:"), "the board is reached from the shell")
        }

        // MARK: - B44 · an offered action this build cannot perform is disabled, not inert

        /// `withoutAction` is what lets the copy stay verbatim (§6, B40) while the control beneath it
        /// stops claiming a capability. Asserted in both directions: the words survive, the offer does
        /// not.
        @Test("stripping the offer keeps every word of the message")
        func withoutActionKeepsTheCopy() {
            // Built the way `message(for:)` builds it — from the error, not from a literal (B40).
            let error = ControlAPIError.routerNotRunning
            let message = StateMessage(
                title: error.headline,
                detail: error.advice,
                actionLabel: error.actionLabel
            )
            let stripped = message.withoutAction
            #expect(message.actionLabel != nil, "the fixture for this test needs an offer to strip")
            #expect(stripped.actionLabel == nil, "the offer is what is removed")
            #expect(stripped.title == message.title, "§6: one wording per state — the words stay")
            #expect(stripped.detail == message.detail)
        }

        /// The board performs exactly one of the actions it draws. The other two — starting the router
        /// and re-pairing — belong to items that have not shipped, so they are drawn dimmed with a
        /// reason (§3.4) rather than enabled and silent. This fails if a later edit wires a second
        /// case to a real call without also making it actionable, and if it makes a case actionable
        /// without giving it something to do.
        @Test("the only action the board performs is the one it owns")
        func onlyTheOwnedActionIsPerformed() throws {
            let board = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Activity/ActivityBoard.swift"
            )
            let actBody = try #require(
                board.range(of: "private func act(on condition: ActivityCondition)")
                    .map { String(board[$0.upperBound...].prefix(420)) }
            )
            #expect(
                actBody.contains("model.clearFilters()"),
                "clearing the filters is the board's own doing and stays wired"
            )
            // Every other case falls to the one `break`. A second call here would be a second
            // capability claim, and would need its own actionable case to be honest.
            #expect(
                actBody.components(separatedBy: "model.").count - 1 == 1,
                "the board calls the model from exactly one branch of act(on:)"
            )
            let actionable = try #require(
                board.range(of: "private func actionable(_ condition: ActivityCondition) -> Bool")
                    .map { String(board[$0.upperBound...].prefix(220)) }
            )
            #expect(
                actionable.contains("case .filteredToNothing = condition"),
                "the one performable action is the one the board can actually perform"
            )
            #expect(
                board.contains("DisabledAction(label: label, reason: Self.actionNotYetBuilt)"),
                "an unperformable offer is drawn dimmed with its reason, never enabled and inert"
            )
        }

        /// The reason is helper text under a control, so it has to read as one — and it must not
        /// apologise or blame the reader (§6's voice).
        @Test("the disabled reason names what is missing without apologising")
        func disabledReasonIsInVoice() {
            let reason = ActivityBoard.actionNotYetBuilt
            #expect(!reason.isEmpty, "§3.4: a disabled control's reason is discoverable, not absent")
            for word in ["sorry", "oops", "error", "failed", "unfortunately"] {
                #expect(
                    !reason.lowercased().contains(word),
                    "a control that has not shipped yet is not an error: '\(word)'"
                )
            }
        }

        // MARK: - B2 · the registry stays a complement

        @Test("this build installs Activity alongside the boards already shipped")
        func registryIsTheShippedSet() {
            // M2's own half first: the board is registered, not merely written.
            #expect(BoardRegistry.hasBoard(.activity))

            // Asserted exactly rather than by containment, so a board appearing or vanishing here is
            // a deliberate edit rather than something a subset check waves through. M3 merged after
            // M2, then M4, M8, M5, M7, and M6 — which closed the set at eight. **M15 took one back
            // out**: Settings is a `Settings` scene now, so it is not a destination and has no
            // board. The `allCases` invariant below is untouched, and it is what proves that
            // removal was complete rather than partial.
            #expect(
                BoardRegistry.installed
                    == [.servers, .activity, .skills, .discover, .evals, .cleanup, .inbox]
            )
            #expect(BoardRegistry.scaffolded.isEmpty)

            // **The assertion that used to live here has been deleted rather than repointed, as its
            // own comment instructed.** It read `ScaffoldedDestination(.inbox) != nil` — "a
            // scaffolded destination still builds one" — and it was repointed at each board landing:
            // `.skills` before M4, `.discover` before M5, `.inbox` after M7. M6 installed the last
            // one, so there is no destination left that can be its subject, and the type it named no
            // longer exists. Keeping it green against a destination that *has* a board would have
            // asserted the opposite of the invariant. What replaced it is
            // `ShellIntegrationTests.placeholderIsNotReintroduced`, which tests the thing that can
            // still go wrong: the sentence coming back.
            #expect(Destination.allCases.allSatisfy(BoardRegistry.hasBoard))
        }
    }
#endif
