#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The board's **visual language**: which colours it paints, whether a mark is drawn or spelled,
    /// which text is in the instrument voice, how tall a row is, and how a row enters.
    ///
    /// The counterpart is `ActivityBoardContractTests`, which owns what the board *claims* — that a
    /// rendered field traces to a wire property the spec names, that it nests no scroll view, that an
    /// unperformable offer is dimmed, that it is registered rather than merely written. Those seven
    /// tests were split out and, for one commit, existed in **both** files: the copy landed before the
    /// originals were removed, so the suite reported seven passes for assertions it was running twice.
    /// Duplicated gates are worse than absent ones — they inflate a count while a later edit to one
    /// copy leaves the other quietly disagreeing — so this file now ends where that one begins.
    ///
    /// These are **source-level** gates rather than rendered assertions, deliberately and for the
    /// reason `ShellAppearanceTests` gives: a rule like "no indicator colour is used decoratively" is
    /// a property of the whole surface, and checking it by rendering one view leaves the rest
    /// unchecked. Each is checkable in both directions against an oracle this code did not write —
    /// `DESIGN.md` for the colours, the voice and the row height.
    @Suite("Activity — what the board may draw it in")
    struct ActivityBoardRulesTests {
        static let boardFiles = [
            "app/Sources/MCPRouterUI/Activity/ActivityBoard.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityRow.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityFilterBar.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityInspector.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityCopy.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityChrome.swift"
        ]

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
    }
#endif
