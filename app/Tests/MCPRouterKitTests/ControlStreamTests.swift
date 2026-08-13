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
    /// Asserted by *timing* rather than by count, because a stream that buffers everything and
    /// delivers it at the end passes any count-based test while being the exact thing this is not
    /// allowed to be. The stub spaces its events out; the first has to arrive before the last is
    /// even sent.
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

        let start = Date()
        var firstRecordAt: TimeInterval?
        var records: [CallRecord] = []

        // Scoped to the first connection. The stub replays its script to whoever connects, so
        // reading past the reconnect would count the same events twice.
        collect: for await event in subject.events() {
            switch event {
            case let .record(record):
                if firstRecordAt == nil { firstRecordAt = Date().timeIntervalSince(start) }
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
        #expect(
            arrival < gap * 3,
            """
            the first record took \(arrival)s, by which time all three had been sent — \
            that is a batch delivered at the end, not a live stream
            """
        )
    }

    /// The router keeps the socket open with comment lines. Decoding them would produce a steady
    /// trickle of parse failures that look exactly like a router gone wrong.
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

        var records: [CallRecord] = []
        collect: for await event in subject.events() {
            switch event {
            case let .record(record):
                records.append(record)
                if records.count == 2 { break collect }
            case .phase(.reconnecting), .phase(.disconnected):
                break collect
            case .phase(.live):
                continue
            }
        }

        #expect(records.map(\.tool) == ["one", "two"], "a comment line was decoded as an event")
    }

    // MARK: - The retry policy

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
    @Test("a connection that delivered anything resets the consecutive-failure count")
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
                maximumAttempts: 3
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
}
