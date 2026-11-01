import Foundation

/// Timestamp recency among returned registry entries. Cumulative usage is never sliced by this window.
public enum RegistryRecency {
    public static func rows(
        in entries: [RegistryEntry], window: RecencyWindow, now: Date = Date()
    ) -> [RegistryEntry] {
        let cutoff = window.days.map { days in
            now.addingTimeInterval(-Double(days) * 86400)
        }
        return entries
            .compactMap { entry -> (RegistryEntry, Date)? in
                guard let changed = DiscoverPresentation.date(from: entry.updatedAt) else {
                    // An unparseable stamp drops the entry from this band rather than sorting
                    // it to one end. It is still reachable from Most used and from search.
                    return nil
                }
                if let cutoff, changed < cutoff { return nil }
                return (entry, changed)
            }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 > rhs.1
            }
            .map(\.0)
    }
}
