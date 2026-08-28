#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// J2 · the three boards whose filter bars are declared controls, driven one segment at a time.
    ///
    /// **Why a segmented control is exactly the inert-UI shape.** A filter chip renders, carries its
    /// accessible name, satisfies a contrast gate and reports itself selected whether or not
    /// anything downstream reads the value it wrote. `board.filter == .running` after setting
    /// `board.filter = .running` is the property the assignment just made — the actuation side of a
    /// vacuous assertion (`detector-defects.md` §11), and the same tautology as a button whose proof
    /// is that it now looks pressed.
    ///
    /// So every case here reads the **row set the table draws**, which is a different channel from
    /// the one that struck and is the state the segment exists to change. Each is asserted in both
    /// directions where the population allows: the rows that survive are exactly the ones that
    /// match, and the rows that vanished are exactly the ones that do not. A one-directional check
    /// passes on a filter that returns nothing at all, and on one that returns everything.
    @Suite("J2 · a filter segment changes the rows, not only itself")
    struct BoardFilterActuationTests {
        // MARK: - SURF-002 · All / Running / Idle / Needs you

        @MainActor
        static func serversBoard() -> ServersBoardModel {
            let client = FixtureControlAPIClient(.populated)
            return ServersBoardModel(client: client, tracker: ServerStateTracker(client: client, stream: nil))
        }

        static func server(
            _ name: String,
            state: ServerState = .running,
            placard: Placard? = nil
        ) throws -> MCPServer {
            var s = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
            s.name = name
            s.state = state
            s.placard = placard
            return s
        }

        /// Four servers chosen so no two segments have the same answer: one plain running, one
        /// plain idle, one running-but-placarded (which `needsYou` claims and `idle` must not), and
        /// one idle-and-placarded (which both claim). A population where `Running` and `Needs you`
        /// coincided would let a segment that ignored its own value still look right.
        @MainActor
        @Test("SURF-002 — each Servers segment draws its own rows, and hides exactly the rest")
        func eachServersSegmentFiltersTheTable() throws {
            let board = Self.serversBoard()
            let flagged = Placard(reason: "under maintenance", substitute: nil, until: nil)
            let servers = try [
                Self.server("alpha", state: .running),
                Self.server("beta", state: .idle),
                Self.server("gamma", state: .running, placard: flagged),
                Self.server("delta", state: .idle, placard: flagged)
            ]
            let state = ServerStateTracker.TrackerState(load: .loaded(servers), stream: .notConfigured)

            let expected: [ServerFilter: [String]] = [
                .all: ["alpha", "beta", "gamma", "delta"],
                .running: ["alpha", "gamma"],
                .idle: ["beta", "delta"],
                .needsYou: ["gamma", "delta"]
            ]
            for segment in ServerFilter.allCases {
                board.filter = segment
                let drawn = board.rows(from: state).map(\.id)
                #expect(
                    drawn == expected[segment],
                    "pressing \(segment.title) drew \(drawn) rather than \(expected[segment] ?? [])"
                )
                // The complement, so a segment that returned everything or nothing fails here.
                let hidden = servers.filter { !drawn.contains($0.name) }
                #expect(
                    hidden.allSatisfy { !segment.matches($0) },
                    "\(segment.title) hid a row that matches it: \(hidden.map(\.name))"
                )
            }
            // Four segments, four different answers — a bar whose segments all led to one row set
            // would collapse to fewer than four here however green each individual check looked.
            #expect(Set(expected.values.map { $0.joined(separator: ",") }).count == 4)
        }

        // MARK: - SURF-004 · All / Held

        /// `Held` is the one Skills segment whose population the fixture can be relied on to make
        /// non-trivial, so it is the one asserted in both directions. `All` is asserted as the
        /// restoration, which is the assertion that fails if a segment latches.
        @MainActor
        @Test("SURF-004 — Held draws exactly the skills with something held, and All restores")
        func eachSkillsSegmentFiltersTheTable() async throws {
            let board = SkillsBoardModel(client: FixtureControlAPIClient(.populated))
            await board.load()
            let everything = board.rows
            try #require(!everything.isEmpty, "the fixture served no skills, so nothing was filtered")

            board.filter = .held
            let held = board.rows
            #expect(
                held.allSatisfy { $0.held?.wantsMore ?? false },
                "Held drew a skill with nothing held: \(held.map(\.id))"
            )
            let hidden = everything.filter { skill in !held.contains { $0.id == skill.id } }
            #expect(
                hidden.allSatisfy { !($0.held?.wantsMore ?? false) },
                "Held hid a skill that has an update held: \(hidden.map(\.id))"
            )

            board.filter = .all
            #expect(board.rows.map(\.id) == everything.map(\.id), "All did not restore the whole list")
        }

        // MARK: - SURF-006 · All / Not met / Not observed / Unstamped

        @MainActor
        @Test("SURF-006 — each Checks segment draws exactly the subjects that match it")
        func eachChecksSegmentFiltersTheTable() async throws {
            let client = FixtureControlAPIClient(.partial)
            let board = EvalsBoardModel(
                client: client,
                store: CheckHistoryStore(directory: Self.scratchDirectory())
            )
            await board.load()
            board.filter = .all
            let everything = board.rows
            try #require(!everything.isEmpty, "the fixture served no subjects, so nothing was filtered")

            var narrowed = 0
            for segment in CheckPresentation.Filter.allCases {
                board.filter = segment
                let drawn = board.rows
                // Both directions, off the segment's own predicate: what survives matches, and what
                // vanished does not. One direction alone passes on a segment that draws nothing and
                // on one that draws everything.
                #expect(
                    drawn.allSatisfy { segment.matches($0) },
                    "\(segment.title) drew a subject that does not match it: \(drawn.map(\.id))"
                )
                let hidden = everything.filter { subject in !drawn.contains { $0.id == subject.id } }
                #expect(
                    hidden.allSatisfy { !segment.matches($0) },
                    "\(segment.title) hid a subject that matches it: \(hidden.map(\.id))"
                )
                if drawn.count < everything.count { narrowed += 1 }
            }
            // Without this the loop above passes on a bar that ignores every press: four subsets of
            // the whole board are four copies of the whole board, and every assertion holds.
            #expect(narrowed > 0, "no Checks segment narrowed the board, so none of them did anything")

            board.filter = .all
            #expect(board.rows.map(\.id) == everything.map(\.id), "All did not restore the whole list")
        }

        /// A directory the history store can own for one test, under the process's temporary
        /// directory rather than the developer's own application support.
        static func scratchDirectory() -> URL {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mcprouter-checks-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }
#endif
