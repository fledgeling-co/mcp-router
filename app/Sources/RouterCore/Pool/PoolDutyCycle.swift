import Foundation

/// The share of wall-clock time each upstream has been alive, and over what.
///
/// This is the product's own argument expressed as a measurement. A server a harness starts for
/// itself has no reaper: it is spawned at session init and lives until the session ends, so its
/// share is whatever the session is. A server behind this router is opened on the first call to it
/// and closed once it has been idle past its window, and the share is what that leaves.
///
/// **Nothing here is modelled.** Every millisecond in it was measured by the pool between an open
/// and a close it performed. There is no figure for the un-routed world, because the router never
/// ran it and `DESIGN.md` §6 forbids inventing one — the comparison the chart invites is left to
/// the caption, which states the mechanism rather than asserting a percentage.
public struct DutyCycleReading: Sendable, Hashable {
    /// One upstream's alive time. Servers with no time at all are included by the caller when it
    /// knows the declared set, because a server at zero is a reading and its absence is not.
    public struct Server: Sendable, Hashable {
        public let name: String
        public let aliveMilliseconds: Double

        public init(name: String, aliveMilliseconds: Double) {
            self.name = name
            self.aliveMilliseconds = aliveMilliseconds
        }
    }

    /// How long the pool has existed. The denominator, and it is reported rather than divided out
    /// here: a share computed against an uptime of four seconds is arithmetically fine and means
    /// nothing, and only a surface holding both numbers can decline to draw it.
    public let uptimeMilliseconds: Double
    public let servers: [Server]

    public init(uptimeMilliseconds: Double, servers: [Server]) {
        self.uptimeMilliseconds = uptimeMilliseconds
        self.servers = servers
    }
}

extension UpstreamPool {
    /// Add one finished incarnation's alive time to the running total.
    ///
    /// Called from both close paths — the reaper and a session that ended on its own — because an
    /// accounting that only counted deliberate closes would under-report precisely the servers that
    /// fall over, which is the opposite of what this chart is for.
    func recordAlive(name: String, since startedAtMilliseconds: Double) {
        let elapsed = clock.nowMilliseconds - startedAtMilliseconds
        guard elapsed > 0 else { return }
        closedAliveMilliseconds[name, default: 0] += elapsed
    }

    /// Alive time per upstream since this pool started, including the incarnation still open.
    ///
    /// In configuration order, and **every declared upstream is present**, including the ones at
    /// zero: a server that has never been opened is the most informative row on the chart, and a
    /// reading that dropped it would look like a shorter list rather than like a zero.
    public func dutyCycle() -> DutyCycleReading {
        let now = clock.nowMilliseconds
        let servers = orderedNames.map { name in
            var alive = closedAliveMilliseconds[name] ?? 0
            if let open = entries[name]?.handle {
                alive += max(0, now - open.startedAtMilliseconds)
            }
            return DutyCycleReading.Server(name: name, aliveMilliseconds: alive)
        }
        return DutyCycleReading(
            uptimeMilliseconds: max(0, now - startedAtMilliseconds), servers: servers
        )
    }
}
