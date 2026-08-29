#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// K3 · the four boards whose one write is a declared control, driven and read on the wire.
    ///
    /// **Why the wire is the only honest channel for a write.** Every board here reports success
    /// from its own model: Discover marks the row installed, the Inbox clears `acceptState` and
    /// closes the sheet, and Harnesses stays `.loaded` whether or not it read anything new. Each of
    /// those is the product's report that it did something, and each of them happens identically
    /// when the request never leaves — which is the acknowledgement-only shape
    /// `references/inert-ui.md` §3 names and the exact tautology the control census exists to
    /// refuse. So every case below reads the request the client recorded, or the row set a second
    /// answer produced, and the same-channel read it declined is named in its own comment.
    ///
    /// **What this lane cannot claim.** The press is made at the model, because a SwiftPM test
    /// cannot actuate a SwiftUI `Button` — so a button rewired to an empty closure while its model
    /// method stayed correct would not fail anything here. That wiring is the interactive-glass
    /// lane's claim, not this one, and it is why the arms in `bin/arm-suites.py` mutate the model
    /// method rather than the view.
    @Suite("K3 · a write control puts something on the wire, or it did nothing")
    @MainActor
    struct BoardWriteActuationTests {
        // MARK: - SURF-005 · Discover → Install

        static func entry(
            id: String,
            command: String,
            args: [String]
        ) -> RegistryEntry {
            RegistryEntry(
                id: id,
                name: id,
                displayName: id.capitalized,
                description: "",
                source: .smithery,
                useCount: nil,
                install: RegistryInstall(type: .stdio, command: command, args: args),
                installed: nil
            )
        }

        static func response(_ results: [RegistryEntry]) -> RegistrySearchResponse {
            RegistrySearchResponse(
                results: results,
                sources: RegistrySources(official: 0, smithery: results.count, merged: results.count),
                warnings: []
            )
        }

        /// Two rows with **different** install blocks, so a handler that declares a fixed payload —
        /// or the row it happened to have selected — fails on the second press rather than passing
        /// twice. One press and one assertion cannot tell those apart.
        ///
        /// The read declined: `board.rows[0].installed == true`, which the board writes itself from
        /// `markInstalled` and which stays true when nothing reaches the router.
        @Test("SURF-005 — Install declares the row that was pressed, and a second press declares the other")
        func installDeclaresTheRowThatWasPressed() async throws {
            let client = DiscoverRecordingClient()
            client.staged = [.success(Self.response([
                Self.entry(id: "alpha", command: "npx", args: ["-y", "alpha-mcp"]),
                Self.entry(id: "beta", command: "uvx", args: ["beta-mcp"])
            ]))]
            let board = DiscoverBoardModel(client: client)
            await board.load()
            try #require(board.rows.count == 2, "the staged answer did not reach the board")
            #expect(client.addedServers.isEmpty, "something declared a server before any press")

            await board.install(board.rows[0], values: [:])
            #expect(client.addedServers.count == 1)
            let first = try #require(client.addedServers.first)
            #expect(first.name == "alpha")
            #expect(first.command == "npx")
            #expect(first.args == ["-y", "alpha-mcp"])

            await board.install(board.rows[1], values: [:])
            #expect(client.addedServers.count == 2)
            let second = try #require(client.addedServers.last)
            #expect(second.name == "beta")
            #expect(second.command == "uvx")
            #expect(second.args == ["beta-mcp"])
            // Two presses, two distinct declarations. A control that sent the same one twice passes
            // every assertion above about the first press.
            #expect(Set(client.addedServers.map(\.name)).count == 2)
        }

        // MARK: - SURF-008 · Inbox → Install

        /// The accept path is the only route in the product by which something a remote device asked
        /// for becomes something that runs, so what matters is the declaration itself and the flag
        /// that decides whether it may replace a server the user already trusts.
        ///
        /// The reads declined: `acceptState == .idle`, `sheetItemID == nil`, and the row leaving
        /// `rows`. All three happen from `record(.accepted(…))` after the call, so all three are
        /// identical over a handler that declared nothing — which is what the arm demonstrates
        /// rather than describes.
        @Test("SURF-008 — Install sends the entry the Mac resolved, and never adopts an existing server")
        func inboxInstallDeclaresTheResolvedEntry() async throws {
            let client = ActuationRecordingClient()
            let board = InboxBoardModel(client: client, service: FixtureInboxService(.paired))
            await board.load()
            let item = try #require(board.rows.first { $0.resolved != nil })
            let acceptable = try #require(AcceptableInboxItem(item))
            #expect(client.declarations.isEmpty, "something declared a server before any press")

            board.sheetItemID = item.id
            await board.accept(acceptable)

            #expect(
                client.declarations.count == 1,
                "the accept reached the router \(client.declarations.count) times"
            )
            let sent = try #require(client.declarations.first)
            #expect(sent.server.name == RegistryPresentation.sanitized(acceptable.entry.name))
            #expect(sent.server.command == acceptable.entry.install?.command)
            // `force: true` adopts an existing declaration, which would let something that arrived
            // from a phone replace the command line of a server the user already trusts.
            #expect(!sent.force)
            // And the row is gone from what the board draws. Kept because it is a real promise, and
            // recorded here as the assertion that would NOT have caught an empty write.
            #expect(!board.rows.contains { $0.id == item.id })
        }

        // MARK: - SURF-008 · Inbox → Decline

        /// Declining is the one disposition that is **local**, so it is read in two places at once:
        /// the rows the board draws lose exactly one row, and the router is told nothing at all.
        /// The second half is the channel the control does not touch, and it is the substance —
        /// a decline that quietly removed a server would satisfy every list assertion here.
        ///
        /// The read declined: `board.dispositioned[item.id] != nil`, the dictionary the call just
        /// wrote, which is the same tautology as a segment reporting itself selected.
        @Test("SURF-008 — Decline removes exactly that row and sends the router nothing")
        func declineRemovesOneRowAndCallsNothing() async throws {
            let client = ActuationRecordingClient()
            let board = InboxBoardModel(client: client, service: FixtureInboxService(.paired))
            await board.load()
            let before = board.rows.map(\.id)
            try #require(before.count >= 2, "one row cannot distinguish removing one from clearing all")
            let target = try #require(board.rows.first)

            board.decline(target)
            await board.pendingWithdrawal?.value

            // Both directions: the survivors are exactly the rest, in order, and the badge counted
            // off the same array agrees. A decline that emptied the board passes neither.
            #expect(board.rows.map(\.id) == before.filter { $0 != target.id })
            #expect(board.waitingCount == before.count - 1)
            // The other channel entirely. Nothing is called on the router: declining is a decision
            // about something that never ran.
            #expect(client.declarations.isEmpty)
            #expect(client.removals.isEmpty)
            #expect(board.isUndoable, "a decline is the reversible disposition")
        }

        // MARK: - SURF-025 · Harnesses → Rescan

        /// `Rescan`'s promise is a **fresh reading**, and a board that redrew the answer it already
        /// had looks identical to one that re-read and got the same thing. So the second answer is
        /// staged to differ: the rows change or the control did nothing.
        ///
        /// The read declined: `board.state` still being `.loaded`, which it was before the press.
        /// The request count alone is declined too — it survives a handler that asks the router and
        /// then throws the answer away, which is what the arm plants.
        @Test("SURF-025 — Rescan asks the router again and draws the second answer, not the first")
        func rescanRedrawsFromTheSecondReading() async throws {
            let client = ActuationRecordingClient(harnesses: [
                HarnessFixtures.response(HarnessFixtures.populated),
                HarnessFixtures.response([])
            ])
            let board = HarnessesBoardModel(client: client)

            await board.load()
            #expect(client.harnessRequests == 1)
            let first = board.rows.map(\.id)
            try #require(!first.isEmpty, "the first reading served no harnesses, so nothing can change")

            await board.load()
            #expect(client.harnessRequests == 2, "Rescan did not ask the router for a fresh reading")
            #expect(board.rows.isEmpty, "the board redrew its first reading rather than the second")
            #expect(board.rows.map(\.id) != first)
            // An answer of none is a reading rather than a failure — the board must not have gone
            // stale or failed on a router that answered perfectly well with an empty list.
            #expect(board.state.error == nil)
        }
    }
#endif
