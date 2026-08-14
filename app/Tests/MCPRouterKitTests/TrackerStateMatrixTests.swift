import Foundation
import Testing
@testable import MCPRouterKit

/// The bridge between `DESIGN.md` §5 and the type M2 and M3 will read.
///
/// F4 ships no surface, so "does it work" cannot be answered by looking at one. What can be
/// answered, and is the whole reason this feature exists as its own item, is whether a surface
/// *could* render each of §5's nine states from a `TrackerState` alone. Two halves:
///
/// 1. **Coverage** — every state named in `DESIGN.md` §5 has a row in the F4 specimen sheet saying
///    which `TrackerState` produces it. A tenth state added to the document fails this until the
///    mapping is extended, rather than being silently unrepresented.
/// 2. **Distinguishability** — the states that must be told apart *are* different values. A model
///    that collapses two of them cannot be fixed by better rendering, and this is where such a
///    collapse is caught.
///
/// The parity direction matters. Asserting only that the mock mentions nine names would pass a mock
/// listing them in prose while the type expressed three; asserting only that the values differ
/// would pass a type nobody had mapped to the design. Both halves, or neither is worth much.
@Suite("Tracker state matrix")
struct TrackerStateMatrixTests {
    /// The F4 specimen sheet, found by walking up from this file — the same way `ControlCopyTests`
    /// finds F3's, and deliberately a hard failure rather than a skip when it is missing.
    static func mockText() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = dir.appendingPathComponent("design/mocks/html/f4-tracker-states.html")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw MatrixError.mockNotFound
    }

    enum MatrixError: Error { case mockNotFound, stateTableNotFound }

    /// The state names in `DESIGN.md` §5's table, read from the document rather than hardcoded.
    ///
    /// Hardcoding the nine here would defeat the test: the document is the authority, and a list
    /// copied into the test agrees with itself forever no matter what §5 says.
    static func designStates() throws -> [String] {
        let url = try DesignDocParser.designDocURL()
        let text = try String(contentsOf: url, encoding: .utf8)

        guard let sectionStart = text.range(of: "## 5 · The states are the design") else {
            throw MatrixError.stateTableNotFound
        }
        let afterHeading = text[sectionStart.upperBound...]
        let section = afterHeading.range(of: "\n## ").map { String(afterHeading[..<$0.lowerBound]) }
            ?? String(afterHeading)

        var states: [String] = []
        for line in section.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let cells = DesignDocParser.cells(of: String(line)), let first = cells.first else { continue }
            let name = DesignDocParser.normalise(first)
            // Skip the header and its separator, and the trailing per-control note's table if any.
            if name.isEmpty || name == "State" || name.allSatisfy({ $0 == "-" || $0 == ":" }) { continue }
            states.append(name)
        }
        return states
    }

    // MARK: - A12, first half: every §5 state is mapped

    @Test("every state DESIGN.md §5 requires has a TrackerState mapped to it in the F4 sheet")
    func everyDesignStateIsMapped() throws {
        let states = try Self.designStates()
        let mock = try Self.mockText()

        #expect(states.count == 9, "DESIGN.md §5 no longer lists nine states — it lists \(states.count): \(states)")

        for state in states {
            // The derivation table writes each state name as its own leading cell. A mention in
            // prose elsewhere on the page is not a mapping and must not satisfy this.
            #expect(
                mock.contains("<td>\(state)</td>"),
                "DESIGN.md §5 requires a “\(state)” state and the F4 sheet maps no TrackerState to it"
            )
        }
    }

    // MARK: - A12, second half: the states that must differ, do

    /// The seven conditions a surface distinguishes by reading `load` and `stream`.
    ///
    /// Two of §5's nine are deliberately absent from this list, and saying why is the point:
    ///
    /// - **Success** is not a value, it is the *transition* into `.loaded` from `.stale` or
    ///   `.failed`. A surface observes it through `updates()`; a distinct "succeeded" case would be
    ///   a state the tracker never leaves, which is worse than not having one.
    /// - **Overflow** is a property of a server's name, not of the tracker. It occurs in any load
    ///   state and changes nothing the tracker reports — which is exactly why the tracker must not
    ///   truncate: a shortened name would be a value no source reported.
    ///
    /// Claiming nine distinct values here would be the more impressive-looking assertion and a
    /// false one.
    static func distinguishable() -> [(String, ServerStateTracker.TrackerState)] {
        func state(
            _ load: ServerStateTracker.LoadState,
            _ stream: ServerStateTracker.StreamCondition = .notConfigured
        ) -> ServerStateTracker.TrackerState {
            ServerStateTracker.TrackerState(load: load, stream: stream)
        }

        let one = [try? FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)]
            .compactMap { $0 }

        return [
            ("Loading", state(.loading)),
            ("Default", state(.loaded(one))),
            ("Empty", state(.loaded([]))),
            ("Partial", state(.stale(one, .transport(detail: "connection reset")))),
            ("Offline", state(.failed(.routerNotRunning))),
            ("Error", state(.failed(.unauthorized))),
            ("Disabled", state(.loaded(one), .phase(.live))),
        ]
    }

    @Test("the states a surface must tell apart are different values")
    func distinguishableStatesAreDistinct() throws {
        let cases = Self.distinguishable()

        for i in cases.indices {
            for j in cases.indices where j > i {
                #expect(
                    cases[i].1 != cases[j].1,
                    "“\(cases[i].0)” and “\(cases[j].0)” are the same TrackerState — a surface cannot render both"
                )
            }
        }
    }

    /// The pair the brief singles out, asserted on its own so a failure names the right thing.
    @Test("a stale snapshot is not the same state as a failure with nothing behind it")
    func staleIsNotFailed() throws {
        let error = ControlAPIError.transport(detail: "connection reset")
        let one = try [FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)]

        #expect(
            ServerStateTracker.LoadState.stale(one, error) != .failed(error),
            "stale collapsed into failed — the last good snapshot would be thrown away to report a refresh problem"
        )
        // And the type cannot express the lie in the other direction: a failure with rows behind it
        // is not constructible, because `.failed` carries no servers at all.
        #expect(ServerStateTracker.TrackerState(load: .failed(error), stream: .notConfigured).servers.isEmpty)
    }

    /// The other collapse, in the other direction.
    @Test("no stream configured is not the same as a stream that dropped")
    func notConfiguredIsNotDisconnected() {
        #expect(
            ServerStateTracker.StreamCondition.notConfigured != .phase(.disconnected),
            "a polling-only tracker and a dropped stream became the same state"
        )
    }

    /// F3 drew this distinction and this is the type that consumes it.
    @Test("unauthorized does not degrade into “an error”")
    func unauthorizedKeepsItsIdentity() {
        #expect(
            ServerStateTracker.LoadState.failed(.unauthorized) != .failed(.routerNotRunning)
        )
        #expect(
            ServerStateTracker.LoadState.failed(.unauthorized)
                != .failed(.server(status: 401, message: "unauthorized", hint: nil)),
            "a 401 from the server and a rotated token became the same state, and they have different fixes"
        )
    }

    // MARK: - A13: the sheet shows the copy the client actually ships

    @Test("the F4 sheet's full-pane copy is the copy ControlAPIError returns")
    func sheetCopyMatchesTheClient() throws {
        let mock = ControlCopyTests.normalised(try Self.mockText())

        for error in [ControlAPIError.routerNotRunning, .unauthorized] {
            #expect(
                mock.contains(ControlCopyTests.normalised(error.headline)),
                "the F4 sheet no longer contains the headline for \(error)"
            )
            #expect(
                mock.contains(ControlCopyTests.normalised(error.advice)),
                "the F4 sheet no longer contains the body copy for \(error)"
            )
            if let action = error.actionLabel {
                #expect(
                    mock.contains(ControlCopyTests.normalised(action)),
                    "the F4 sheet no longer offers “\(action)”"
                )
            }
        }
    }
}
