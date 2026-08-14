import Foundation

/// The window of call records the Activity board holds, and the groupings it derives from them.
///
/// **Everything here is derived from records the router actually returned.** `DESIGN.md` §6 forbids
/// displaying a number the router does not observe, and the way that rule gets broken on a log
/// surface is not by inventing a metric — it is by offering a filter option, or a count beside one,
/// that no loaded record supports. So the options *are* the grouping: an option cannot exist
/// without at least one record in it, because it is constructed by grouping the records.
public struct ActivityRecords: Equatable, Sendable {
    /// How many records are kept.
    ///
    /// The router's own ring is 500 (`RING_SIZE` in `src/usage.ts`) and `GET /usage` slices its
    /// tail, so asking for more returns no more. Matching it exactly means the backfill is the whole
    /// of what the router has, and the live stream can top the list up to the same bound rather than
    /// growing without limit — an unbounded list behind a feed that never stops is a leak with a
    /// slow fuse.
    public static let capacity = 500

    /// Newest first, which is the order `recent()` returns (`.slice(-limit).reverse()`) and the only
    /// order in which "a new call appears at the top" is true.
    public private(set) var records: [CallRecord]

    /// When the router's counter was last reset. Displayed, never computed from.
    ///
    /// **Optional, because it is a fact the router states and not one this window can supply.** A
    /// record can arrive on the stream before the backfill returns — `start()` runs both halves
    /// concurrently, so on a busy router that is ordinary rather than exotic — and the window has to
    /// hold it. Seeding this from that record's own `ts` would put a number in the slot meaning "the
    /// counting window opened at", which only `UsageResponse.since` can answer: the window opened
    /// earlier, and how much earlier is exactly what is not yet known. `nil` until a response says,
    /// and the subtitle drops the clause rather than inventing it.
    public let since: String?

    /// Ids already held, so the de-duplication in `prepending` is a set lookup rather than a scan
    /// of five hundred records on every arriving event.
    private var ids: Set<String>

    public init(records: [CallRecord], since: String?) {
        var seen = Set<String>()
        var kept: [CallRecord] = []
        kept.reserveCapacity(min(records.count, Self.capacity))
        for record in records where !seen.contains(record.id) {
            guard kept.count < Self.capacity else { break }
            seen.insert(record.id)
            kept.append(record)
        }
        self.records = kept
        self.since = since
        ids = seen
    }

    public init(_ response: UsageResponse) {
        self.init(records: response.records, since: response.since)
    }

    public var isEmpty: Bool { records.isEmpty }
    public var count: Int { records.count }

    /// A record arriving on the live stream.
    ///
    /// Returns whether anything changed, so a caller can skip an animation for an event that was
    /// already on screen. A record the backfill already carried is dropped rather than prepended:
    /// the stream and the backfill overlap by construction — the stream is subscribed after the
    /// fetch, and a call made in between arrives on both — and a log that shows the same call twice
    /// is a log nobody can count from.
    @discardableResult
    public mutating func prepend(_ record: CallRecord) -> Bool {
        guard !ids.contains(record.id) else { return false }
        ids.insert(record.id)
        records.insert(record, at: 0)
        while records.count > Self.capacity, let dropped = records.popLast() {
            ids.remove(dropped.id)
        }
        return true
    }

    // MARK: - The groupings the filters are built from

    /// The sessions present in the loaded records, most calls first.
    public func sessions() -> [ActivityOption<SessionKey>] {
        group { SessionKey(record: $0) }
    }

    /// The working directories present in the loaded records, most calls first.
    public func directories() -> [ActivityOption<DirectoryKey>] {
        group { DirectoryKey(record: $0) }
    }

    /// Groups the loaded records by a key and counts each group.
    ///
    /// Ordered by count descending and then by label, rather than by first appearance: a menu whose
    /// order changes every time a call arrives is a menu you cannot learn, and the count is the
    /// thing a reader is choosing on.
    private func group<Key: ActivityFilterKey>(
        by key: (CallRecord) -> Key
    ) -> [ActivityOption<Key>] {
        var counts: [Key: Int] = [:]
        var exemplars: [Key: CallRecord] = [:]
        for record in records {
            let k = key(record)
            counts[k, default: 0] += 1
            // The first record in a group names it. The identity is the pid or the directory; the
            // label is whatever that record happened to carry, which is display only.
            if exemplars[k] == nil { exemplars[k] = record }
        }
        return counts
            .map { entry in
                ActivityOption(
                    key: entry.key,
                    calls: entry.value,
                    label: exemplars[entry.key].map { entry.key.displayLabel(from: $0) }
                        ?? entry.key.label
                )
            }
            .sorted {
                $0.calls == $1.calls ? $0.label < $1.label : $0.calls > $1.calls
            }
    }
}

/// One choice in a filter menu, with the number of loaded calls behind it.
public struct ActivityOption<Key: ActivityFilterKey>: Equatable, Sendable, Identifiable {
    public let key: Key
    public let calls: Int
    /// What the menu shows. Resolved from a record in the group rather than from the key, because
    /// the key is identity and the name is not.
    public let label: String

    public var id: Key { key }

    public init(key: Key, calls: Int, label: String) {
        self.key = key
        self.calls = calls
        self.label = label
    }
}

/// Names shared by every surface that renders a call record.
public enum ActivityNaming {
    /// What a record the router could not attribute is called, everywhere it is called anything.
    ///
    /// One name per state across both surfaces (`DESIGN.md` §6): the filter menu, the inspector and
    /// the accessibility label all read this, so none of them can say it differently.
    public static let unattributed = "Unattributed"
}

/// What a filter menu's rows have in common.
public protocol ActivityFilterKey: Hashable, Sendable {
    /// The fallback label, for when no record of this group is to hand.
    var label: String { get }
    /// The label a menu shows, given a record that belongs to this key.
    func displayLabel(from record: CallRecord) -> String
    /// Whether one record belongs to this key.
    func matches(_ record: CallRecord) -> Bool
}

/// Which agent session a call came from.
///
/// An enum rather than `Int?` on purpose. With an optional, "no pid" and "no filter" are the same
/// value, and a call site that forgets the difference silently turns *show me the unattributed
/// calls* into *show me everything*. The router omits `pid` whenever `lsof` could not name the
/// caller — `ClientResolver` returns an empty identity on every failure path, deliberately, because
/// an unattributed record is worth far more than a dropped one — so this is a real group with real
/// records in it, not an error case.
public enum SessionKey: ActivityFilterKey {
    /// **The pid alone.** The client name is display, not identity: the router resolves it once per
    /// connection and legitimately reports it for one call and not the next, so carrying it in the
    /// hashable payload split a single session into two menu entries with two half-counts — and the
    /// same equality drives the filter-fallback, so one of the two could never be cleared. D2 always
    /// said the match was on `pid`; this makes the type say it too.
    case attributed(pid: Int)
    case unattributed

    public init(record: CallRecord) {
        guard let pid = record.pid else { self = .unattributed; return }
        self = .attributed(pid: pid)
    }

    /// The fallback label, used when no record is to hand. The menu prefers `displayLabel(from:)`,
    /// which can name the client.
    public var label: String {
        switch self {
        case let .attributed(pid): "pid \(pid)"
        case .unattributed: ActivityNaming.unattributed
        }
    }

    /// The label as a menu shows it, given one record that belongs to this key.
    public func displayLabel(from record: CallRecord) -> String {
        switch self {
        case let .attributed(pid):
            guard let client = record.client, !client.isEmpty else { return "pid \(pid)" }
            return "\(client) · pid \(pid)"
        case .unattributed:
            return ActivityNaming.unattributed
        }
    }

    public func matches(_ record: CallRecord) -> Bool {
        switch self {
        case let .attributed(pid): record.pid == pid
        case .unattributed: record.pid == nil
        }
    }
}

/// Which working directory a call came from — the per-project ledger, as the router keeps it.
public enum DirectoryKey: ActivityFilterKey {
    /// The working directory alone, for the same reason `SessionKey` carries only the pid: the
    /// router's `project` is a convenience it may or may not send, and a directory that arrived once
    /// with a project name and once without would otherwise be two entries.
    case path(cwd: String)
    case unattributed

    public init(record: CallRecord) {
        guard let cwd = record.cwd, !cwd.isEmpty else { self = .unattributed; return }
        self = .path(cwd: cwd)
    }

    /// The label as a menu shows it, given one record that belongs to this key.
    public func displayLabel(from record: CallRecord) -> String {
        switch self {
        case .path: projectLabel(cwd: record.cwd, project: record.project)
        case .unattributed: ActivityNaming.unattributed
        }
    }

    /// The name people recognise, which is what the row shows. The full path is never lost — the
    /// inspector carries it, and `cwd` is what the match is made on.
    public var label: String {
        switch self {
        case let .path(cwd): projectLabel(cwd: cwd, project: nil)
        case .unattributed: ActivityNaming.unattributed
        }
    }

    public func matches(_ record: CallRecord) -> Bool {
        switch self {
        case let .path(cwd): record.cwd == cwd
        case .unattributed: record.cwd == nil || record.cwd?.isEmpty == true
        }
    }
}
