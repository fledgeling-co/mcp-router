import Foundation

/// One capability the user has sent to their Mac for review.
///
/// **The phone queues; it never installs** (`DESIGN.md` §9). Pairing grants a remote party the
/// ability to put executable code on a laptop, so this phone's commit writes an item to a local
/// queue that the Mac reads and a human reviews. That narrowing is the product's, not this
/// feature's, and every surface reflects it.
///
/// `install` is carried so Triage can show what is being reviewed — the transport, the host, the
/// declared credential — without re-searching. It is **data at rest for a person to read**. Nothing
/// on this phone executes it, nothing on this phone can, and the control API's `command`, `args`
/// and `env` are not writable at any point in this product.
public struct QueuedCapability: Codable, Sendable, Equatable, Identifiable {
    /// `RegistryEntry.id`, and the idempotency key. Queueing the same entry twice must not produce
    /// two rows for the reviewer to reconcile.
    public let id: String
    public let displayName: String
    public let source: RegistryEntry.Source
    public let install: RegistryInstall?
    public let queuedAt: Date

    public init(
        id: String,
        displayName: String,
        source: RegistryEntry.Source,
        install: RegistryInstall?,
        queuedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.install = install
        self.queuedAt = queuedAt
    }

    public init(entry: RegistryEntry, queuedAt: Date = Date()) {
        self.init(
            id: entry.id,
            displayName: entry.displayName,
            source: entry.source,
            install: entry.install,
            queuedAt: queuedAt
        )
    }
}

/// What can go wrong writing the queue.
public enum CapabilityQueueError: Error, Sendable, Equatable {
    /// The queue file exists and could not be read as a queue. **Not** treated as an empty queue:
    /// a decode path whose failure mode is emptiness is the exact defect `SWIFT_PRACTICES.md` §2
    /// records from this repo's own TypeScript router, where a flat `servers.json` loaded zero
    /// servers with no error at all.
    case unreadable(String)
    /// The write was refused. Surfaced as a failure, never swallowed.
    case writeFailed(String)
}

/// The write half of the capability queue.
///
/// **I2 defines only this port and the item type; I3 owns the reader and the storage format.** The
/// brief makes the commit this feature's deliverable, so a commit that commits nothing would be a
/// placeholder wearing a button. Checked before writing this: no queue type existed anywhere in
/// the tree, so there is nothing to collide with — and this seam is reported for I3 to adopt rather
/// than assumed.
public protocol CapabilityQueueWriter: Sendable {
    /// Add an item. Idempotent on `id`.
    func enqueue(_ item: QueuedCapability) async throws
    /// Whether an entry is already queued, which is what the commit's queued states key on.
    func contains(_ id: String) async throws -> Bool
}

/// The shipped writer: a JSON file in the app's Application Support directory.
///
/// An `actor` because the queue is genuinely mutable shared state reached from a `@MainActor`
/// surface — the case `SWIFT_PRACTICES.md` §1 says to reach for an actor for, rather than as a way
/// to silence a diagnostic.
public actor FileCapabilityQueueWriter: CapabilityQueueWriter {
    private let url: URL
    private let fileManager: FileManager

    /// - Parameter directory: where the queue lives. Injected so tests write to a temporary
    ///   directory and a relaunch can be simulated by constructing a second writer over the same
    ///   one — which is what makes "survives an app relaunch" a test rather than a claim.
    public init(directory: URL, fileManager: FileManager = .default) {
        url = directory.appendingPathComponent("capability-queue.json")
        self.fileManager = fileManager
    }

    /// The app's own Application Support directory.
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

    public func enqueue(_ item: QueuedCapability) async throws {
        var items = try read()
        // Idempotent on id: re-queueing an entry keeps the original `queuedAt`, because the fact
        // the reviewer cares about is when it was first sent, and a second tap is not new
        // information.
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        try write(items)
    }

    public func contains(_ id: String) async throws -> Bool {
        try read().contains { $0.id == id }
    }

    // MARK: - Storage

    private func read() throws -> [QueuedCapability] {
        // A missing file is an empty queue, and that is the one case where emptiness is the honest
        // answer: nothing has been queued yet. A file that exists and will not decode is an error,
        // never an empty queue.
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CapabilityQueueError.unreadable(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode([QueuedCapability].self, from: data)
        } catch {
            throw CapabilityQueueError.unreadable(error.localizedDescription)
        }
    }

    private func write(_ items: [QueuedCapability]) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(items)
        } catch {
            throw CapabilityQueueError.writeFailed(error.localizedDescription)
        }
        do {
            // Atomic, so a queue is never left half-written by a phone that was backgrounded
            // mid-save.
            try data.write(to: url, options: .atomic)
        } catch {
            // The error propagates. I1's `PairingStorageFailureTests` records the precedent this
            // is written against: there, a `try?` made a refused Keychain write render as paired.
            // A refused write here must render as a failure and never as a queued item.
            throw CapabilityQueueError.writeFailed(error.localizedDescription)
        }
    }
}

/// An in-memory writer, for previews and for the host tests that have no container.
public actor InMemoryCapabilityQueue: CapabilityQueueWriter {
    private var items: [QueuedCapability] = []
    private let failure: CapabilityQueueError?

    /// - Parameter failure: when set, every `enqueue` throws it. This is how the refused-write
    ///   path is exercised, rather than by hoping a real filesystem refuses something.
    public init(failure: CapabilityQueueError? = nil) {
        self.failure = failure
    }

    public func enqueue(_ item: QueuedCapability) async throws {
        if let failure { throw failure }
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
    }

    public func contains(_ id: String) async throws -> Bool {
        if let failure { throw failure }
        return items.contains { $0.id == id }
    }

    public func all() -> [QueuedCapability] {
        items
    }
}
