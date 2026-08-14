import Foundation

/// A Mac this phone is paired with.
///
/// `lastSeen` is **optional, and that optionality is a designed state rather than a convenience**:
/// a Mac that is reachable but has not reported since the app opened has no last-seen instant, and
/// the Partial state exists to say "unknown" instead of inventing a plausible one. Making this
/// non-optional with a default would delete that state and replace it with a fabricated timestamp,
/// which is exactly what `DESIGN.md` §6 forbids.
public struct PairedMac: Sendable, Equatable, Codable, Identifiable {
    public var id: String { fingerprint }

    public let name: String
    public let pairedAt: Date
    public let lastSeen: Date?

    /// Where the Mac is reached, and how it is identified. Stored for the transport M6 brings.
    /// **Never rendered and never logged** — none of the three tells the user anything they can act
    /// on, and together they are most of what an attacker would want.
    public let host: String
    public let port: Int
    public let fingerprint: String

    public init(
        name: String,
        pairedAt: Date,
        lastSeen: Date?,
        host: String,
        port: Int,
        fingerprint: String
    ) {
        self.name = name
        self.pairedAt = pairedAt
        self.lastSeen = lastSeen
        self.host = host
        self.port = port
        self.fingerprint = fingerprint
    }
}

/// How the code being submitted was obtained.
///
/// The honesty rule (`DESIGN.md` §6) turns on this distinction, so it is carried in the type. A
/// boolean `didScan` alongside an optional expiry would let the two disagree — an expiry present
/// with the flag false, and a countdown rendered for a number nobody observed. Here the expiry only
/// exists inside `.scanned`, so the invalid combination cannot be constructed.
public enum PairingAttempt: Sendable, Equatable {
    case scanned(PairingPayload)
    case typed(PairingCode)

    public var code: PairingCode {
        switch self {
        case let .scanned(payload): payload.code
        case let .typed(code): code
        }
    }

    /// The expiry, when there is an observed one. `nil` for a typed code — the phone has not spoken
    /// to the Mac yet and so has observed nothing.
    public var observedExpiry: Date? {
        switch self {
        case let .scanned(payload): payload.expiresAt
        case .typed: nil
        }
    }

    /// The Mac's name, when the payload carried it. Typed entry does not know it yet.
    public var macName: String? {
        switch self {
        case let .scanned(payload): payload.macName
        case .typed: nil
        }
    }
}

/// Every way a pairing attempt ends.
///
/// Nine cases, not one. A user told "pairing failed" retries the thing that cannot work — and
/// `versionMismatch` and `alreadyUsed` are both unfixable by retrying, so the recovery each needs
/// is different in kind, not just in wording.
public enum PairingOutcome: Sendable, Equatable {
    case paired(PairedMac)

    /// The Mac does not know this code.
    case notRecognised
    /// The code was real and its window has closed. The Mac is already showing the next one.
    case expired
    /// Each code pairs one device once, and this one has been spent.
    case alreadyUsed
    /// The Mac speaks a pairing version this build does not.
    case versionMismatch(macName: String?)
    /// Nothing answered. Asleep, elsewhere on the network, or not running — indistinguishable
    /// from here, so the copy names all three rather than guessing one.
    case unreachable(macName: String?)
    /// Someone dismissed the request at the Mac. A decision, not an error.
    case refused(macName: String?)

    /// The scanned text was not one of ours.
    case notAPairingCode
    /// Ours, but unreadable.
    case malformedPayload

    public var isSuccess: Bool {
        if case .paired = self { return true }
        return false
    }
}

/// Whether anything this phone sends will arrive.
///
/// Three cases and no fourth. "Paired but we have not checked yet" is not a connection state — it is
/// the Loading state of the surface asking, and folding it in here would let a surface render
/// "can't reach it" for a Mac nobody has tried.
public enum ConnectionState: String, Sendable, Equatable, CaseIterable {
    /// The Mac answered. Items sent now arrive now.
    case reachable
    /// Paired, and nothing answered. Queued work waits and sends itself when it returns.
    case notReachable
    /// No Mac is paired at all.
    case neverPaired

    /// Whether a surface that sends may commit right now.
    public var canSend: Bool { self == .reachable }
}

/// The nine states of the paired-Mac surface, as one value a test can construct.
///
/// Driving the surface from an enum rather than from a scatter of optionals is what makes
/// `DESIGN.md` §5 checkable: a test enumerates the cases, renders each, and a tenth state added
/// without copy fails to compile rather than shipping blank.
public enum PairedMacSurfaceState: Sendable, Equatable {
    /// Populated and reachable.
    case reachable(PairedMac)
    /// No Mac has ever been paired here — and, per A23, also what a *missing* Keychain item means.
    case neverPaired
    /// Reading the stored pairing.
    case loading
    /// Reachable, but the Mac has not reported since the app opened, so `lastSeen` is unknown.
    case partial(PairedMac)
    /// The stored pairing was present and could not be read. Reached only from an observed failure.
    case unreadable
    /// Just paired, in place, no toast.
    case justPaired(PairedMac)
    /// Paired and nothing answered.
    case macUnreachable(PairedMac)

    /// The Mac this state is about, where it has one.
    public var mac: PairedMac? {
        switch self {
        case let .reachable(mac), let .partial(mac), let .justPaired(mac), let .macUnreachable(mac):
            mac
        case .neverPaired, .loading, .unreadable:
            nil
        }
    }

    /// The connection vocabulary this state speaks, which is the same vocabulary every sending
    /// surface uses.
    public var connection: ConnectionState {
        switch self {
        case .reachable, .partial, .justPaired: .reachable
        case .macUnreachable: .notReachable
        case .neverPaired, .unreadable: .neverPaired
        case .loading: .neverPaired
        }
    }
}
