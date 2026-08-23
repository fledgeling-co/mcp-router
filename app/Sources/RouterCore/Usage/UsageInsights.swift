import Foundation

/// What the call log says about a window of time.
///
/// The Insights board needs three things the per-server aggregate cannot answer — how many calls
/// arrived in the last day, which caller they came from, and how they were spread across the hours
/// — and all three are in the log rather than in the rollup, which has no time axis at all.
///
/// **The horizon is part of the answer.** The log rotates at 8 MiB keeping one generation, so a
/// window is only ever as long as what survives; ``horizon`` is the oldest record actually read, so
/// a surface can say what it covered rather than implying it covered the whole window. That is what
/// makes the brief's *"a window with too little history says so"* a measurement instead of a guess.
///
/// **Time is compared as text, deliberately.** Every timestamp here is written by
/// ``JSDate/iso8601(milliseconds:)`` or by the reference's `toISOString()`, both of which produce
/// `YYYY-MM-DDTHH:MM:SS.sssZ` — fixed width, UTC, zero-padded — and that format sorts
/// lexicographically in the same order it sorts chronologically. So the window test is a string
/// comparison and the hour bucket is a 13-character prefix. No date parser is introduced, and a
/// timestamp that is *not* in that shape cannot be silently mis-bucketed: it fails the prefix
/// length test and is counted as dropped.
public struct UsageInsights: Sendable, Hashable {
    /// One hour of the window, oldest first.
    public struct Hour: Sendable, Hashable {
        public let startMilliseconds: Double
        public let calls: Int

        public init(startMilliseconds: Double, calls: Int) {
            self.startMilliseconds = startMilliseconds
            self.calls = calls
        }
    }

    /// One caller, named exactly as the router observed it. `client` is a process name, never a
    /// harness name — see ``ClientProcessName`` for why the two are not the same claim.
    public struct Caller: Sendable, Hashable {
        public let client: String
        public let calls: Int

        public init(client: String, calls: Int) {
            self.client = client
            self.calls = calls
        }
    }

    /// The name given to calls whose peer could not be identified.
    ///
    /// A real category rather than a bucket for leftovers: ``LibProcPeerResolver`` returns an empty
    /// identity whenever the process has gone or the socket cannot be read, and the reference
    /// records the call anyway. Folding those into some named caller would attribute them; dropping
    /// them would make the bars stop summing to the headline.
    public static let unattributed = "unattributed"

    public let windowStartMilliseconds: Double
    public let totalCalls: Int
    public let failedCalls: Int
    /// Callers in descending call order, ties broken by name so two runs agree.
    public let callers: [Caller]
    /// Exactly `windowHours` buckets, oldest first, including the empty ones.
    public let hours: [Hour]
    /// The oldest record inside the window, or nil when the window holds none.
    public let horizon: String?
    /// Lines the reader could not use, and why they are reported rather than dropped silently: a
    /// count of what parsed is not a count of what was there, which is the whole subject of
    /// `planning/reader-accounting.py`.
    public let unreadableLines: Int

    /// Fold a log into the window ending at `nowMilliseconds`.
    ///
    /// - Parameter lines: the log's lines in the order they were written. A torn last line is
    ///   normal after a hard kill and is counted, never fatal.
    public static func over(
        lines: some Sequence<String>,
        nowMilliseconds: Double,
        windowHours: Int
    ) -> UsageInsights {
        var window = Window(nowMilliseconds: nowMilliseconds, windowHours: windowHours)
        for line in lines where !line.isEmpty {
            window.absorb(line)
        }
        return window.reading()
    }

    /// The fold's mutable state, so the loop above is one line and each rule below is separable.
    ///
    /// A type rather than seven `var`s in a function: the rules — which records are in the window,
    /// which hour a record belongs to, which caller it counts toward, and what "could not read it"
    /// means — are the substance here, and a single function carrying all of them sat at
    /// cyclomatic complexity 11 against this repository's cap of 10.
    private struct Window {
        let windowStart: Double
        let windowStartText: String
        var bucketKeys: [String] = []
        var bucketStarts: [Double] = []
        var bucketCounts: [Int] = []
        var callerNames: [String] = []
        var callerCounts: [Int] = []
        var total = 0
        var failed = 0
        var horizon: String?
        var unreadable = 0

        init(nowMilliseconds: Double, windowHours: Int) {
            // The window starts at the top of the hour `windowHours - 1` back, so the last bucket
            // is the hour in progress and every bucket is a whole hour. A window starting at "now
            // minus 24h" to the millisecond makes the first and last buckets partial, and a chart
            // whose end columns are short for arithmetic reasons reads as a fall in traffic.
            let hour = 3_600_000.0
            let currentHourStart = (nowMilliseconds / hour).rounded(.down) * hour
            windowStart = currentHourStart - Double(max(0, windowHours - 1)) * hour
            windowStartText = JSDate.iso8601(milliseconds: windowStart)
            for index in 0 ..< max(0, windowHours) {
                let start = windowStart + Double(index) * hour
                bucketStarts.append(start)
                bucketKeys.append(UsageInsights.hourKey(JSDate.iso8601(milliseconds: start)) ?? "")
                bucketCounts.append(0)
            }
        }

        /// One log line. Anything this cannot place is **counted** rather than bucketed somewhere
        /// plausible: a count of what parsed is not a count of what was there.
        mutating func absorb(_ line: String) {
            guard let parsed = try? JSONParser.parse(line), let record = UsageRecord(parsed),
                  let key = UsageInsights.hourKey(record.ts)
            else {
                unreadable += 1
                return
            }
            guard record.ts >= windowStartText else { return }

            total += 1
            if !record.ok { failed += 1 }
            if let seen = horizon {
                if record.ts < seen { horizon = record.ts }
            } else {
                horizon = record.ts
            }
            if let bucket = bucketKeys.firstIndex(of: key) { bucketCounts[bucket] += 1 }
            count(caller: record.client.flatMap { $0.isEmpty ? nil : $0 } ?? unattributed)
        }

        private mutating func count(caller: String) {
            if let index = callerNames.firstIndex(of: caller) {
                callerCounts[index] += 1
            } else {
                callerNames.append(caller)
                callerCounts.append(1)
            }
        }

        func reading() -> UsageInsights {
            var callers: [Caller] = []
            for (index, name) in callerNames.enumerated() {
                callers.append(Caller(client: name, calls: callerCounts[index]))
            }
            callers.sort { left, right in
                left.calls == right.calls ? left.client < right.client : left.calls > right.calls
            }
            var hours: [Hour] = []
            for (index, start) in bucketStarts.enumerated() {
                hours.append(Hour(startMilliseconds: start, calls: bucketCounts[index]))
            }
            return UsageInsights(
                windowStartMilliseconds: windowStart,
                totalCalls: total,
                failedCalls: failed,
                callers: callers,
                hours: hours,
                horizon: horizon,
                unreadableLines: unreadable
            )
        }
    }

    /// `YYYY-MM-DDTHH` — the hour a fixed-width UTC ISO timestamp names.
    ///
    /// Nil for anything that is not that shape, which is what stops a stray format being bucketed
    /// by its first thirteen characters wherever they happen to land.
    static func hourKey(_ timestamp: String) -> String? {
        guard timestamp.count >= 13 else { return nil }
        let key = String(timestamp.prefix(13))
        let digits = Array(key)
        guard digits.count == 13,
              digits[4] == "-", digits[7] == "-", digits[10] == "T",
              digits[0].isNumber, digits[1].isNumber, digits[2].isNumber, digits[3].isNumber,
              digits[5].isNumber, digits[6].isNumber, digits[8].isNumber, digits[9].isNumber,
              digits[11].isNumber, digits[12].isNumber
        else { return nil }
        return key
    }
}
