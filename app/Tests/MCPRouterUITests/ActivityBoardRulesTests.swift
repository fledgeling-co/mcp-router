#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The board's surface-level rules: what it may draw, what voice it may draw it in, and what
    /// source it may draw it from.
    ///
    /// These are **source-level** gates rather than rendered assertions, deliberately and for the
    /// reason `ShellAppearanceTests` gives: a rule like "no indicator colour is used decoratively" is
    /// a property of the whole surface, and checking it by rendering one view leaves the rest
    /// unchecked. Each is checkable in both directions against an oracle this code did not write —
    /// `DESIGN.md` for the colours, `planning/specs/spec-M2.md` for the fields.
    @Suite("Activity — what the board may draw")
    struct ActivityBoardRulesTests {
        static let boardFiles = [
            "app/Sources/MCPRouterUI/Activity/ActivityBoard.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityRow.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityFilterBar.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityInspector.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityCopy.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityChrome.swift"
        ]

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

        // MARK: - B8 · the indicator colours do only their own job

        @Test("every indicator colour the board uses is justified by the document's own meaning")
        func indicatorUsesAreJustified() throws {
            let design = try ShellTestSupport.repoFile("DESIGN.md")
            let meanings: [ColorToken: String] = [
                .accent: "selection, focus, the one primary action",
                .live: "a child process is running",
                .attention: "wants a human decision",
                .fail: "failed or tripped"
            ]
            for use in ActivityChrome.indicatorUses {
                let documented = try #require(meanings[use.token], "\(use.token) is not an indicator")
                #expect(
                    documented.contains(use.justification),
                    "'\(use.justification)' is not part of \(use.token.rawValue)'s documented meaning"
                )
                #expect(design.contains(documented), "DESIGN.md no longer states that meaning")
            }
        }

        /// The direction that actually goes wrong: a token drawn somewhere the declaration does not
        /// mention.
        @Test("no board file draws an indicator colour the declaration does not list")
        func noUndeclaredIndicatorUse() throws {
            let declared = ActivityChrome.indicatorTokensUsed
            let indicators: [(ColorToken, String)] = [
                (.accent, "accent"), (.live, "live"), (.attention, "attention"), (.fail, "fail")
            ]
            for file in Self.boardFiles {
                let source = try ShellTestSupport.repoFile(file)
                for (token, name) in indicators where source.contains("ColorToken.\(name).color") {
                    #expect(
                        declared.contains(token),
                        "\(file) draws \(token.rawValue) but ActivityChrome does not justify it"
                    )
                }
            }
        }

        /// D4, stated as its own assertion because it is the decision most likely to be undone by
        /// someone who thinks a green tick would look friendly.
        @Test("nothing on this board is drawn in the running-process colour")
        func liveIsNeverDrawn() throws {
            #expect(!ActivityChrome.indicatorTokensUsed.contains(.live))
            for file in Self.boardFiles {
                let source = try ShellTestSupport.repoFile(file)
                #expect(
                    !source.contains("ColorToken.live.color"),
                    "\(file) paints a finished call in the colour that means a process is running"
                )
            }
        }

        /// **Scoped to the files this item owns.** The board's view tree also reaches F2's shared
        /// styles — `ProminentButtonStyle`'s accent fill and `focusRing`'s accent ring — and those
        /// are F2's to justify, tested by `ShellAppearanceTests` against the same document. A scan
        /// that walked into them would make this item responsible for a shared component's palette,
        /// which is the opposite of one owner per rule. What is asserted here is that **this item's**
        /// files draw exactly the tokens it declares.
        @Test("the board's own files draw exactly the tokens it declares, and no more")
        func tokenAllowlistIsExactForTheBoardsOwnFiles() throws {
            var drawn = Set<ColorToken>()
            for file in Self.boardFiles {
                let source = try ShellTestSupport.repoFile(file)
                for token in ColorToken.allCases {
                    let name = String(describing: token)
                    if source.contains("ColorToken.\(name).color") { drawn.insert(token) }
                }
            }
            #expect(
                drawn == ActivityChrome.tokensUsed,
                """
                drawn but not on the allowlist: \(drawn.subtracting(ActivityChrome.tokensUsed)); \
                on the allowlist but not drawn: \(ActivityChrome.tokensUsed.subtracting(drawn))
                """
            )
        }

        // MARK: - B7 · drawn, never unicode

        /// The predicate is narrow on purpose. A whole-file non-ASCII scan would fail on the board's
        /// own copy, which legitimately contains `·`, `…` and `—`; and excluding string literals
        /// would make it blind to exactly the case it exists to catch. What is forbidden is a *mark*
        /// spelled as a character.
        @Test("no board file renders a symbol-block character where an icon belongs")
        func noUnicodeMarks() throws {
            let forbidden: Set<Character> = [
                "❄", "✳", "✻", "✴", "❆", "❅", "★", "☆", "✓", "✔", "✗", "✘",
                "●", "○", "◆", "◇", "■", "□", "▲", "△", "⚠", "⚡", "🔥", "❗"
            ]
            for file in Self.boardFiles {
                let source = try ShellTestSupport.repoFile(file)
                for character in source where forbidden.contains(character) {
                    Issue.record("\(file) renders '\(character)' where DESIGN.md §4 requires a drawn icon")
                }
            }
        }

        @Test("the cold mark is a drawn icon in a non-indicator tier")
        func coldMarkIsDrawnAndQuiet() throws {
            let row = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Activity/ActivityRow.swift"
            )
            #expect(row.contains("IconView(.frost"))
            #expect(Icon.frost.systemName == "snowflake")
            // Not the accent: on this board an accent-coloured duration competes with the selected
            // row, and §2 reserves the token for selection, focus and the one primary action.
            let mark = try #require(
                row.range(of: "IconView(.frost").map { String(row[$0.upperBound...].prefix(200)) }
            )
            #expect(mark.contains("ColorToken.t2.color"), "the cold mark is a quiet tier")
            #expect(
                !mark.contains("ColorToken.accent.color"),
                "the cold mark is drawn in the selection colour and competes with the selected row"
            )
        }

        // MARK: - B10 · the instrument voice does not leak into prose

        /// §2's monospace list is closed: "numerals, counts, durations, error codes, status
        /// subtitles". A tool name and a project name are identifiers and are on none of them.
        @Test("the tool, server and project columns are not in the instrument voice")
        func identifiersAreNotMonospaced() throws {
            let row = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Activity/ActivityRow.swift"
            )
            for field in ["text(.tool)", "text(.server)", "text(.project)"] {
                let index = try #require(row.range(of: field)?.upperBound)
                let following = String(row[index...].prefix(120))
                #expect(
                    !following.contains("monospaced: true"),
                    "\(field) borrows the instrument voice for an identifier"
                )
            }
        }

        @Test("the age, session and duration are in the instrument voice")
        func numeralsAreMonospaced() throws {
            let row = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Activity/ActivityRow.swift"
            )
            for field in ["text(.when)", "text(.session)", "text(.took)"] {
                let index = try #require(row.range(of: field)?.upperBound)
                let following = String(row[index...].prefix(120))
                #expect(following.contains("monospaced: true"), "\(field) is instrument data")
            }
        }

        @Test("DESIGN.md still states the monospace rule this board is held to")
        func monospaceRuleIsStillDocumented() throws {
            // The sentence wraps in the document, so the comparison is over collapsed whitespace —
            // an exact-substring match could never hit it and would have passed as a false green
            // the moment the rule was reworded rather than removed.
            let design = try ShellTestSupport.repoFile("DESIGN.md")
            let flattened = design.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            #expect(flattened.contains("numerals, counts, durations, error codes, status subtitles"))
        }

        // MARK: - B5 · the row height never moves, and the skeleton matches it exactly

        /// The value check alone would be circular — it would compare the constant to the token it
        /// was defined from. What catches drift is the second half: **every** height either the row
        /// or the skeleton draws at must be that one constant, so a literal, or a different token,
        /// or a second independent expression, all fail.
        @Test("the row, the header row and the skeleton are all drawn at the one documented height")
        func rowHeightIsOneDocumentedValue() throws {
            #expect(ActivityColumn.rowHeight == MetricToken.tableRows.leadingScalar)
            // Parsed out of the document rather than written here. Editing §2 to say 28 used to
            // leave this green, which made the citation decorative.
            let design = try ShellTestSupport.repoFile("DESIGN.md")
            let documentedRow = try #require(
                design.split(separator: "\n").first { $0.contains("| Table rows |") },
                "DESIGN.md §2 no longer documents a dense-list row height"
            )
            let cells = documentedRow.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
            let documented = try #require(
                cells.count > 2 ? Double(cells[2].prefix { $0.isNumber }) : nil,
                "could not read the leading scalar out of §2's Table rows row"
            )
            #expect(MetricToken.tableRows.leadingScalar == documented)

            let row = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Activity/ActivityRow.swift"
            )
            // Code lines only. The doc comment above `rowHeight` explains the rule by quoting the
            // expression it forbids, and a scan that reads comments fails on its own explanation.
            let code = row.split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let heights = code.components(separatedBy: ".frame(height:").dropFirst()
                .map { String($0.prefix(60)) }
            #expect(heights.count >= 2, "the populated row and the skeleton row both set a height")
            for height in heights {
                #expect(
                    height.contains("ActivityColumn.rowHeight"),
                    "a height in ActivityRow.swift is not the shared row height: \(height)"
                )
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

        // MARK: - B35 · a row enters by transform, never by fading up from nothing

        /// The row's own entry, asserted by name rather than by "some transition exists somewhere".
        ///
        /// A `ForEach` row with no `.transition(_:)` is not "no animation": SwiftUI applies its
        /// default insertion transition, which is `.opacity`, so an arriving call fades in from
        /// nothing — against §7 and B35 — while the file contains no opacity for any grep to find.
        /// That is exactly what this board did, under a comment claiming it did not.
        @Test("the row declares the transform-only entry transition")
        func rowDeclaresItsEntryTransition() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Activity/ActivityBoard.swift"
            )
            let rows = try #require(source.range(of: "ForEach(model.visible)"))
            let list = source[rows.upperBound...]
            let declared = try #require(list.range(of: ".transition("))

            // The modifier as written, up to its closing newline. Asserting the *whole* expression
            // rather than that it merely contains `rowInsertion` is what closes the obvious defeat:
            // `.transition(ActivityMotion.rowInsertion(reduceMotion: reduceMotion)
            //     .combined(with: .opacity))` restores the fade from zero while satisfying every
            // check that only looks for a substring — the named helper is still there, its own
            // definition is untouched, and no `.opacity(0)` or `.transition(.opacity` appears
            // anywhere for a grep to find.
            let modifier = list[declared.lowerBound...]
                .prefix(while: { $0 != "\n" })
            #expect(
                modifier == ".transition(ActivityMotion.rowInsertion(reduceMotion: reduceMotion))",
                "the row's entry transition is no longer exactly the transform-only one: \(modifier)"
            )
        }

        @Test("this build installs Activity alongside the boards already shipped")
        func registryIsTheShippedSet() {
            // M2's own half first: the board is registered, not merely written. A board that
            // compiles but is absent from `installed` still shows the reader a placeholder.
            #expect(BoardRegistry.hasBoard(.activity))
            #expect(ScaffoldedDestination(.activity) == nil, "the placeholder cannot be built for it")

            // This read `installed == [.activity]` while M2 was the only board on the branch. M3
            // merged, so the set is both — asserted exactly rather than by containment, so a board
            // appearing or vanishing here is a deliberate edit rather than something a subset check
            // waves through.
            #expect(BoardRegistry.installed == [.servers, .activity])
            #expect(BoardRegistry.scaffolded.count == 6)
            #expect(ScaffoldedDestination(.skills) != nil, "a scaffolded destination still builds one")
        }
    }
#endif
