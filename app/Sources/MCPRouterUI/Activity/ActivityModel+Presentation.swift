#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// What the board *shows*, as against what the model *knows*.
    ///
    /// The subtitle, the clock formatting and the one derived value on the surface — the age — live
    /// here rather than beside the load and subscribe logic. They are the part of the model most
    /// likely to be read by someone checking a claim about what the router observes, and they are
    /// worth finding in one place.
    public extension ActivityModel {
        /// The board's subtitle, or nil where nothing has been observed to say.
        func subtitle() -> String? {
            guard let records else { return nil }
            return ActivityCopy.subtitle(
                count: records.count,
                since: displaySince(records.since),
                feed: ActivityCopy.feedLabel(phase)
            )
        }

        /// `since` as a clock time, or the raw value when it is not a timestamp this version parses.
        ///
        /// Falling back to the raw string rather than to a placeholder: the router sent something,
        /// and showing it unparsed is honest where showing "—" would discard a fact.
        ///
        /// `nil` in, `nil` out, and that case is real: a window seeded by a record that arrived on
        /// the stream before the first backfill returned has no `since`, because the router has not
        /// said when its counting window opened and the record's own `ts` is not that answer. The
        /// callers omit the clause rather than inventing one.
        func displaySince(_ raw: String?) -> String? {
            guard let raw else { return nil }
            guard let date = raw.asControlAPIDate else { return raw }
            return Self.timeOfDay.string(from: date)
        }

        /// Internal, not public: it was `private` inside the class before this file existed, and a
        /// `public extension` would otherwise export a formatter as API for no caller that wants it.
        internal static let timeOfDay: DateFormatter = {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("jmm")
            return formatter
        }()

        /// The relative age of one record, at this instant.
        ///
        /// A **derived** value, and the one derivation on this surface: the router sends an absolute
        /// `ts` and this subtracts it from the device clock, which is not the router's clock. It is
        /// derived rather than fabricated — nothing is invented, one observed value is re-expressed
        /// — and the absolute timestamp is in the inspector so the raw fact is never out of reach. A
        /// `ts` in the future (a clock skew, not a fault) reads as "now" rather than as a negative
        /// age, because `shortAgo` floors the interval at zero.
        func age(of record: CallRecord) -> String {
            guard let date = record.ts.asControlAPIDate else { return "—" }
            return shortAgo(date, from: clock())
        }

        /// The newest loaded record's time of day, for the feed states.
        ///
        /// Named in the copy as *the newest call here* and never as a completeness watermark: the
        /// wire carries no watermark, so a record's timestamp proves one arrived and never that
        /// none was missed.
        var newestTimestamp: String? {
            guard let ts = records?.records.first?.ts, let date = ts.asControlAPIDate else {
                return nil
            }
            return Self.timeOfDay.string(from: date)
        }
    }
#endif
