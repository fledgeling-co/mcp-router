import Foundation

/// One capability the user has decided is not for them.
///
/// **This is the record the rejected swipe deck could not keep.** A gesture that dismisses an item
/// and forgets it makes a decision taken badly on a train unrecoverable at the desk; a decision with
/// a home is revisitable and reversible, which is the whole argument for the bucket. So the
/// dismissal is persisted with the same care the queue is, and for the same reason: it is state the
/// user produced, and losing it silently is worse than never offering the act.
///
/// The coordinate and when, and nothing else. There is deliberately **no reason field**: the product
/// never asks for one, and a nullable reason nobody supplies is a column that makes the file look
/// richer than the decision was.
public struct DismissedCapability: Codable, Sendable, Equatable, Identifiable {
    /// `RegistryEntry.id`, and the idempotency key — dismissing twice must not produce two rows.
    public let id: String
    /// What the row said when the user turned it down. Rendered in the bucket so the row is
    /// readable without a second registry search, which may return a different page.
    public let displayName: String
    public let dismissedAt: Date

    public init(id: String, displayName: String, dismissedAt: Date) {
        self.id = id
        self.displayName = displayName
        self.dismissedAt = dismissedAt
    }

    public init(entry: RegistryEntry, dismissedAt: Date = Date()) {
        self.init(id: entry.id, displayName: entry.displayName, dismissedAt: dismissedAt)
    }
}

/// What can go wrong reading or writing the dismissal set.
///
/// **Mirrors `CapabilityQueueError` case for case, deliberately.** The two persisted sets on this
/// phone fail the same way or they drift, and the failure that matters is the same one in both:
/// `Undecided = results − queued − dismissed`, so a dismissal file that will not decode silently
/// re-populates Undecided with everything the user already turned down. That is the
/// failure-mode-is-emptiness defect `SWIFT_PRACTICES.md` §2 records from this repo's own TypeScript
/// router, where a flat `servers.json` loaded zero servers with no error at all — and it is exactly
/// as available here as it is on the queue.
public enum DismissalStoreError: Error, Sendable, Equatable {
    /// The file exists and could not be read as a dismissal set. **Never treated as an empty set.**
    case unreadable(String)
    /// The write was refused. Surfaced as a failure, never swallowed.
    case writeFailed(String)
}

/// The dismissal set's port.
public protocol DismissalStore: Sendable {
    /// Everything the user has turned down. Throws rather than returning `[]` on a corrupt file.
    func all() async throws -> [DismissedCapability]
    /// Turn something down. Idempotent on `id`.
    func dismiss(_ item: DismissedCapability) async throws
    /// Put it back in Undecided.
    func restore(_ id: String) async throws
}

/// The shipped store: a JSON file beside the queue in Application Support.
///
/// A **second file** rather than a second array in the queue's document. `capability-queue.json` is
/// a `[QueuedCapability]` array that I2 shipped and that a Mac may one day read; widening that
/// document to carry an unrelated set would break its format for a convenience this store does not
/// need.
///
/// An `actor` for the reason `SWIFT_PRACTICES.md` §1 gives — genuinely mutable shared state reached
/// from a `@MainActor` surface — not as a way to silence a diagnostic.
public actor FileDismissalStore: DismissalStore {
    private let url: URL
    private let fileManager: FileManager

    /// - Parameter directory: where the file lives. Injected so tests write to a temporary directory
    ///   and a relaunch is simulated by constructing a second store over the same one, which is what
    ///   makes "a dismissal survives a relaunch" a test rather than a claim.
    public init(directory: URL, fileManager: FileManager = .default) {
        url = directory.appendingPathComponent("dismissed-capabilities.json")
        self.fileManager = fileManager
    }

    /// The app's own Application Support directory — the same one the queue uses, so the two files
    /// live together and a future migration moves one directory rather than hunting two.
    public static func defaultDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    public func all() async throws -> [DismissedCapability] {
        try read()
    }

    public func dismiss(_ item: DismissedCapability) async throws {
        var items = try read()
        // Idempotent on id, and the ORIGINAL `dismissedAt` is kept: the fact worth recording is when
        // the user first turned it down, and a second dismissal is not new information.
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        try write(items)
    }

    public func restore(_ id: String) async throws {
        let items = try read()
        let remaining = items.filter { $0.id != id }
        // A restore of something not dismissed is a no-op rather than an error: the surface offers
        // the act only on rows that are dismissed, so a mismatch here means the set changed under
        // us, and failing would surface a fault the user cannot act on.
        guard remaining.count != items.count else { return }
        try write(remaining)
    }

    // MARK: - Storage

    private func read() throws -> [DismissedCapability] {
        // A missing file is an empty set, and that is the one case where emptiness is the honest
        // answer: nothing has been dismissed yet. A file that exists and will not decode is an
        // error, never an empty set.
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DismissalStoreError.unreadable(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode([DismissedCapability].self, from: data)
        } catch {
            throw DismissalStoreError.unreadable(error.localizedDescription)
        }
    }

    private func write(_ items: [DismissedCapability]) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(items)
        } catch {
            throw DismissalStoreError.writeFailed(error.localizedDescription)
        }
        do {
            // Atomic, so the set is never left half-written by a phone backgrounded mid-save.
            try data.write(to: url, options: .atomic)
        } catch {
            throw DismissalStoreError.writeFailed(error.localizedDescription)
        }
    }
}

/// An in-memory store, for previews and for the host tests that have no container.
public actor InMemoryDismissalStore: DismissalStore {
    private var items: [DismissedCapability]
    private let failure: DismissalStoreError?
    private let readFailure: DismissalStoreError?

    /// - Parameter failure: when set, every **write** throws it.
    /// - Parameter readFailure: when set, `all()` throws it — which is how the unreadable state is
    ///   driven.
    ///
    /// Two flags rather than one, matching `InMemoryCapabilityQueue` for the reason a merged test
    /// there made plain: a refused write and an unreadable file are different faults, and a double
    /// that conflates them cannot express "the write was refused and nothing was stored".
    public init(
        items: [DismissedCapability] = [],
        failure: DismissalStoreError? = nil,
        readFailure: DismissalStoreError? = nil
    ) {
        self.items = items
        self.failure = failure
        self.readFailure = readFailure
    }

    public func all() async throws -> [DismissedCapability] {
        if let readFailure { throw readFailure }
        return items
    }

    public func dismiss(_ item: DismissedCapability) async throws {
        if let failure { throw failure }
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
    }

    public func restore(_ id: String) async throws {
        if let failure { throw failure }
        items.removeAll { $0.id == id }
    }
}
