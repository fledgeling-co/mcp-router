import Foundation
import Testing
@testable import MCPRouterKit

/// The live call log: what arrives, what is ignored, and when it gives up.
@Suite("Call-log stream")
struct ControlStreamTests {
    private static func record(_ server: String, _ tool: String) -> String {
        """
        data: {"ts":"2026-08-14T00:00:00.000Z","server":"\(server)","tool":"\(tool)",\
        "ok":true,"ms":12,"cold":false}
        """
    }

    /// The property that makes it a live log rather than a download.
    ///
    /// Asserted by *ordering* rather than by count, because a stream that buffers everything and
    /// delivers it at the end passes any count-based test while being the exact thing this is not
    /// allowed to be. The stub spaces its events out; the first has to arrive before the last is
    /// even sent.
    ///
    /// Ordering, specifically, and not a wall-clock budget. The budget version measured from
    /// before the connection was opened, so it charged URLSession setup and the TCP handshake to
    /// stream latency: on a contended CI runner the first record landed at 0.52s against a 0.36s
    /// bound and failed, while streaming correctly. Comparing two instants on the stub's own
    /// timeline removes setup from the question and leaves nothing to tune.
    @Test("events arrive as they happen, not in one batch at the end")
    func eventsArriveIncrementally() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        let gap = 0.12
        stub.onStream(
            HTTPStub.Stream(
                lines: [Self.record("a", "one"), Self.record("b", "two"), Self.record("c", "three")],
                gap: gap
            )
        )

        let subject = ControlEventStream(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            policy: ReconnectPolicy(
                initialDelay: .milliseconds(1),
                ceiling: .milliseconds(2),
                maximumAttempts: 1
            )
        )

        var firstRecordAt: Date?
        var records: [CallRecord] = []

        // Scoped to the first connection. The stub replays its script to whoever connects, so
        // reading past the reconnect would count the same events twice.
        collect: for await event in subject.events() {
            switch event {
            case let .record(record):
                if firstRecordAt == nil { firstRecordAt = Date() }
                records.append(record)
                if records.count == 3 { break collect }
            case .phase(.reconnecting), .phase(.disconnected):
                break collect
            case .phase(.live):
                continue
            }
        }

        #expect(records.count == 3)
        #expect(records.map(\.tool) == ["one", "two", "three"])

        let arrival = try #require(firstRecordAt)
        let lastSent = try #require(stub.lastLineSentAt, "the stub never sent its last line")
        #expect(
            arrival < lastSent,
            """
            the first record surfaced \(arrival.timeIntervalSince(lastSent))s AFTER the stub's \
            last line — a batch delivered at the end, not a live stream
            """
        )
    }

    /// The router keeps the socket open with comment lines. Decoding them would produce a steady
    /// trickle of parse failures that look exactly like a router gone wrong.
    /// Asserts the **whole** event sequence, not just the records in it.
    ///
    /// An earlier version collected records only, and the red-green pass walked straight through
    /// it: a comment line made to `yield(.phase(.live))` produced three spurious events and the
    /// test still passed, because it never looked at anything but records. "Ignored" has to mean
    /// no event of any kind, or the assertion only covers half the clause.
    @Test("heartbeat and greeting comments are ignored rather than decoded")
    func heartbeatsAreSkipped() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.onStream(
            HTTPStub.Stream(
                lines: [": connected", ": ping", Self.record("a", "one"), ": ping", Self.record("b", "two")],
                gap: 0.01
            )
        )

        let subject = ControlEventStream(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            policy: ReconnectPolicy(
                initialDelay: .milliseconds(1),
                ceiling: .milliseconds(2),
                maximumAttempts: 1
            )
        )

        // The body ends after five lines and the stream reconnects, so the run is bounded by the
        // first phase that is not `.live` rather than by a record count — counting records is what
        // let the spurious events through in the first place.
        var events: [StreamEvent] = []
        collect: for await event in subject.events() {
            switch event {
            case .phase(.reconnecting), .phase(.disconnected): break collect
            default: events.append(event)
            }
        }

        let records = events.compactMap { event -> CallRecord? in
            guard case let .record(record) = event else { return nil }
            return record
        }
        #expect(records.map(\.tool) == ["one", "two"], "a comment line was decoded as an event")

        // Three comment lines went past. The only phase in the sequence is the one the connection
        // itself accounts for: it opened.
        let phases = events.compactMap { event -> StreamPhase? in
            guard case let .phase(phase) = event else { return nil }
            return phase
        }
        #expect(phases == [.live], "a comment line produced a phase event of its own: \(phases)")
        #expect(events.count == 3, "the stream emitted something no line accounts for: \(events)")
    }

    // MARK: - The retry policy

    /// The stated policy is the *default* one, and until this existed nothing pinned it.
    ///
    /// Every other test here builds a policy with explicit values, so the numbers A11 states —
    /// half a second, a thirty-second ceiling, six attempts — could have been changed to anything
    /// at all and the whole suite would have stayed green. The red-green pass found that by moving
    /// the ceiling to 30000s and the cap to 600 and watching nothing go red.
    @Test("the stated policy is the one you get without asking")
    func defaultPolicyIsTheStatedOne() {
        let policy = ReconnectPolicy()

        #expect(policy.initialDelay == .milliseconds(500))
        #expect(policy.ceiling == .seconds(30))
        #expect(policy.maximumAttempts == 6)
        #expect(
            policy.minimumHealthyDuration == .seconds(5),
            """
            the health threshold has to be under the router's 25s heartbeat, or a quiet but \
            healthy stream would be counted as flapping
            """
        )

        // And the defaults produce the stated curve, ceiling included.
        #expect(policy.delay(forAttempt: 1) == .milliseconds(500))
        #expect(policy.delay(forAttempt: 7) == .seconds(30))
        #expect(policy.delay(forAttempt: 100) == .seconds(30))
    }

    @Test("the delay doubles from the first retry and then holds at the ceiling")
    func backoffDoublesAndHolds() {
        let policy = ReconnectPolicy(
            initialDelay: .milliseconds(500),
            ceiling: .seconds(30),
            maximumAttempts: 6
        )

        #expect(policy.delay(forAttempt: 1) == .milliseconds(500))
        #expect(policy.delay(forAttempt: 2) == .seconds(1))
        #expect(policy.delay(forAttempt: 3) == .seconds(2))
        #expect(policy.delay(forAttempt: 4) == .seconds(4))
        #expect(policy.delay(forAttempt: 5) == .seconds(8))
        // 0.5 × 2^6 is 32s, past the ceiling, and every attempt after it stays there.
        #expect(policy.delay(forAttempt: 7) == .seconds(30))
        #expect(policy.delay(forAttempt: 20) == .seconds(30))
    }

    /// The whole point of a bounded policy: a router that has gone for good is reported, rather
    /// than retried in silence forever — which is indistinguishable from a stream that is simply
    /// quiet.
    @Test("after the stated number of failures it reports disconnected and stops retrying")
    func retryingStopsAndSaysSo() async throws {
        let clock = RecordingStreamClock()
        let subject = try ControlEventStream(
            // Port 1 is reserved; nothing will ever answer.
            baseURL: #require(URL(string: "http://127.0.0.1:1")),
            session: URLSession(configuration: .ephemeral),
            policy: ReconnectPolicy(
                initialDelay: .milliseconds(500),
                ceiling: .seconds(30),
                maximumAttempts: 6
            ),
            clock: clock
        )

        var phases: [StreamPhase] = []
        for await event in subject.events() {
            if case let .phase(phase) = event { phases.append(phase) }
        }

        // The stream ended on its own — that is what "stops retrying" means, and a stream that
        // retried forever would never have left the loop above.
        #expect(phases.last == .disconnected, "it must say it gave up, saw \(phases)")
        #expect(
            phases.filter { $0 == .reconnecting }.count == 5,
            "six attempts means five waits between them, saw \(phases)"
        )

        let waits = await clock.recorded()
        #expect(
            waits == [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)],
            "the delays are not the stated sequence: \(waits)"
        )
    }

    /// A connection that worked resets the count. Without this the six is cumulative rather than
    /// consecutive, so a stream that reconnected happily all day would eventually stop for a reason
    /// no one could see.
    @Test("a connection that stayed up resets the consecutive-failure count")
    func successfulConnectionResetsTheCount() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.onStream(HTTPStub.Stream(lines: [": connected", Self.record("a", "one")], gap: 0.01))

        let clock = RecordingStreamClock()
        let subject = ControlEventStream(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            policy: ReconnectPolicy(
                initialDelay: .milliseconds(1),
                ceiling: .milliseconds(4),
                maximumAttempts: 3,
                // Every connection here is short by design, so the health threshold is taken out
                // of the question: this test is about the reset existing at all. The threshold
                // itself is the subject of the next one.
                minimumHealthyDuration: .zero
            ),
            clock: clock
        )

        // The stub serves the same short script on every connection, so each attempt succeeds and
        // is closed. If the counter did not reset, this would reach `.disconnected` after three;
        // because it does, it keeps reconnecting and we stop it ourselves.
        var reconnects = 0
        var sawDisconnected = false
        for await event in subject.events() {
            if case let .phase(phase) = event {
                if phase == .reconnecting { reconnects += 1 }
                if phase == .disconnected { sawDisconnected = true; break }
                if reconnects >= 5 { break }
            }
        }

        #expect(reconnects >= 5, "it stopped reconnecting despite every connection working")
        #expect(!sawDisconnected, "a working connection was counted as a consecutive failure")
    }

    /// The case the bound exists for, and the one it could not reach.
    ///
    /// The router greets every connection with `: connected` the instant it opens. So a router that
    /// is up but broken — accepting, greeting, dropping — delivered a line on every attempt, and
    /// "delivered anything" reset the counter each time. The stream retried it **forever**, which
    /// is indistinguishable on screen from a stream that is simply quiet, and is exactly what A11
    /// says must not happen. The test above even asserted that behaviour as correct.
    ///
    /// A connection now has to *last* to count as having worked. This stub behaves identically to
    /// that broken router, and the stream must give up.
    @Test("a router that greets and immediately drops is bounded, not retried forever")
    func flappingRouterIsBounded() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        // Greets, sends nothing else, closes. Exactly what an up-but-broken router looks like.
        stub.onStream(HTTPStub.Stream(lines: [": connected"], gap: 0.01))

        let clock = RecordingStreamClock()
        let subject = ControlEventStream(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            policy: ReconnectPolicy(
                initialDelay: .milliseconds(1),
                ceiling: .milliseconds(4),
                maximumAttempts: 3,
                // No connection this stub makes will last thirty seconds.
                minimumHealthyDuration: .seconds(30)
            ),
            clock: clock
        )

        var phases: [StreamPhase] = []
        for await event in subject.events() {
            if case let .phase(phase) = event { phases.append(phase) }
            // The escape hatch matters as much as the assertion. Without it, a regression that
            // restores the unbounded loop does not fail this test — it hangs it, and a hung suite
            // reports nothing at all. Three attempts can produce at most a handful of phases, so
            // anything past ten is the loop this test exists to catch.
            if phases.count > 10 { break }
        }

        #expect(
            phases.last == .disconnected,
            "it never gave up on a router that only ever greeted and dropped: \(phases)"
        )
        #expect(
            phases.filter { $0 == .reconnecting }.count == 2,
            "three attempts means two waits between them, saw \(phases)"
        )
    }

    /// A record this version cannot parse is skipped so one bad event cannot tear down a working
    /// stream — but skipping it *silently* is the same failure this codebase forbids by name,
    /// moved to the stream: a router emitting records the client cannot read would look exactly
    /// like a router with nothing to say. It has to leave a trace, by shape and never by content.
    @Test("an unreadable record is skipped, but not silently")
    func unreadableRecordsAreLogged() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.onStream(
            HTTPStub.Stream(
                lines: ["data: {\"nonsense\":true}", Self.record("a", "one")],
                gap: 0.01
            )
        )

        let sink = CollectingLogSink()
        let subject = ControlEventStream(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            policy: ReconnectPolicy(
                initialDelay: .milliseconds(1),
                ceiling: .milliseconds(4),
                maximumAttempts: 1,
                minimumHealthyDuration: .zero
            ),
            log: ControlLog(sink: sink)
        )

        var records: [CallRecord] = []
        for await event in subject.events() {
            if case let .record(record) = event { records.append(record) }
            if case .phase(.disconnected) = event { break }
            if case .phase(.reconnecting) = event { break }
        }

        #expect(records.map(\.tool) == ["one"], "the readable record after the bad one was lost")

        var written = ""
        for _ in 0 ..< 100 where written.isEmpty {
            written = await sink.joined()
            if written.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(written.contains("could not decode"), "the skipped record left no trace: \(written)")
        #expect(!written.contains("nonsense"), "the log carried the record's content, not its shape")
    }
}
