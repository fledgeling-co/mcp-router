import Foundation

/// The three buckets, and the derivation that produces them.
///
/// **`undecided` is derived, not fetched.** There is no feed: `/registry/search` takes `q` and
/// `limit` and nothing else — no `since`, no cursor, and no per-user seen-state anywhere in this
/// product. So "undecided" cannot mean "new since you last looked"; it means *of the results in
/// front of you, the ones you have not acted on*, which is computable from three sets the app
/// already holds. The prototype's empty-state copy ("you have been through everything new since
/// Tuesday") asserts the recency this type is unable to observe, and the copy does not repeat it.
public enum TriageBucket: String, Sendable, Equatable, CaseIterable, Identifiable {
    case undecided
    case queued
    case dismissed

    public var id: String { rawValue }

    public var copyKey: TriageCopy.Key {
        switch self {
        case .undecided: .control(.bucketUndecided)
        case .queued: .control(.bucketQueued)
        case .dismissed: .control(.bucketDismissed)
        }
    }

    /// Only Undecided offers a batch act, so only Undecided draws checkboxes. The other two carry
    /// the entry's tile in the row's leading slot instead, which keeps the row's shape while
    /// removing an affordance that would do nothing.
    public var isSelectable: Bool { self == .undecided }
}

/// The resolved contents of all three buckets.
public struct TriageBuckets: Sendable, Equatable {
    public let undecided: [RegistryEntry]
    public let queued: [RegistryEntry]
    public let dismissed: [RegistryEntry]

    public init(
        undecided: [RegistryEntry],
        queued: [RegistryEntry],
        dismissed: [RegistryEntry]
    ) {
        self.undecided = undecided
        self.queued = queued
        self.dismissed = dismissed
    }

    public func entries(in bucket: TriageBucket) -> [RegistryEntry] {
        switch bucket {
        case .undecided: undecided
        case .queued: queued
        case .dismissed: dismissed
        }
    }

    /// The count a segment carries.
    ///
    /// Every one of these is the size of a set the user's own decisions produced, which is the only
    /// reason a number is permitted on this surface at all: it is observed, by definition, because
    /// the observation is the user's own act.
    public func count(in bucket: TriageBucket) -> Int {
        entries(in: bucket).count
    }

    /// `undecided = results − queued − dismissed`.
    ///
    /// **`installed` is deliberately not a filter.** The router computes it as
    /// `installed.has(r.displayName)` against locally declared server keys — a display-name
    /// collision test, not an identity match, so it both false-positives (a local `github` marks
    /// every entry whose last path segment is `github`) and misses on case. Hiding a row on that
    /// heuristic would silently remove things the user could legitimately want, and silence is the
    /// worst available outcome for a wrong guess. The row is shown; the honest line is what I2's
    /// Discover renders about it.
    public static func resolve(
        results: [RegistryEntry],
        queuedIDs: Set<String>,
        dismissedIDs: Set<String>
    ) -> TriageBuckets {
        var undecided: [RegistryEntry] = []
        var queued: [RegistryEntry] = []
        var dismissed: [RegistryEntry] = []

        for entry in results {
            // Order matters and is stated: a queued entry that was also dismissed reads as queued,
            // because queueing is the later and more consequential act — it put something in front
            // of a human on another machine.
            if queuedIDs.contains(entry.id) {
                queued.append(entry)
            } else if dismissedIDs.contains(entry.id) {
                dismissed.append(entry)
            } else {
                undecided.append(entry)
            }
        }

        return TriageBuckets(undecided: undecided, queued: queued, dismissed: dismissed)
    }
}
