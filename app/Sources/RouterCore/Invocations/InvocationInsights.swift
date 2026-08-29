import Foundation

/// One row of *Skill and server use, by version* — the table the design of record draws at
/// `design/mcp-router-console.html:3490`.
///
/// A row exists **only for a run whose version the ledger could establish**. The mock's own callout
/// under that table — *"a run against 1.4.0 never counts toward 1.4.2's evidence"* — is this rule,
/// and honouring it means the runs the ledger cannot place appear as
/// ``CapabilityUseWindow/supersededRuns`` and ``CapabilityUseWindow/unestablishedRuns`` beside the
/// table rather than inside it.
public struct CapabilityUseRow: Sendable, Hashable {
    public let kind: CapabilityKind
    public let name: String
    /// The version this row's runs are pinned to, as ``CapabilityVersion/display`` would render it.
    public let version: String
    public let runs: Int
    /// One cell per day of the window, oldest first — the mock's distribution strip. Whole days,
    /// including empty ones, so the strip's shape is the traffic's and not the array's.
    public let perDay: [Int]
    public let lastUsed: String

    public init(
        kind: CapabilityKind,
        name: String,
        version: String,
        runs: Int,
        perDay: [Int],
        lastUsed: String
    ) {
        self.kind = kind
        self.name = name
        self.version = version
        self.runs = runs
        self.perDay = perDay
        self.lastUsed = lastUsed
    }
}

/// One harness's share — or its refusal to give one.
///
/// `runs` is optional and that is the substance, exactly as it is on ``HarnessCallCount``. Measured
/// 2026-08-29: Claude Code is the only harness on this machine whose sessions record a skill run.
/// Codex's rollouts are a different line shape with no skill concept; Grok's 2,169 `*.jsonl` are
/// sandbox events with no tool call in them; Cursor has none. A `0` against any of those would read
/// as *this harness ran no skills*, which is the finding, and it would be fabricated.
public struct HarnessInvocationCount: Sendable, Hashable {
    public let harness: String
    public let runs: Int?
    public let reason: String?

    public init(harness: String, runs: Int?, reason: String? = nil) {
        self.harness = harness
        self.runs = runs
        self.reason = reason
    }
}

/// The window, folded — and every figure that says what the window could not reach.
public struct CapabilityUseWindow: Sendable {
    public let generatedAt: String
    public let days: Int
    /// The first day in the window, `YYYY-MM-DD`.
    public let windowStart: String
    /// The oldest invocation actually held, or nil when the window holds none. What lets a surface
    /// say *not enough history yet* as a measurement — ``InsightsResponse/logHorizon``'s job.
    public let horizon: String?
    /// The oldest version boundary the ledger holds. Nothing before it can be attributed to any
    /// version at all, whatever the invocation log reaches back to, so the two horizons are both
    /// reported and are not the same fact.
    public let ledgerHorizon: String?
    public let rows: [CapabilityUseRow]
    /// Runs whose capability moved version at an unknown moment around them. Counted toward no row.
    public let supersededRuns: Int
    /// Runs the ledger holds no boundary for at all.
    public let unestablishedRuns: Int
    public let harnesses: [HarnessInvocationCount]
    public let accounting: TranscriptAccounting

    public init(
        generatedAt: String,
        days: Int,
        windowStart: String,
        horizon: String?,
        ledgerHorizon: String?,
        rows: [CapabilityUseRow],
        supersededRuns: Int,
        unestablishedRuns: Int,
        harnesses: [HarnessInvocationCount],
        accounting: TranscriptAccounting
    ) {
        self.generatedAt = generatedAt
        self.days = days
        self.windowStart = windowStart
        self.horizon = horizon
        self.ledgerHorizon = ledgerHorizon
        self.rows = rows
        self.supersededRuns = supersededRuns
        self.unestablishedRuns = unestablishedRuns
        self.harnesses = harnesses
        self.accounting = accounting
    }

    /// Every run in the window, however it was dispositioned.
    ///
    /// The identity `attributedRuns + supersededRuns + unestablishedRuns == totalRuns` is what makes
    /// the table readable beside the headline. A surface that printed only the rows would report a
    /// fraction of the traffic as the whole of it.
    public var attributedRuns: Int { rows.reduce(0) { $0 + $1.runs } }
    public var totalRuns: Int { attributedRuns + supersededRuns + unestablishedRuns }
    /// Whether there is anything to draw. A measurement, not a threshold picked by eye.
    public var hasHistory: Bool { horizon != nil }
}

/// What the scan said about itself — the per-harness counts and the drop accounting.
///
/// One parameter rather than two, and not only to sit under this repository's parameter cap: both
/// are the reader reporting on its own reach rather than on the traffic, and a fold handed one
/// without the other could report bars that do not reconcile with what was read.
public struct InvocationReading: Sendable {
    public let harnesses: [HarnessInvocationCount]
    public let accounting: TranscriptAccounting

    public init(harnesses: [HarnessInvocationCount], accounting: TranscriptAccounting) {
        self.harnesses = harnesses
        self.accounting = accounting
    }
}

/// Folding invocations against the ledger.
public enum InvocationInsights {
    /// `YYYY-MM-DD` — the day an orderable UTC instant falls in.
    static func dayKey(_ timestamp: String) -> String? {
        guard VersionLedger.isOrderable(timestamp) else { return nil }
        return String(timestamp.prefix(10))
    }

    /// Fold `events` over the `days` whole days ending with the day `nowMilliseconds` falls in.
    ///
    /// Whole days, ending with the day in progress, for the reason `UsageInsights.Window` gives for
    /// whole hours: a window starting "now minus seven days" to the millisecond makes the end cells
    /// short for arithmetic reasons, and a chart whose last column is low reads as a fall in traffic.
    public static func fold(
        events: [InvocationEvent],
        ledger: VersionLedger,
        reading: InvocationReading,
        nowMilliseconds: Double,
        days: Int
    ) -> CapabilityUseWindow {
        let generatedAt = JSDate.iso8601(milliseconds: nowMilliseconds)
        let span = max(1, days)
        let dayMilliseconds = 86_400_000.0
        let today = (nowMilliseconds / dayMilliseconds).rounded(.down) * dayMilliseconds
        var keys: [String] = []
        for index in 0 ..< span {
            let start = today - Double(span - 1 - index) * dayMilliseconds
            keys.append(String(JSDate.iso8601(milliseconds: start).prefix(10)))
        }
        var fold = Fold(dayKeys: keys)
        for event in events {
            fold.absorb(event, ledger: ledger)
        }
        return fold.reading(
            generatedAt: generatedAt, days: span,
            ledgerHorizon: ledger.horizon, reading: reading
        )
    }

    /// The fold's mutable state.
    ///
    /// A type rather than a pile of `var`s, for the reason ``UsageInsights/Window`` is one: the rules
    /// — which runs are in the window, which row a run counts toward, and which runs count toward no
    /// row at all — are the substance, and one function carrying all of them sits over this
    /// repository's cyclomatic cap.
    private struct Fold {
        let dayKeys: [String]
        var identities: [String] = []
        var rows: [CapabilityUseRow] = []
        var superseded = 0
        var unestablished = 0
        var horizon: String?

        init(dayKeys: [String]) {
            self.dayKeys = dayKeys
        }

        mutating func absorb(_ event: InvocationEvent, ledger: VersionLedger) {
            guard let day = InvocationInsights.dayKey(event.ts), let first = dayKeys.first,
                  day >= first, dayKeys.contains(day)
            else { return }
            if let seen = horizon { horizon = min(seen, event.ts) } else { horizon = event.ts }

            let resolved = event.kind == .skill
                ? ledger.version(ofSkill: event.name, at: event.ts)
                : ledger.version(of: event.kind, event.name, at: event.ts)
            switch resolved {
            case .superseded:
                superseded += 1
            case .unestablished:
                unestablished += 1
            case let .attributed(version, _):
                credit(event, version: version, day: day)
            }
        }

        private mutating func credit(_ event: InvocationEvent, version: String, day: String) {
            let identity = "\(event.kind.rawValue)\u{1F}\(event.name)\u{1F}\(version)"
            guard let index = identities.firstIndex(of: identity) else {
                identities.append(identity)
                var perDay = [Int](repeating: 0, count: dayKeys.count)
                if let slot = dayKeys.firstIndex(of: day) { perDay[slot] += 1 }
                rows.append(CapabilityUseRow(
                    kind: event.kind, name: event.name, version: version,
                    runs: 1, perDay: perDay, lastUsed: event.ts
                ))
                return
            }
            let existing = rows[index]
            var perDay = existing.perDay
            if let slot = dayKeys.firstIndex(of: day) { perDay[slot] += 1 }
            rows[index] = CapabilityUseRow(
                kind: existing.kind, name: existing.name, version: existing.version,
                runs: existing.runs + 1, perDay: perDay,
                lastUsed: max(existing.lastUsed, event.ts)
            )
        }

        func reading(
            generatedAt: String,
            days: Int,
            ledgerHorizon: String?,
            reading: InvocationReading
        ) -> CapabilityUseWindow {
            // Descending by runs, ties broken by name and then by version, so two folds of one
            // unchanged corpus agree — the property `UsageInsights.Caller`'s sort exists for.
            let sorted = rows.sorted { left, right in
                if left.runs != right.runs { return left.runs > right.runs }
                if left.name != right.name { return left.name < right.name }
                return left.version < right.version
            }
            return CapabilityUseWindow(
                generatedAt: generatedAt, days: days, windowStart: dayKeys.first ?? "",
                horizon: horizon, ledgerHorizon: ledgerHorizon,
                rows: sorted, supersededRuns: superseded, unestablishedRuns: unestablished,
                harnesses: reading.harnesses, accounting: reading.accounting
            )
        }
    }
}
