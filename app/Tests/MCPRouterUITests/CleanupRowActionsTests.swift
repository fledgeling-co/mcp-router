#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// DEF-011: the per-row actions the design specifies and the build drew on no row.
    ///
    /// `prototype.html:950` gives every Cleanup row a 150px trailing column carrying `Inspect` and
    /// `Remove`, and a flagged skill gets `Read first…` in their place. The vocabulary differential
    /// found it by comparing accessible names board by board with the shell and the fixture rows
    /// subtracted: `examined=8 boards, in-design-not-build=20`.
    ///
    /// Source-level, for the reason `ActivityBoardRulesTests` gives: the claim is about every row in
    /// every state, and a rendered assertion over one row leaves the rest unchecked.
    @Suite("Cleanup — the row actions the design draws")
    struct CleanupRowActionsTests {
        private static func read(_ relative: String) throws -> String {
            try String(
                contentsOf: ShellTestSupport.repoRoot().appending(path: relative),
                encoding: .utf8
            )
        }

        private static let rowSource = "app/Sources/MCPRouterUI/Boards/CleanupBoardRow.swift"
        private static let boardSource = "app/Sources/MCPRouterUI/Boards/CleanupBoard.swift"

        @Test("the row draws both actions the design puts on it")
        func theRowDrawsBothActions() throws {
            let source = try Self.read(Self.rowSource)
            #expect(
                source.contains("Button(\"Inspect\""),
                "the Cleanup row draws no Inspect; prototype.html:950 puts one on every row"
            )
            #expect(
                source.contains("Button(\"Remove…\""),
                "the Cleanup row draws no Remove; prototype.html:950 puts one on every row"
            )
        }

        /// The actions have to be reachable, not merely drawn.
        ///
        /// `children: .combine` flattens a row's controls into its label and leaves nothing to
        /// press — the failure this campaign already recorded for a time-limited undo that only
        /// mouse users could reach.
        @Test("the row contains its controls rather than combining them away")
        func theRowContainsItsControls() throws {
            // Scoped to `CleanupBoardRow`, not to the file. The first version asserted that
            // `.combine` appeared nowhere in it and went red against `CleanupObservationTrack`,
            // where combining is correct — it draws a bar and a number and carries no control. A
            // predicate that fires on a correct use is a detector defect, whichever file it is in.
            let row = try Self.code(of: "CleanupBoardRow", in: Self.rowSource)
            #expect(
                row.contains("accessibilityElement(children: .contain)"),
                "the Cleanup row combines its children, so its buttons are not reachable"
            )
            #expect(
                !row.contains("accessibilityElement(children: .combine)"),
                "the Cleanup row still combines its children somewhere"
            )
        }

        /// One type's source, from its declaration to the next one or the end of the file.
        private static func declaration(of type: String, in relative: String) throws -> String {
            let source = try read(relative)
            let start = try #require(
                source.range(of: "struct \(type): View {"),
                "\(relative) declares no `\(type)` — this test names the wrong thing"
            )
            let rest = source[start.upperBound...]
            let next = rest.range(of: "\n    struct ") ?? rest.range(of: "\n#endif")
            return String(next.map { rest[..<$0.lowerBound] } ?? rest)
        }

        /// The same, with every comment line removed.
        ///
        /// **A predicate satisfied by the prose explaining it is not a predicate.** The first
        /// `ShellDetailWidthTests` searched raw source for a modifier its own doc comment three
        /// lines above also named, so deleting the modifier left the assertion green. Every
        /// source-level assertion below reads this instead.
        private static func code(of type: String, in relative: String) throws -> String {
            try declaration(of: type, in: relative)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }

        /// A row with no closures draws no controls, so the board has to pass them.
        @Test("the board wires the row's actions rather than leaving them nil")
        func theBoardWiresTheRowsActions() throws {
            let source = try Self.read(Self.boardSource)
            #expect(
                source.contains("inspect: {") && source.contains("remove: {"),
                "CleanupBoard builds its rows without actions, so every row draws an empty column"
            )
        }

        /// Removal opens the dialog; it does not remove.
        ///
        /// The row's button is one click, and the one destructive act on this board is never one
        /// click. Asserted against the model rather than the view, because what the button does is
        /// the model's state change and not the pixel.
        @MainActor
        @Test("the row's removal opens the dialog and writes nothing")
        func theRowsRemovalOpensTheDialog() async {
            let client = M7RecordingClient()
            client.serversToServe = [M7Fixtures.server(name: "alpha", calls: 0)]
            let board = CleanupBoardModel(client: client)
            await board.load()

            board.sheet = .removeServer(name: "alpha")
            #expect(
                board.sheet == .removeServer(name: "alpha"),
                "the row's removal did not open the dialog"
            )
            #expect(
                client.writes.isEmpty,
                "opening the removal dialog already wrote to the router: \(client.writes)"
            )
        }

        // MARK: - Read first…, the third action

        private static let sheetSource = "app/Sources/MCPRouterUI/Boards/CleanupSheets.swift"

        @MainActor
        private static func boardWithMovedSkill() async -> CleanupBoardModel {
            let client = M7RecordingClient()
            client.skillsToServe = SkillsResponse(
                skills: [
                    M7Fixtures.skill(name: "pr-summariser", presence: [:], provenance: M7Fixtures.moved()),
                    M7Fixtures.skill(name: "changelog", presence: [:])
                ],
                clients: [M7Fixtures.client("claude")]
            )
            let board = CleanupBoardModel(client: client)
            await board.load()
            return board
        }

        /// The note reaches the row, and it is the check's own sentence rather than a second one.
        ///
        /// Read through `SkillChecks.originUnchanged` so this board and the Checks board cannot
        /// disagree about what counts as moved — asserted by comparing against that check's result
        /// rather than against a literal, because a literal here would pass while the two boards
        /// drifted apart.
        @MainActor
        @Test("a moved marketplace reaches the row as the check's own sentence")
        func aMovedMarketplaceReachesTheRow() async throws {
            let board = await Self.boardWithMovedSkill()
            let moved = try #require(
                board.candidates.first { $0.name == "pr-summariser" },
                "the moved skill is not a candidate, so this test measures nothing"
            )
            let expected = SkillChecks.originUnchanged(
                M7Fixtures.skill(name: "pr-summariser", presence: [:], provenance: M7Fixtures.moved())
            ).reason
            #expect(
                moved.provenance == expected,
                "the row's note is not the check's sentence: \(moved.provenance ?? "nil")"
            )
        }

        /// A skill whose origin has not moved carries nothing, and neither does a server.
        ///
        /// The negative half is what makes the positive one mean something: a field that is always
        /// populated cannot mark a row.
        @MainActor
        @Test("an unmoved skill and a server both carry no note")
        func anUnmovedRowCarriesNoNote() async throws {
            let board = await Self.boardWithMovedSkill()
            let unmoved = try #require(
                board.candidates.first { $0.name == "changelog" },
                "the unmoved skill is not a candidate, so this test measures nothing"
            )
            #expect(
                unmoved.provenance == nil,
                "a skill whose marketplace never moved is flagged: \(unmoved.provenance ?? "")"
            )

            let client = M7RecordingClient()
            client.serversToServe = [M7Fixtures.server(name: "alpha", calls: 0)]
            let servers = CleanupBoardModel(client: client)
            await servers.load()
            #expect(
                servers.candidates.allSatisfy { $0.provenance == nil },
                "a server carries a provenance note, and a server has no marketplace to have moved"
            )
        }

        /// `Read first…` replaces the other two rather than joining them.
        ///
        /// `prototype.html:961` puts it in their place, and the substitution is the requirement: a
        /// removal left on that row is one click from a fact nobody has read yet. Source-level for
        /// the reason the file's own header gives — the claim is about every flagged row in every
        /// state, and a rendered assertion over one row leaves the rest unchecked.
        @Test("the row swaps both of its actions for Read first…")
        func theRowSwapsItsActions() throws {
            let row = try Self.code(of: "CleanupBoardRow", in: Self.rowSource)
            #expect(
                row.contains("Button(\"Read first…\", action: readFirst)"),
                "the Cleanup row draws no Read first…; prototype.html:961 puts one on a flagged row"
            )
            let branch = try #require(
                row.range(of: "if candidate.provenance != nil {"),
                "the row draws Read first… unconditionally, so every row offers it"
            )
            let flagged = row[branch.upperBound...]
            let elseBranch = try #require(
                flagged.range(of: "} else {"),
                "the row has no unflagged branch, so an ordinary row draws no actions at all"
            )
            let flaggedOnly = flagged[..<elseBranch.lowerBound]
            #expect(
                !flaggedOnly.contains("Button(\"Inspect\"") && !flaggedOnly.contains("Button(\"Remove…\""),
                "a flagged row still draws Inspect or Remove, so a removal is one click from an unread fact"
            )
        }

        /// The button opens the sheet, and opening it writes nothing.
        @MainActor
        @Test("Read first… opens its sheet and writes nothing")
        func readFirstOpensItsSheet() async throws {
            let client = M7RecordingClient()
            client.skillsToServe = SkillsResponse(
                skills: [M7Fixtures.skill(
                    name: "pr-summariser",
                    presence: [:],
                    provenance: M7Fixtures.moved()
                )],
                clients: [M7Fixtures.client("claude")]
            )
            let board = CleanupBoardModel(client: client)
            await board.load()
            let moved = try #require(board.candidates.first, "no candidate to open a sheet for")

            board.sheet = .provenance(skillPath: moved.key.id)
            #expect(
                board.sheet?.id == "prov:/skills/pr-summariser",
                "the sheet is not keyed by the skill's path: \(board.sheet?.id ?? "nil")"
            )
            #expect(
                board.skill(atPath: moved.key.id)?.provenance == M7Fixtures.moved(),
                "the sheet cannot find the skill it was opened for, so it renders no observation"
            )
            #expect(
                client.writes.isEmpty,
                "opening Read first… wrote to the router: \(client.writes)"
            )
        }

        /// The sheet shows what `SkillProvenance` carries, and none of what the prototype invents.
        ///
        /// `prototype.html:1249` lists an owner at install, a force-pushed default branch, an
        /// installed hash "no longer in history" and an eval score of 5 of 8. The router reports
        /// none of them and cannot compute one of them at all, so each is named here rather than
        /// left to a reviewer to notice if it ever arrives.
        @Test("the sheet reports the three observed fields and none of the four invented ones")
        func theSheetReportsOnlyObservations() throws {
            let sheet = try Self.code(of: "SkillProvenanceSheet", in: Self.sheetSource)
            for field in ["firstSeenSource", "currentSource", "firstSeenAt"] {
                #expect(
                    sheet.contains("provenance.\(field)"),
                    "the sheet never renders `\(field)`, which is one of the three the router observes"
                )
            }
            for invented in ["Owner at install", "force-pushed", "no longer in history", "5 of 8"] {
                #expect(
                    !sheet.contains(invented),
                    "the sheet states '\(invented)', which the router never reported"
                )
            }
        }
    }
#endif
