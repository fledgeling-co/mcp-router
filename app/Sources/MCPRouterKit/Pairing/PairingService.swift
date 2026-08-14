import Foundation

/// The seam between the phone's pairing surfaces and the Mac that answers them.
///
/// **No live implementation ships in this item, and that is a decision rather than a gap.** M6 owns
/// the Mac endpoint and is unmerged; writing a network client now would mean inventing a wire M6
/// then has to match, and a contract invented by the consumer is one the producer discovers late.
/// What ships instead is this protocol plus a fixture covering every outcome — the same shape F3
/// used for the control client — so every surface, every failure and every recovery is built and
/// tested now, and M6 implements against something exact.
///
/// The payload contract itself is fixed in `PairingPayload` and in `planning/specs/spec-I1.md`.
public protocol PairingService: Sendable {
    /// Submit an attempt and find out how it ends.
    ///
    /// This does not `throw`. Every way pairing can end is a *designed outcome* with its own copy
    /// and its own recovery, so modelling six of them as errors and one as a return value would put
    /// the same decision in two places and invite a `catch` that flattens them back into one
    /// message — which is the failure `PairingOutcome` exists to prevent.
    func pair(using attempt: PairingAttempt) async -> PairingOutcome

    /// Whether the paired Mac is answering right now.
    func reachability(of mac: PairedMac) async -> ConnectionState
}

/// Every outcome, on demand, with no network and no Mac.
///
/// One scenario per `PairingOutcome` case. `PairingOutcomeCoverageTests` enumerates the outcomes
/// and asserts each is produced by some scenario, so a tenth outcome added later cannot quietly
/// ship with no way to see it.
public struct FixturePairingService: PairingService {
    public enum Scenario: String, Sendable, CaseIterable {
        case paired
        case notRecognised
        case expired
        case alreadyUsed
        case versionMismatch
        case unreachable
        case refused
        case notAPairingCode
        case malformedPayload

        /// Paired, but the Mac stops answering afterwards — the state the brief calls out by name.
        case pairedThenUnreachable
        /// Paired and answering, but it has not reported since the app opened: the Partial state.
        case pairedNeverReported
    }

    public let scenario: Scenario
    private let mac: PairedMac

    /// The specimen Mac. The same name the design representation uses, so the copy assertions and
    /// the rendered surfaces are talking about the same device.
    public static let specimenMac = PairedMac(
        name: "Luke's MacBook Pro",
        pairedAt: Date(timeIntervalSince1970: 1_755_000_000),
        lastSeen: Date(timeIntervalSince1970: 1_755_003_600),
        host: "192.168.1.24",
        port: 7333,
        fingerprint: "SHA256:5f2b9c0e"
    )

    /// A name long enough to force the Overflow state.
    public static let longNameMac = PairedMac(
        name: "Luke's 16-inch MacBook Pro (work, Ventura office)",
        pairedAt: Date(timeIntervalSince1970: 1_755_000_000),
        lastSeen: Date(timeIntervalSince1970: 1_755_003_600),
        host: "192.168.1.24",
        port: 7333,
        fingerprint: "SHA256:5f2b9c0f"
    )

    public init(_ scenario: Scenario = .paired, mac: PairedMac = FixturePairingService.specimenMac) {
        self.scenario = scenario
        self.mac = mac
    }

    public func pair(using attempt: PairingAttempt) async -> PairingOutcome {
        // Expiry is checked from the payload the phone actually holds, before any scenario applies:
        // a scanned code whose window has closed is expired regardless of what the Mac would say,
        // and this is the one failure the phone can determine on its own.
        if case let .scanned(payload) = attempt, payload.hasExpired(at: Date()) {
            return .expired
        }

        switch scenario {
        case .paired, .pairedThenUnreachable:
            return .paired(resolved(from: attempt))
        case .pairedNeverReported:
            let base = resolved(from: attempt)
            return .paired(PairedMac(
                name: base.name,
                pairedAt: base.pairedAt,
                lastSeen: nil,
                host: base.host,
                port: base.port,
                fingerprint: base.fingerprint
            ))
        case .notRecognised: return .notRecognised
        case .expired: return .expired
        case .alreadyUsed: return .alreadyUsed
        case .versionMismatch: return .versionMismatch(macName: attempt.macName)
        case .unreachable: return .unreachable(macName: attempt.macName)
        case .refused: return .refused(macName: attempt.macName)
        case .notAPairingCode: return .notAPairingCode
        case .malformedPayload: return .malformedPayload
        }
    }

    public func reachability(of _: PairedMac) async -> ConnectionState {
        switch scenario {
        case .pairedThenUnreachable, .unreachable: .notReachable
        default: .reachable
        }
    }

    /// A scanned attempt names the Mac; a typed one does not know it until the Mac answers.
    private func resolved(from attempt: PairingAttempt) -> PairedMac {
        guard case let .scanned(payload) = attempt else { return mac }
        return PairedMac(
            name: payload.macName,
            pairedAt: Date(),
            lastSeen: Date(),
            host: payload.host,
            port: payload.port,
            fingerprint: payload.fingerprint
        )
    }
}
