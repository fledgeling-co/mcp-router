// The four identities the pool's races turn on.
//
// One generation counter is not enough, and the plan gate showed exactly why: a single counter
// cannot tell a start attempt from a handle from a timer from a lease, so a duplicate `release()`
// decrements twice and a retried start inherits its predecessor's identity. Each concern gets its
// own monotonic id, and each id exists because there is a test that fails without it.
//
// They are distinct types rather than four `UInt64`s so they cannot be transposed at a call site —
// comparing a handle id against a reap epoch would otherwise compile and be silently wrong.

/// One attempt to open an upstream. Bumped per attempt, **including a retry after a failure**, so a
/// late-completing attempt can tell it has been superseded.
public struct StartAttemptID: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let value: UInt64
    public init(_ value: UInt64) {
        self.value = value
    }

    public static func < (a: Self, b: Self) -> Bool {
        a.value < b.value
    }

    public var description: String { "start#\(value)" }
}

/// One installed handle. Bumped per successful install, so a close event or a lease release from a
/// previous incarnation cannot act on its replacement.
public struct HandleID: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let value: UInt64
    public init(_ value: UInt64) {
        self.value = value
    }

    public static func < (a: Self, b: Self) -> Bool {
        a.value < b.value
    }

    public var description: String { "handle#\(value)" }
}

/// One arming of the idle timer.
///
/// Swift task cancellation is cooperative, not `clearTimeout`: a cancelled sleeping task can still
/// wake and run. The epoch is what lets the woken task discover that the deadline it was sleeping
/// against is no longer the current one.
public struct ReapEpoch: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let value: UInt64
    public init(_ value: UInt64) {
        self.value = value
    }

    public static func < (a: Self, b: Self) -> Bool {
        a.value < b.value
    }

    public var description: String { "epoch#\(value)" }
}

/// One lease on an upstream. Tracked in a set so release is **exactly once** — a duplicated or
/// copied release would otherwise decrement the in-flight count twice and let the reaper close an
/// upstream that still has work outstanding.
public struct LeaseID: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let value: UInt64
    public init(_ value: UInt64) {
        self.value = value
    }

    public static func < (a: Self, b: Self) -> Bool {
        a.value < b.value
    }

    public var description: String { "lease#\(value)" }
}

/// A monotonic source for the four ids. Actor-isolated by its owner; never shared.
struct IdentitySequence {
    private var next: UInt64 = 1

    mutating func take() -> UInt64 {
        defer { next &+= 1 }
        return next
    }
}
