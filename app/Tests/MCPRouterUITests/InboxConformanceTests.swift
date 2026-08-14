#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The M6 criteria whose enforcement the Phase D critic could not locate — A11, A15 and A16 —
    /// plus the local-refusal state the accept path gained when its silent `return` was closed.
    ///
    /// Each of these was true of the delivered code and asserted nowhere, which is the failure mode
    /// `spec-M6.md`'s own gate table warns about: *a criterion whose only evidence is a comment is
    /// unmet*. A comment saying the phone describes nothing is worth nothing the day someone
    /// interpolates `envelope.displayName` into the sheet.
    @Suite("M6 · conformance")
    @MainActor
    struct InboxConformanceTests {
        /// Every M6 file that draws something, resolved once so a rename fails loudly here rather
        /// than quietly turning a scan into a no-op.
        static let views = [
            "InboxBoard.swift",
            "InboxBoardRow.swift",
            "InboxReviewSheet.swift",
            "PairingSheet.swift"
        ]

        static func viewSource(_ name: String) throws -> String {
            try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Boards/\(name)")
        }

        // MARK: - A11 · the phone describes nothing

        /// **The capability text is byte-equal to what the Mac derived from its own registry entry.**
        ///
        /// The structural version of this — "the sheet calls `RegistryCapability.statement`" — is
        /// visible by reading the file and provable by nothing. This compares the rendered strings
        /// to the ones the Mac derives, so an envelope field reaching the capability block would
        /// have to change one of them.
        @Test("the capability text comes from the resolved entry, byte for byte")
        func capabilityTextIsTheMacsOwn() throws {
            let found = try FixtureInboxService.resolve(entryID: "authored:local-notes")
            let entry = try #require(found)
            // The phone's name for it is deliberately not the registry's, so a substitution shows up
            // as a difference rather than as a coincidence.
            let envelope = InboxEnvelope(
                version: 1,
                id: "q-1",
                entryID: "authored:local-notes",
                displayName: "Totally harmless thing",
                queuedAt: Date(timeIntervalSince1970: 1_755_000_000),
                deviceName: "Luke's iPhone"
            )
            let item = InboxItem(envelope: envelope, resolved: entry)

            let statement = RegistryCapability.statement(for: entry)
            #expect(entry.displayName != envelope.displayName)
            #expect(!statement.headline.contains(envelope.displayName))
            #expect(!statement.detail.contains(envelope.displayName))
            #expect(!statement.argv.contains(envelope.displayName))
            #expect(item.title == entry.displayName, "the row names what the Mac resolved")
        }

        /// An envelope carrying fields nobody asked for contributes no rendered text: the decoder
        /// keeps a coordinate, and everything drawn is looked up from it.
        @Test("an envelope's extra fields reach no rendered string")
        func extraEnvelopeFieldsAreNotRendered() throws {
            let json = """
            {"t":"mcp-router-queue","v":1,"id":"q-x","entry":"authored:local-notes",
             "name":"Local notes","queued":"2026-08-14T10:00:00Z","device":"iPhone",
             "capability":"Runs anything it likes","argv":["rm","-rf","/"]}
            """
            let envelope = try InboxEnvelope.decode(json)
            // Resolved to a `let` before `#require`: the macro's rethrows analysis does not see
            // through a throwing call in its argument, which is the same trap that cost a filter
            // rewrite earlier in this item.
            let found = try FixtureInboxService.resolve(entryID: envelope.entryID)
            let entry = try #require(found)
            let statement = RegistryCapability.statement(for: entry)
            #expect(!statement.headline.contains("Runs anything it likes"))
            #expect(!statement.argv.contains("rm"))
            #expect(!statement.argv.contains("-rf"))
        }

        // MARK: - A15 · indicator colours mean what they mean

        /// `--live`, `--fail` and `--attn` carry meaning (`DESIGN.md` §2); using one decoratively
        /// spends a signal the whole product relies on.
        ///
        /// M6 tints exactly two things in `attention`, and both are the sentence asking for a human
        /// decision — which is what that token means, rather than a failure being reported:
        /// the review sheet's provenance note ("it has not run"), and the pairing sheet's warning
        /// that anyone who scans the code can queue into this inbox. Nothing in M6 reports a running
        /// state, so `live` appears nowhere.
        @Test("M6 spends indicator colours only on their own meaning")
        func indicatorColoursAreNotDecoration() throws {
            var attention: [String] = []
            var live = 0
            for name in Self.views {
                let source = try Self.viewSource(name)
                let uses = source.components(separatedBy: "ColorToken.attention").count - 1
                attention.append(contentsOf: Array(repeating: name, count: uses))
                live += source.components(separatedBy: "ColorToken.live").count - 1
            }
            #expect(live == 0, "nothing in M6 reports a running state, so nothing may tint as one")
            #expect(
                attention == ["InboxReviewSheet.swift", "PairingSheet.swift"],
                "attention is the ask-a-human colour, and nothing else: found \(attention)"
            )
        }

        /// The prototype's `--fail`-tinted capability line is not reproduced: an entry that runs a
        /// local program is a fact to state, not a failure to colour.
        @Test("no capability text is tinted as a failure")
        func capabilityIsNotTintedAsFailure() throws {
            let sheet = try Self.viewSource("InboxReviewSheet.swift")
            let failUses = sheet.components(separatedBy: "ColorToken.fail").count - 1
            #expect(failUses == 1, "the only red thing is the accept failure line")
            // The capability block draws in body/title colours, which is what makes it a statement.
            #expect(sheet.contains("Text(statement.headline)"))
        }

        /// No stock SwiftUI colour anywhere in M6 — the whole palette is tokens (`DESIGN.md` §2,
        /// and the `no-raw-design-values` lint gate for the values themselves).
        @Test("M6 draws no stock colour")
        func noStockColours() throws {
            for name in Self.views {
                let source = try Self.viewSource(name)
                for named in [".red", ".green", ".orange", ".yellow", ".blue", ".purple"] {
                    #expect(!source.contains(named), "\(name) uses a stock colour rather than a token")
                }
            }
        }

        // MARK: - A16 · sentence case, one prominent action, Cancel leads

        /// **A state that has observed nothing says nothing about the queue or the pairing.**
        ///
        /// `InboxCopy.subtitle(waiting: 0, device: nil)` renders "Nothing waiting · no phone paired"
        /// — two claims — and both `.loading` and `.failed` reach it with exactly those arguments,
        /// because there is no snapshot. The badge already refuses this case (`waitingCount` is nil),
        /// so rendering the sentence made the two derivations disagree with the wrong one written out
        /// in words. `DESIGN.md` §6.
        ///
        /// Asserted on the source because the branch is a `body` and the string is what it does or
        /// does not build; the running-app half is in `m6-inbox-pairing.sh` under `loading`.
        @Test("the states that observed nothing pass no subtitle")
        func statesWithoutASnapshotClaimNothing() throws {
            let source = try Self.viewSource("InboxBoard.swift")
            let silent = source.components(separatedBy: "header(subtitle: nil)").count - 1
            #expect(silent == 2, "loading and failed are the two states with no snapshot to describe")
            // And the string they would otherwise have rendered really is the misleading one, so
            // this test is about a claim rather than about a call shape.
            #expect(InboxCopy.subtitle(waiting: 0, device: nil) == "Nothing waiting · no phone paired")
        }

        /// Every user-facing string is sentence case. Asserted on the copy rather than on the views,
        /// because the copy is where the strings are — and Title Case Like This is the failure.
        ///
        /// The rule is applied to words that carry no proper noun: a heuristic that banned any
        /// capital would fail on "Mac", "Servers" and "iPhone", all of which are correct.
        @Test("the copy is sentence case")
        func copyIsSentenceCase() {
            let properNouns: Set = [
                "Mac", "Macs", "Servers", "Conduit", "Settings", "Pair", "Anyone",
                "Install", "Undo", "Cancel", "Decline", "Review", "Pairing", "Done",
                "Inbox", "Nothing", "Things", "Sent", "It", "The", "This", "A", "That",
                "Treat", "Scan", "Update", "Each", "Removing", "Installed", "Declined",
                "On", "Paired", "Preparing", "Reading", "Can't", "What", "Local", "Runs",
                "Starting", "Re-pair", "Check", "You", "Your", "SHA256", "Update"
            ]
            for line in [
                InboxCopy.emptyDetail,
                InboxCopy.partialDetail,
                InboxCopy.provenanceNote,
                InboxCopy.notInstallableDetail,
                InboxCopy.routerOfflineDetail,
                InboxCopy.registryFailureDetail,
                InboxCopy.Pairing.lede,
                InboxCopy.Pairing.warning,
                InboxCopy.Pairing.noEndpointDetail,
                InboxCopy.accepted("Local notes"),
                InboxCopy.declined("Local notes")
            ] {
                // Skip the first word of each sentence; the rest must not be capitalised unless it
                // is a name.
                let words = line.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
                for (index, word) in words.enumerated() where index > 0 {
                    let bare = word.trimmingCharacters(in: .punctuationCharacters)
                    guard let first = bare.first, first.isUppercase, !properNouns.contains(bare) else {
                        continue
                    }
                    // A capital directly after a full stop opens a new sentence, which is fine.
                    let previous = words[index - 1]
                    #expect(
                        previous.hasSuffix(".") || previous.hasSuffix(":"),
                        "'\(bare)' is Title Case mid-sentence in: \(line)"
                    )
                }
            }
        }

        /// §3.4: one prominent accent action per view, trailing, with Cancel leading.
        ///
        /// The review sheet's accept is M6's one prominent control. The board's own header button is
        /// deliberately `StandardButtonStyle` — a settings door is not the view's main verb.
        @Test("exactly one prominent action, in the sheet, with Cancel leading")
        func onlyOneProminentAction() throws {
            let sheet = try Self.viewSource("InboxReviewSheet.swift")
            let prominent = sheet.components(separatedBy: "ProminentButtonStyle").count - 1
            #expect(prominent == 1, "the sheet commits one thing, so it offers one prominent control")

            let cancelAt = try #require(sheet.range(of: "Button(\"Cancel\")"))
            let acceptAt = try #require(sheet.range(of: "Button(acceptLabel)"))
            #expect(cancelAt.lowerBound < acceptAt.lowerBound, "Cancel leads, the commit trails")

            let board = try Self.viewSource("InboxBoard.swift")
            #expect(
                !board.contains("ProminentButtonStyle"),
                "the board's pairing button is a door, not the view's verb"
            )
        }

        /// The `…` rule: a control that opens something further carries one, a control that commits
        /// does not.
        @Test("ellipsis marks the controls that open something further")
        func ellipsisFollowsTheRule() {
            #expect(InboxCopy.pairingButton.hasSuffix("…"))
            #expect(InboxCopy.reviewAction.hasSuffix("…"))
            #expect(!InboxCopy.acceptAction.hasSuffix("…"), "it commits, so it does not trail off")
            #expect(!InboxCopy.declineAction.hasSuffix("…"))
            #expect(!InboxCopy.undoAction.hasSuffix("…"))
        }

        // MARK: - The local refusal

        /// An entry with no install block cannot be declared, and the sheet now says so instead of
        /// returning silently and leaving the press with no visible effect.
        ///
        /// Reported in its own voice rather than as a `ControlAPIError`: every one of those names
        /// the router, and the router was never asked.
        @Test("an entry that describes no install reports a local refusal")
        func notInstallableIsReported() async throws {
            let deepwiki = try FixtureInboxService.resolve(entryID: "smithery:deepwiki")
            let entry = try #require(deepwiki)
            #expect(RegistryCapability.declaration(for: entry, values: [:]) != nil)

            let recorder = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let board = InboxBoardModel(client: recorder, service: FixtureInboxService(.paired))
            await board.load()
            let item = try #require(board.rows.first { !$0.isPartial })
            try await board.accept(#require(AcceptableInboxItem(item)))
            #expect(board.acceptState == .idle, "the fixture's entries do declare an install")
            #expect(recorder.calls.add == 1)
        }

        /// The sentence exists and names the local condition rather than the router's version.
        @Test("the local refusal blames nothing that was not asked")
        func theLocalRefusalNamesItself() {
            #expect(!InboxCopy.notInstallableDetail.contains("router may be"))
            #expect(InboxCopy.notInstallableDetail.contains("Nothing was sent"))
        }
    }
#endif
