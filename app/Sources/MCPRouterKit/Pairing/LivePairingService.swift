import CryptoKit
import Foundation

/// The phone's real pairing exchange, behind a transport seam.
///
/// **Order is the contract (REQ-016, plan §2.2 and §4).** The phone's key is stored before anything
/// is sent, so a key that cannot be stored never reaches the Mac. The paired-Mac record is written
/// only after `pair.ok` and after that key write. The ack follows the record, and nothing reports
/// paired until the ack has gone out, so a failure at any step leaves the phone not paired.
///
/// Not wired into the app. B5 supplies the production transport and makes this the phone's service.
public struct LivePairingService: PairingService {
    private let transport: any PairingTransport
    private let keys: any PhoneKeyStore
    private let records: any PairingRecordStore
    private let discovery: any PairingDiscovery
    private let phoneName: String
    private let timeout: Duration

    public init(
        transport: any PairingTransport,
        keys: any PhoneKeyStore,
        records: any PairingRecordStore,
        discovery: any PairingDiscovery,
        phoneName: String,
        timeout: Duration = .seconds(10)
    ) {
        self.transport = transport
        self.keys = keys
        self.records = records
        self.discovery = discovery
        self.phoneName = phoneName
        self.timeout = timeout
    }

    public func pair(using attempt: PairingAttempt) async -> PairingOutcome {
        // Expiry is the one failure the phone decides alone, so it is checked before any connection.
        if case let .scanned(payload) = attempt, payload.hasExpired(at: Date()) {
            return .expired
        }
        switch await result(for: attempt) {
        case let .paired(mac):
            return .paired(mac)
        case let .refused(refusal):
            return MacPairing.outcome(for: refusal, macName: attempt.macName)
        case let .failed(failure):
            return Self.outcome(for: failure, macName: attempt.macName)
        }
    }

    /// The outcome for a failed exchange. Three failures have an outcome of their own. The rest report
    /// `.unreachable`, which says only that nothing answered, so a protocol violation or an ack that
    /// did not go out is indistinguishable from a Mac that is asleep. That is a known gap, not a choice.
    static func outcome(for failure: LivePairingFailure, macName: String?) -> PairingOutcome {
        switch failure {
        case .identityMismatch: .identityMismatch
        case .keyStore, .recordStore: .notSaved(macName: macName)
        case .untypedAttempt: .typedEntryUnavailable
        case .transport, .timedOut, .protocolViolation, .ackNotSent: .unreachable(macName: macName)
        }
    }

    public func reachability(of mac: PairedMac) async -> ConnectionState {
        await bounded { await probe(mac) }
    }

    func result(for attempt: PairingAttempt) async -> LivePairingResult {
        guard case let .scanned(payload) = attempt else {
            // A typed code carries no fingerprint, so nothing can be pinned and nothing is sent (D2).
            return .failed(.untypedAttempt)
        }
        return await bounded { await exchange(payload) }
    }

    /// Runs `work` in its own task and cancels that task once `timeout` passes.
    ///
    /// The deadline only cancels. `work` decides its own result, so an answer that arrives late is
    /// never reported as if it arrived in time, and nothing is written by the deadline itself.
    private func bounded<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
        let timeout = timeout
        let task = Task { await work() }
        let deadline = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            task.cancel()
        }
        let value = await task.value
        deadline.cancel()
        return value
    }

    private func exchange(_ payload: PairingPayload) async -> LivePairingResult {
        let key: P256.Signing.PrivateKey
        do {
            key = try await keys.loadOrCreate()
        } catch {
            return .failed(.keyStore)
        }

        let channel: any PairingChannel
        do {
            channel = try await transport.connect(
                host: payload.host,
                port: payload.port,
                expecting: payload.fingerprint
            )
        } catch PairingTransportError.identityMismatch {
            return .failed(.identityMismatch)
        } catch {
            return .failed(transportFailure())
        }

        let result = await converse(on: channel, payload, phoneKey: key.publicKey.derRepresentation)
        await channel.close()
        return result
    }

    private func converse(
        on channel: any PairingChannel,
        _ payload: PairingPayload,
        phoneKey: Data
    ) async -> LivePairingResult {
        // Pin before anything is sent. A certificate other than the one the QR named gets no request.
        guard channel.peerFingerprint == payload.fingerprint else {
            return .failed(.identityMismatch)
        }

        let request: Data
        do {
            request = try PairingFrame.encode(
                .request(code: payload.code, phoneName: phoneName, phoneKey: phoneKey)
            )
        } catch {
            return .failed(.protocolViolation)
        }
        do {
            try await channel.send(request)
        } catch {
            return .failed(transportFailure())
        }

        let frame: Data
        do {
            frame = try await channel.receive()
        } catch is PairingFrameError {
            // The framing gate refused the length prefix, so the Mac sent something the contract does
            // not allow. That is a protocol violation, not a connection that failed.
            return .failed(.protocolViolation)
        } catch {
            return .failed(transportFailure())
        }
        let reply: PairingMessage
        do {
            reply = try PairingFrame.decode(frame)
        } catch {
            return .failed(.protocolViolation)
        }

        switch reply {
        case let .refused(refusal):
            return .refused(refusal)
        case let .ok(macName, phoneId):
            return await commit(macName: macName, phoneId: phoneId, payload: payload, on: channel)
        default:
            return .failed(.protocolViolation)
        }
    }

    /// Writes the record, then acks it. Nothing reports paired until the ack has gone out.
    ///
    /// The store holds one Mac, so this save replaces whatever was paired before. If the ack fails,
    /// the earlier record is put back rather than cleared, because the attempt is what overwrote it.
    private func commit(
        macName: String,
        phoneId: String,
        payload: PairingPayload,
        on channel: any PairingChannel
    ) async -> LivePairingResult {
        let previous = await records.load()
        let mac = PairedMac(
            name: macName,
            pairedAt: Date(),
            lastSeen: Date(),
            host: payload.host,
            port: payload.port,
            fingerprint: payload.fingerprint,
            phoneID: phoneId
        )
        do {
            try await records.save(mac)
        } catch {
            // A failed write can take the earlier record with it, so it is put back, as an ack failure
            // does below.
            await restore(previous)
            return .failed(.recordStore)
        }

        do {
            try await channel.send(PairingFrame.encode(.ack(phoneId: phoneId)))
        } catch {
            await restore(previous)
            return .failed(.ackNotSent)
        }
        return .paired(mac)
    }

    private func restore(_ previous: PairingRecordLoad) async {
        if case let .loaded(earlier) = previous {
            do {
                try await records.save(earlier)
            } catch {
                ControlLog().warning("earlier pairing could not be restored after a failed ack")
            }
        } else {
            _ = await records.unpair()
        }
    }

    /// A reachability probe: the stored address first, then a browse for the Mac wherever it now is.
    ///
    /// A Mac counts as itself only while its certificate is the stored fingerprint. An address that refuses,
    /// or answers as some other certificate, sends the probe to the browse. Nothing is sent in either case.
    private func probe(_ mac: PairedMac) async -> ConnectionState {
        if await answers(host: mac.host, port: mac.port, as: mac.fingerprint) { return .reachable }
        return await rediscover(mac) ? .reachable : .notReachable
    }

    /// Whether a connection to `host:port` completes and presents the pinned certificate.
    private func answers(host: String, port: Int, as fingerprint: String) async -> Bool {
        let channel: any PairingChannel
        do {
            channel = try await transport.connect(host: host, port: port, expecting: fingerprint)
        } catch {
            return false
        }
        let pinned = channel.peerFingerprint == fingerprint
        await channel.close()
        return pinned
    }

    /// Dials each endpoint the browse names, and keeps the first the stored certificate answers from.
    ///
    /// Endpoints that advertise the stored name are tried first, since that is the likely one. The name only
    /// orders the attempts: a Mac is the endpoint whose certificate matches, whatever it calls itself. At
    /// most
    /// `maxCandidates` are dialled, because anyone on the LAN can advertise a name and each dial costs a
    /// connection. They are dialled together, so an endpoint that accepts and never answers holds up only
    /// itself, and a Mac further down the list is still tried within the probe's timeout.
    private func rediscover(_ mac: PairedMac) async -> Bool {
        let found = await discovery.browse()
        let likely = found.filter { $0.name == mac.name }
        let others = found.filter { $0.name != mac.name }
        let candidates = Array((likely + others).prefix(Self.maxCandidates))
        guard let winner = await firstAnswering(candidates, as: mac.fingerprint) else { return false }
        await moveRecord(of: mac, to: winner)
        return true
    }

    /// The first candidate to present `fingerprint`, in the order they answer. Once one has, the rest are
    /// cancelled, and any that has not finished reports nothing.
    private func firstAnswering(
        _ candidates: [DiscoveredMac],
        as fingerprint: String
    ) async -> DiscoveredMac? {
        await withTaskGroup(of: DiscoveredMac?.self) { group in
            for candidate in candidates {
                group.addTask {
                    let pinned = await answers(host: candidate.host, port: candidate.port, as: fingerprint)
                    return pinned ? candidate : nil
                }
            }
            for await winner in group where winner != nil {
                group.cancelAll()
                return winner
            }
            return nil
        }
    }

    /// How many browse endpoints one probe will dial, the stored address not counted.
    private static let maxCandidates = 8

    /// Writes the Mac's new address, and only if the stored record is still this Mac. A pairing that replaced
    /// the record while the probe ran is not overwritten. The identity fields are kept as they were stored.
    private func moveRecord(of mac: PairedMac, to candidate: DiscoveredMac) async {
        guard case let .loaded(current) = await records.load(),
              current.fingerprint == mac.fingerprint else { return }
        let moved = PairedMac(
            name: current.name,
            pairedAt: current.pairedAt,
            lastSeen: current.lastSeen,
            host: candidate.host,
            port: candidate.port,
            fingerprint: current.fingerprint,
            phoneID: current.phoneID
        )
        do {
            try await records.save(moved)
        } catch {
            ControlLog().warning("the Mac's new address could not be saved")
        }
    }

    /// A cancelled attempt is a timeout; any other transport error is a failed connection.
    private func transportFailure() -> LivePairingFailure {
        Task.isCancelled ? .timedOut : .transport
    }
}

/// How one exchange ended, before it is mapped to a `PairingOutcome`.
enum LivePairingResult: Equatable, Sendable {
    case paired(PairedMac)
    case refused(PairingRefusal)
    case failed(LivePairingFailure)
}

/// Why an exchange failed. Each names the step that stopped it, so a test can say which one.
enum LivePairingFailure: Equatable, Sendable {
    case untypedAttempt
    case keyStore
    case transport
    case timedOut
    case identityMismatch
    case protocolViolation
    case recordStore
    case ackNotSent
}
