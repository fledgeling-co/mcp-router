import Foundation
import Testing
@testable import MCPRouterKit

/// The at-rest readout's arithmetic, and the product's central honesty rule.
///
/// `DESIGN.md` §6: *"Numbers the router does not observe are never displayed."* Every test here is
/// ultimately about that one sentence — that a count comes from a response, that a failure removes
/// it rather than freezing or zeroing it, and that the trace describes the window it actually has.
@Suite("At-rest readout")
struct ReadoutModelTests {
    /// A real recorded response, with the running states set for the case under test.
    ///
    /// Built from the fixture rather than hand-assembled: the house rule is to prefer a real value
    /// over a mock, and a hand-built `MCPServer` would let a field drift away from the shape the
    /// router actually serves.
    static func response(running: Int, declared: Int) async throws -> ServersResponse {
        var response = try await FixtureControlAPIClient(.populated).servers()
        let source = response.servers
        #expect(source.count >= 1, "the populated fixture is empty; the recording changed")

        var servers: [MCPServer] = []
        for index in 0 ..< declared {
            var server = source[index % source.count]
            server.name = "server-\(index)"
            server.state = index < running ? .running : .idle
            servers.append(server)
        }
        response.servers = servers
        return response
    }

    static let t0 = Date(timeIntervalSince1970: 1_770_000_000)

    // MARK: - The counts

    @Test("a poll's counts are exactly what the response carried")
    func countsComeFromTheResponse() async throws {
        let model = try await ReadoutModel().applying(Self.response(running: 3, declared: 8), at: Self.t0)
        #expect(model.running == 3)
        #expect(model.declared == 8)
        #expect(model.hasCounts)
        #expect(!model.isEmpty)
    }

    /// A18 — the clause guarding the rule the whole product is built on.
    @Test("when the router is not running the counts are absent, not zero")
    func offlineCountsAreAbsentNotZero() async throws {
        let populated = try await ReadoutModel().applying(Self.response(running: 3, declared: 8), at: Self.t0)
        let offline = populated.applying(.routerNotRunning, at: Self.t0.addingTimeInterval(5))

        #expect(offline.running == nil, "a zero here would be an observation nobody made")
        #expect(offline.declared == nil)
        #expect(!offline.hasCounts)
        #expect(offline.failure == .routerNotRunning)
    }

    /// The other half of the same rule: a failure must not leave the last good numbers on screen
    /// looking current. Absent is honest; stale is a quieter lie than a zero.
    @Test("a failure removes the counts rather than freezing the previous ones")
    func failureDoesNotFreezeStaleCounts() async throws {
        let populated = try await ReadoutModel().applying(Self.response(running: 5, declared: 9), at: Self.t0)
        #expect(populated.running == 5)

        let failed = populated.applying(.transport(detail: "timed out"), at: Self.t0.addingTimeInterval(1))
        #expect(failed.running == nil)
        #expect(failed.declared == nil)
    }

    @Test("a router with nothing declared is empty, which is not the same as no answer")
    func emptyIsDistinctFromNoAnswer() async throws {
        let empty = try await ReadoutModel().applying(Self.response(running: 0, declared: 0), at: Self.t0)
        #expect(empty.isEmpty)
        #expect(empty.declared == 0, "the router answered zero; that is an observation")
        #expect(empty.hasCounts)

        let noAnswer = ReadoutModel()
        #expect(!noAnswer.isEmpty, "no answer is not an empty router")
        #expect(!noAnswer.hasCounts)
    }

    // MARK: - The window

    /// A16's boundary. Tested at the edge rather than in the middle: an off-by-one at a unit
    /// boundary is the bug that ships.
    @Test("a sample at 59s survives and one past 60s is evicted")
    func evictionBoundary() async throws {
        var model = try await ReadoutModel().applying(Self.response(running: 1, declared: 4), at: Self.t0)
        model = try await model.applying(
            Self.response(running: 2, declared: 4),
            at: Self.t0.addingTimeInterval(59)
        )
        #expect(model.samples.count == 2, "the 59s sample is inside the window")

        // One more second and the first sample is 60s old — still inside, on the boundary itself.
        model = try await model.applying(
            Self.response(running: 3, declared: 4),
            at: Self.t0.addingTimeInterval(60)
        )
        #expect(model.samples.count == 3, "a sample exactly 60s old is still in a 60s window")

        // At 61s the first is outside and must go.
        model = try await model.applying(
            Self.response(running: 4, declared: 4),
            at: Self.t0.addingTimeInterval(61)
        )
        #expect(model.samples.count == 3, "the 61s-old sample was not evicted")
        #expect(model.samples.first?.running == 2)
    }

    /// A16 — a failed poll observed nothing, so it must not draw a line to the floor.
    @Test("a failed poll appends no sample and still ages the window")
    func failedPollAppendsNothingAndStillEvicts() async throws {
        var model = try await ReadoutModel().applying(Self.response(running: 2, declared: 4), at: Self.t0)
        #expect(model.samples.count == 1)

        model = model.applying(.routerNotRunning, at: Self.t0.addingTimeInterval(1))
        #expect(model.samples.count == 1, "a failure invented a sample")
        #expect(model.samples.first?.running == 2, "the real sample was overwritten")

        // A minute of failures leaves an empty trace rather than a frozen one — the samples were
        // real when taken, and they age out on their own.
        model = model.applying(.routerNotRunning, at: Self.t0.addingTimeInterval(61))
        #expect(model.samples.isEmpty, "stale samples outlived the window during a failure")
    }

    /// A17 — twenty seconds after launch the trace holds twenty seconds, and saying "last 60s"
    /// there would be a claim about data that does not exist.
    @Test("the trace names the window it actually holds")
    func traceLabelNamesTheRealWindow() async throws {
        var model = try await ReadoutModel().applying(Self.response(running: 1, declared: 4), at: Self.t0)
        model = try await model.applying(
            Self.response(running: 4, declared: 4),
            at: Self.t0.addingTimeInterval(20)
        )

        #expect(model.traceLabel(at: Self.t0.addingTimeInterval(20)) == "last 20s · peak 4")

        var full = model
        full = try await full.applying(
            Self.response(running: 2, declared: 4),
            at: Self.t0.addingTimeInterval(80)
        )
        // The oldest surviving sample is the 20s one, so at 80s the window is the full 60.
        #expect(full.traceLabel(at: Self.t0.addingTimeInterval(80)) == "last 60s · peak 4")
    }

    @Test("an empty trace describes nothing rather than printing a sentence about no data")
    func emptyTraceHasNoLabel() {
        #expect(ReadoutModel().traceLabel(at: Self.t0) == nil)
        #expect(ReadoutModel().observedSpan(at: Self.t0) == nil)
        #expect(ReadoutModel().peak == nil)
    }

    @Test("the peak is the highest simultaneous count inside the window")
    func peakIsInsideTheWindow() async throws {
        var model = try await ReadoutModel().applying(Self.response(running: 9, declared: 9), at: Self.t0)
        model = try await model.applying(
            Self.response(running: 2, declared: 9),
            at: Self.t0.addingTimeInterval(30)
        )
        #expect(model.peak == 9)

        // Once the 9 ages out the peak must fall with it, not linger as a high-water mark.
        model = try await model.applying(
            Self.response(running: 3, declared: 9),
            at: Self.t0.addingTimeInterval(70)
        )
        #expect(model.peak == 3, "the peak outlived the window it is supposed to describe")
    }

    // MARK: - The rule with no code behind it

    /// There is deliberately nothing in `ReadoutModel` from which a memory saving could be
    /// computed. This asserts the absence, because the failure mode is someone adding the field
    /// later and it looking reasonable.
    ///
    /// The allow-list is exhaustive rather than a substring filter, and it earned that when
    /// `notIndexed` was added for §5's Partial state: this test went red on a field that turned out
    /// to be legitimate, which is the behaviour that makes it worth having. Every name below traces
    /// to something the router serves — `running` and `declared` to `/servers`, `notIndexed` to
    /// `MCPServer.indexError`, `samples` to the app's own timestamped record of those polls, and
    /// `failure` to the typed error. A field that cannot be traced that way does not belong here.
    @Test("the model exposes no figure the router does not measure")
    func noFabricatedMetricExists() async throws {
        let model = try await ReadoutModel().applying(Self.response(running: 3, declared: 8), at: Self.t0)
        let mirror = Mirror(reflecting: model)
        let fields = Set(mirror.children.compactMap(\.label))
        #expect(
            fields == ["running", "declared", "notIndexed", "samples", "failure"],
            "an unexpected field appeared: \(fields)"
        )

        for forbidden in ["memory", "saving", "saved", "ram", "bytes", "mb"] {
            #expect(
                !fields.contains { $0.lowercased().contains(forbidden) },
                "a field named for \(forbidden) is a number the router does not observe"
            )
        }
    }
}
