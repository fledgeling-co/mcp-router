import Foundation

/// The resolved-identity cache — B70.
///
/// Ported from the reference's `byPid` map, including the part that looks like a bug and is not:
///
/// ```js
/// this.byPid.set(pid, identity);
/// if (this.byPid.size > 512) this.byPid.clear();
/// ```
///
/// The bound is checked **after** the insert and the map is cleared **wholesale**, so the 513th
/// distinct pid empties the cache rather than evicting the oldest entry. An LRU here would be a
/// better cache and a *different* one, and the whole point of this layer is that the Swift router
/// answers identically to the TypeScript one. The reference's own comment explains why it is
/// content with this: "a pid is reused eventually, but not within one router lifetime in any
/// realistic case, and the cost of being wrong is a mislabelled log line."
///
/// A class rather than a struct because the resolver is a value type whose `identity(peerPort:)`
/// is non-mutating; the cache is the one piece of state that outlives a call.
public final class AttributionCache: @unchecked Sendable {
    /// The reference's literal. Cleared when the count goes *above* this, so at most this many
    /// entries are ever held.
    public static let bound = 512

    private let lock = NSLock()
    private var byPid: [Int32: ClientIdentity] = [:]

    public init() {}

    public func identity(for pid: Int32) -> ClientIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return byPid[pid]
    }

    public func store(_ identity: ClientIdentity, for pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        byPid[pid] = identity
        if byPid.count > Self.bound { byPid.removeAll() }
    }

    /// Exposed for the boundary test — B70 is a claim about the count, and a claim about a count
    /// that nothing can read is not testable.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return byPid.count
    }

    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return byPid.isEmpty
    }
}
