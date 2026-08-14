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

        @Test("the board's token allowlist covers every token it draws, and no more")
        func tokenAllowlistIsExact() throws {
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
            #expect(!row
                .contains(
                    "IconView(.frost, size: TypeToken.caption.size, weight: .medium)\n                        .foregroundStyle(ColorToken.accent"
                ))
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

        // MARK: - B2 · the registry stays a complement

        @Test("this build installs exactly one board and scaffolds the other seven")
        func registryIsTheShippedSet() {
            #expect(BoardRegistry.installed == [.activity])
            #expect(BoardRegistry.scaffolded.count == 7)
            #expect(ScaffoldedDestination(.activity) == nil, "the placeholder cannot be built for it")
            #expect(ScaffoldedDestination(.servers) != nil)
        }
    }
#endif
