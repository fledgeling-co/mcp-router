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
            guard let cells = DesignDocParser.cells(of: String(line)),
                  let first = cells.first else { continue }
            let name = DesignDocParser.normalise(first)
            // Skip the header and its separator, and the trailing per-control note's table if any.
            if name.isEmpty || name == "State" || name.allSatisfy({ $0 == "-" || $0 == ":" }) { continue }
            states.append(name)
        }
        return states
    }

    /// The sheet's derivation table, as a state name → derivation-cell map.
    ///
    /// Parsed rather than substring-searched, because the substring version of this test asserted
    /// only that nine names appeared somewhere in an HTML file. A row reading
    /// `<td>Loading</td><td></td>` satisfied it, as would one whose derivation named a type that
    /// does not exist. The mapping is the artifact under test, so the mapping has to be read.
    static func derivations() throws -> [String: String] {
        let mock = try mockText()
        var map: [String: String] = [:]
        for line in mock.split(separator: "\n") {
            guard line.contains("<tr><td>") else { continue }
            let cells = line
                .replacingOccurrences(of: "<tr>", with: "")
                .components(separatedBy: "</td>")
                .map { $0.replacingOccurrences(of: "<td>", with: "") }
            guard cells.count >= 2 else { continue }
            let name = cells[0].trimmingCharacters(in: .whitespaces)
            // The stream-condition table at the foot of the sheet keys on `<code>` rather than a
            // §5 state name; it is a different table and must not overwrite these rows.
            guard !name.contains("<code>"), !name.isEmpty else { continue }
            map[name] = cells[1]
        }
        return map
    }

    // MARK: - A12, first half: every §5 state is mapped

    @Test("every state DESIGN.md §5 requires has a TrackerState mapped to it in the F4 sheet")
    func everyDesignStateIsMapped() throws {
        let states = try Self.designStates()
        let derivations = try Self.derivations()

        #expect(
            states.count == 9,
            "DESIGN.md §5 no longer lists nine states — it lists \(states.count): \(states)"
        )

        for state in states {
            guard let derivation = derivations[state] else {
                Issue.record("DESIGN.md §5 requires a “\(state)” state and the F4 sheet has no row for it")
                continue
            }
            // A row with an empty derivation cell is not a mapping. This is the half the substring
            // version could not see.
            #expect(
                !derivation.trimmingCharacters(in: .whitespaces).isEmpty,
                "the F4 sheet has a “\(state)” row that maps it to no TrackerState at all"
            )
        }
    }

    /// The bridge the two halves were missing: the sheet and the specimens must agree.
    ///
    /// Coverage proved the sheet named nine states; distinguishability proved seven values differ.
    /// Nothing connected them, so the specimen labelled *Disabled* could carry `.phase(.live)` —
    /// the sheet's own **non**-disabled condition — and both halves still passed. This asserts each
    /// specimen against the derivation the sheet publishes for that name.
    @Test("each specimen is the TrackerState the F4 sheet says produces that state")
    func specimensMatchTheSheetsDerivation() throws {
        let derivations = try Self.derivations()

        for (name, state) in try Self.distinguishable() {
            guard let derivation = derivations[name] else {
                Issue.record("the F4 sheet has no derivation row for “\(name)”")
                continue
            }

            // Each half is checked only where the row actually pins it. Most §5 states are about
            // the load and say nothing about the feed; *Disabled* is the reverse — it is defined
            // by there being no feed, and pins no load state at all. Demanding both of every row
            // would fail the sheet for being precise rather than for being wrong.
            if derivation.contains("load:") {
                let loadToken = switch state.load {
                case .loading: ".loading"
                case .loaded: ".loaded"
                case .stale: ".stale"
                case .failed: ".failed"
                }
                #expect(
                    derivation.contains(loadToken),
                    "“\(name)”: the specimen is \(loadToken) but the sheet derives it from \(derivation)"
                )
            }

            if derivation.contains("stream:") {
                let streamToken = switch state.stream {
                case .notConfigured: ".notConfigured"
                case let .phase(phase): ".phase(.\(phase.rawValue))"
                }
                #expect(
                    derivation.contains(streamToken),
                    "“\(name)”: the specimen's stream is \(streamToken), the sheet says \(derivation)"
                )
            }

            // And no row may pin neither, or the specimen is answerable to nothing.
            #expect(
                derivation.contains("load:") || derivation.contains("stream:"),
                "“\(name)”: the sheet's derivation pins neither a load state nor a stream condition"
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
    static func distinguishable() throws -> [(String, ServerStateTracker.TrackerState)] {
        func state(
            _ load: ServerStateTracker.LoadState,
            _ stream: ServerStateTracker.StreamCondition = .notConfigured
        ) -> ServerStateTracker.TrackerState {
            ServerStateTracker.TrackerState(load: load, stream: stream)
        }

        // `try`, not `try?`. Swallowing a decode failure here would leave `one == []`, which makes
        // "Default" and "Empty" the same value and reports a missing fixture as a modelling
        // collapse — a `try?` hiding an error, in the feature whose whole subject is a `try?`
        // hiding errors.
        let one = try [FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)]

        return [
            ("Loading", state(.loading)),
            // Default carries a live feed; Disabled is the same data with no feed configured. The
            // sheet pins Disabled to `stream: .notConfigured` (and maps `.phase(.live)` to "Call
            // log live", the opposite condition), so these were previously the wrong way round.
            ("Default", state(.loaded(one), .phase(.live))),
            ("Empty", state(.loaded([]))),
            ("Partial", state(.stale(one, .transport(detail: "connection reset")))),
            ("Offline", state(.failed(.routerNotRunning))),
            ("Error", state(.failed(.unauthorized))),
            ("Disabled", state(.loaded(one), .notConfigured))
        ]
    }

    @Test("the states a surface must tell apart are different values")
    func distinguishableStatesAreDistinct() throws {
        let cases = try Self.distinguishable()

        for i in cases.indices {
            for j in cases.indices where j > i {
                #expect(
                    cases[i].1 != cases[j].1,
                    """
                    “\(cases[i].0)” and “\(cases[j].0)” are the same TrackerState — \
                    a surface cannot render both
                    """
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
            """
            stale collapsed into failed — the last good snapshot would be thrown away \
            to report a refresh problem
            """
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
        let mock = try ControlCopyTests.normalised(Self.mockText())

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

    // MARK: - A15: F3's recorded fixtures are the contract R4 will diff against

    /// A15 was stated as a criterion and checked by hand, which means it was checked once.
    ///
    /// The fixtures under `Control/Fixtures/` are what R4's differential parity gate diffs the
    /// Swift router against. F4 wraps `StreamPhase` rather than widening it precisely so that
    /// contract does not move, and this is what keeps the promise after the branch merges — a
    /// later edit to a fixture is otherwise caught by nothing.
    ///
    /// **What this asserted until M29, and why it could not keep asserting it.** The original form
    /// required the diff against `main` to be *empty*: no branch may modify a recording at all.
    /// That invariant holds only while the wire shape is frozen, and M29 widens it deliberately —
    /// `GET /servers` gains a non-optional `disabled`, so every recording that carries a server row
    /// must gain the key or stop decoding (`spec-M29.md` D1). The premise was falsified by a change
    /// the product wanted, not by a branch misbehaving, and an assertion that a correct branch
    /// cannot satisfy stops being a gate.
    ///
    /// **What it asserts instead, and why that is still worth having.** The hazard the empty-diff
    /// form actually caught is a *hand-patched* fixture: one file edited to make one suite go green
    /// while the rest of the directory goes stale. That is now stated directly — recordings move as
    /// a set or not at all. A re-recording through `scripts/capture-control-fixtures.sh` runs the
    /// reference router over every response and therefore rewrites all of them together; a hand
    /// edit reaches for the one file whose suite is red.
    ///
    /// The two halves the empty-diff form also covered are held elsewhere, and are not re-asserted
    /// here: that each recording still decodes, and that its keys and the model's fields correspond
    /// in both directions, are `ControlFixtureTests`' three tests; that the recordings match what
    /// the reference router actually emits is `scripts/acceptance/parity-control.sh`, which diffs
    /// two live routers rather than two files.
    @Test("F3's recorded fixtures move as a set or not at all")
    func fixturesMoveAsASet() throws {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var root: URL?
        for _ in 0 ..< 8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                root = dir
                break
            }
            dir = dir.deletingLastPathComponent()
        }
        let repo = try #require(root, "could not locate the repository root from \(#filePath)")

        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        git.arguments = [
            "git", "-C", repo.path, "diff", "--name-only", "main...HEAD", "--",
            "app/Sources/MCPRouterKit/Control/Fixtures/"
        ]
        let pipe = Pipe()
        git.standardOutput = pipe
        git.standardError = Pipe()
        try git.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(bytes: data, encoding: .utf8) ?? ""
        git.waitUntilExit()

        // A git failure is not a pass. If the command could not run the criterion is unverified,
        // and reporting that as clean is how a gate starts lying.
        #expect(git.terminationStatus == 0, "git could not compare the fixtures directory")

        let changed = Set(
            out.split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)).deletingPathExtension().lastPathComponent }
        )
        // No recording moved: the ordinary case, and nothing further to check.
        guard !changed.isEmpty else { return }

        // Which recordings carry a server row, read from the files rather than listed here, so a
        // recording added later is covered without anyone remembering to add it.
        //
        // `transport` is the marker rather than the presence of a `servers` key, because
        // `usage-summary` also has one and its rows are usage totals per server name — no wire
        // field of `MCPServer` on them, so a change to `MCPServer` does not reach that file and
        // requiring it to move would fail a branch that behaved correctly.
        func carriesServerRow(_ object: Any) -> Bool {
            if let one = object as? [String: Any] {
                if one["transport"] != nil { return true }
                if let rows = one["servers"] as? [Any] {
                    return rows.contains { ($0 as? [String: Any])?["transport"] != nil }
                }
            }
            return false
        }

        var serverBearing: Set<String> = []
        for entry in ControlFixtureTests.expected {
            let fixture = try FixtureControlAPIClient.fixtureData(entry.name)
            if carriesServerRow(try JSONSerialization.jsonObject(with: fixture)) {
                serverBearing.insert(entry.name)
            }
        }

        // The recordings that moved must be exactly the ones the wire change reaches. A branch that
        // re-records through the capture script rewrites all of them; a branch that hand-patches
        // one file to quiet one suite moves a strict subset, and that is what fails here.
        let stale = serverBearing.subtracting(changed)
        #expect(
            stale.isEmpty,
            """
            this branch moved some recordings and left others stale: changed \
            \(changed.sorted()), but these carry a server row and did not move: \(stale.sorted()). \
            Re-record them together with scripts/capture-control-fixtures.sh rather than editing \
            one file by hand.
            """
        )
    }
}
