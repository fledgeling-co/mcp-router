import Foundation

/// The pool's two Insights readings, taken live.
///
/// A separate port from ``PoolSnapshotPort`` because both are `async` and neither can be
/// usefully snapshotted ahead of the request: `residentMb()` shells out to `ps`, so taking it on
/// every control request would put a subprocess behind `GET /servers`, and a duty cycle that was
/// measured a moment ago is simply a wrong one.
public struct PoolInsightsPort: InsightsSource {
    let pool: UpstreamPool

    public init(pool: UpstreamPool) {
        self.pool = pool
    }

    public func resident() async -> [ResidentReading] {
        // `residentMb()` already omits an upstream with no local process, which is the behaviour
        // that matters here: an HTTP upstream has no child to measure, and reporting it at zero
        // would put a number nobody took into a figure labelled "measured, not modelled".
        await pool.residentMb()
            .map { ResidentReading(server: $0.key, megabytes: $0.value) }
            .sorted { $0.server < $1.server }
    }

    public func dutyCycle() async -> DutyCycleReading {
        await pool.dutyCycle()
    }
}
