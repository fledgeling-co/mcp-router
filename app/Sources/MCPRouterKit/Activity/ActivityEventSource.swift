import Foundation

/// Where a surface gets its live call records from.
///
/// `ControlEventStream` is a concrete struct that opens a `URLSession` connection, so it cannot be
/// substituted for a recording — and a board tested only against a live socket is a board whose
/// reconnecting and disconnected states are never exercised. This protocol is the seam, and it is
/// deliberately the *narrowest* one that works: one method, returning the events, with the
/// reconnect policy, the SSE parsing and the heartbeat handling all left inside the merged stream
/// type rather than reimplemented behind the seam.
public protocol ActivityEventSource: Sendable {
    func events() -> AsyncStream<StreamEvent>
}

/// The real feed: `GET /usage/stream`, with F3's reconnect policy and its comment handling.
public struct LiveActivityEventSource: ActivityEventSource {
    private let stream: ControlEventStream

    public init(_ stream: ControlEventStream) {
        self.stream = stream
    }

    public func events() -> AsyncStream<StreamEvent> {
        stream.events()
    }
}

/// A recorded sequence, delivered in order and then ended.
///
/// The stream finishing is itself meaningful — `ControlEventStream` finishes its stream when the
/// policy gives up — so this ends rather than hanging, and a consumer that treats "the events
/// stopped" as a condition is exercised by it.
public struct ReplayActivityEventSource: ActivityEventSource {
    private let recorded: [StreamEvent]

    public init(_ recorded: [StreamEvent]) {
        self.recorded = recorded
    }

    public func events() -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            for event in recorded {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
