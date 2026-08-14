import Foundation

/// Which of the loaded records are showing, and what is therefore hidden.
///
/// **The filters run over records already in memory, and never as query parameters.** `GET /usage`
/// does accept `server` and `cwd`, but `GET /usage/stream` accepts nothing — so a server-side
/// directory filter would give a board whose backfill was narrowed and whose live half was not, and
/// every arriving record for another directory would have to be discarded on the client anyway. One
/// predicate over one in-memory window means the two halves cannot disagree, a filter change costs
/// no request and shows no flicker, and there is exactly one definition of what is on screen.
///
/// Neither key is an optional of a primitive. `nil` here means "no filter", and the *absence* of
/// attribution is `SessionKey.unattributed` / `DirectoryKey.unattributed` — a value that matches the
/// records the router could not name rather than all of them.
public struct ActivityFilter: Equatable, Sendable {
    public var session: SessionKey?
    public var directory: DirectoryKey?

    public init(session: SessionKey? = nil, directory: DirectoryKey? = nil) {
        self.session = session
        self.directory = directory
    }

    public static let none = ActivityFilter()

    public var isActive: Bool { session != nil || directory != nil }

    public func matches(_ record: CallRecord) -> Bool {
        if let session, !session.matches(record) { return false }
        if let directory, !directory.matches(record) { return false }
        return true
    }

    public mutating func clear() {
        session = nil
        directory = nil
    }
}

/// What a filtered board is showing, and out of how many.
///
/// The total travels with the visible slice rather than being fetched from somewhere else, because
/// both numbers are rendered in one sentence — `9 of 28` — and reading them from two places is how
/// they come to disagree. Without that sentence a filter matching nothing looks exactly like a
/// router with nothing to say, which is the silent-empty failure this codebase forbids by name.
public struct ActivityResult: Equatable, Sendable {
    public let visible: [CallRecord]
    public let total: Int

    public init(visible: [CallRecord], total: Int) {
        self.visible = visible
        self.total = total
    }

    public var isFilteredToNothing: Bool { visible.isEmpty && total > 0 }
    public var hiddenCount: Int { total - visible.count }
}

public extension ActivityRecords {
    /// The records one filter admits, with the total they were drawn from.
    func applying(_ filter: ActivityFilter) -> ActivityResult {
        guard filter.isActive else {
            return ActivityResult(visible: records, total: records.count)
        }
        return ActivityResult(visible: records.filter(filter.matches), total: records.count)
    }
}
