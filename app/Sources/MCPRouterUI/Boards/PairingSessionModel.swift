#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The Mac pairing sheet's state: what this build can offer, the code on screen, and the clock.
    ///
    /// Separate from `InboxBoardModel` because it is a different lifetime. A code is alive for five
    /// minutes whether or not anyone is looking at the inbox, and the countdown has to keep running
    /// while the sheet is open over any board — the sheet is reachable from the File menu as well as
    /// from the pane.
    @MainActor
    @Observable
    public final class PairingSessionModel {
        /// What the sheet can show, which is a fact about this build before it is a fact about state.
        public enum Phase: Sendable, Equatable {
            /// No transport. **The only phase a Release build reaches.**
            case noEndpoint
            /// An endpoint exists and a code is being minted.
            case preparing
            /// A code is on screen, with the text the QR encodes.
            case live(IssuedPairingCode, encoded: String)
            /// The code's window closed with the sheet still open.
            case expired(IssuedPairingCode)
            /// The issue attempt failed. Reached only from an observed failure.
            case failed(String)
        }

        @ObservationIgnored private let service: any InboxService
        @ObservationIgnored private let clock: @MainActor () -> Date
        /// Resolved when a code is issued rather than at init.
        ///
        /// `ProcessInfo.hostName` is ~40 ms on a cold call, and this model is now constructed during
        /// `ShellModel.init` — on the launch path, before the first frame. A Release build never
        /// issues a payload at all, so it should never pay for a host name it will not render.
        @ObservationIgnored private let macNameProvider: () -> String

        public private(set) var phase: Phase = .noEndpoint
        public var isOpen = false

        /// Redrawn once a second so the countdown moves. Held rather than derived because a view
        /// cannot observe a clock.
        public private(set) var now: Date

        /// Codes this Mac has already paired a device with. One code, one device — enforced here
        /// because this Mac is the issuer.
        public private(set) var spent: Set<PairingCode> = []

        @ObservationIgnored private var ticker: Task<Void, Never>?

        public init(
            service: any InboxService,
            macName: @autoclosure @escaping () -> String = PairingSessionModel.hostName(),
            clock: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.service = service
            macNameProvider = macName
            self.clock = clock
            now = clock()
        }

        /// The name this Mac calls itself.
        ///
        /// `ProcessInfo.hostName` rather than a constant, because the phone renders this and a
        /// hardcoded name would be a value nobody observed. It is the one piece of the payload that
        /// is *meant* to be read by a human.
        public static func hostName() -> String {
            let name = ProcessInfo.processInfo.hostName
            // `.local` is an mDNS artefact, not part of what anyone calls their machine.
            return name.hasSuffix(".local") ? String(name.dropLast(6)) : name
        }

        // MARK: - Opening

        /// Open the sheet and, where this build can, issue a code.
        ///
        /// **No endpoint means no code and no payload** — not a code with placeholder values. The
        /// early return is the control: there is no path from here to `MacPairing.encode` without a
        /// `PairingEndpoint`, which is itself failable, so an endpoint that could not produce a
        /// decodable payload cannot reach the encoder either.
        public func open() {
            isOpen = true
            guard case let .available(endpoint) = service.availability() else {
                phase = .noEndpoint
                return
            }
            phase = .preparing
            issue(from: endpoint)
            startTicking()
        }

        public func close() {
            isOpen = false
            stopTicking()
        }

        private func issue(from endpoint: PairingEndpoint) {
            // The window comes from the service rather than from the constant, so a build whose
            // transport mints shorter-lived codes is described accurately — and so the near-expiry
            // state is reachable in the running app at all. A five-minute countdown cannot be driven
            // by an acceptance script, which is why the `expiring` scenario existed and did nothing.
            let issued = MacPairing.issue(at: clock(), lifetime: service.pairingLifetime())
            let payload = MacPairing.payload(for: issued, endpoint: endpoint, macName: macNameProvider())
            do {
                phase = try .live(issued, encoded: MacPairing.encode(payload))
            } catch {
                // A payload that cannot be encoded is a defect, not a user-facing condition — but it
                // is still shown rather than swallowed, because a sheet that renders nothing with no
                // explanation is the failure `DESIGN.md` §5 exists to prevent.
                phase = .failed("The code could not be prepared.")
            }
        }

        /// Mint a fresh code, which is what the expired state offers.
        public func reissue() {
            guard case let .available(endpoint) = service.availability() else {
                phase = .noEndpoint
                return
            }
            issue(from: endpoint)
        }

        // MARK: - The clock

        /// One second, which is the resolution the countdown renders at. A faster tick would redraw
        /// the sheet for a string that has not changed.
        static let tickNanoseconds: UInt64 = 1_000_000_000

        private func startTicking() {
            stopTicking()
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: Self.tickNanoseconds)
                    guard !Task.isCancelled else { return }
                    await self?.tick()
                }
            }
        }

        public func stopTicking() {
            ticker?.cancel()
            ticker = nil
        }

        /// Advance the clock and expire the code if its window has closed.
        ///
        /// Kept internal and callable so a test can drive expiry without waiting five minutes —
        /// `ShellTestSupport.waitUntil` is for a condition that *becomes* true on its own, and a
        /// wall-clock countdown is not something to wait on.
        func tick() {
            now = clock()
            guard case let .live(issued, _) = phase, issued.hasExpired(at: now) else { return }
            phase = .expired(issued)
        }

        // MARK: - Deciding

        /// What this Mac does with a submitted code, and the record it keeps afterwards.
        ///
        /// Returns `nil` when the code is accepted. The caller marks it spent by calling
        /// `markPaired`, which is deliberately a second step: a decision that *also* mutated the
        /// spent set could not be tested for its decision alone.
        public func decide(submitted: PairingCode, version: Int = MacPairing.wireVersion) -> PairingRefusal? {
            MacPairing.decide(
                submitted: submitted,
                version: version,
                live: liveCode,
                spent: spent,
                at: clock()
            )
        }

        public func markPaired(_ code: PairingCode) {
            spent.insert(code)
        }

        /// A human at this Mac dismissing the request. A decision, not an error.
        public func declineRequest() -> PairingRefusal {
            .declined
        }

        public var liveCode: IssuedPairingCode? {
            guard case let .live(issued, _) = phase else { return nil }
            return issued
        }

        /// The text the QR encodes, or nil when there is nothing to encode.
        ///
        /// The view takes **this**, never a `PairingPayload`, so there is no second encoder and no
        /// path by which a view could build a payload of its own.
        public var encodedPayload: String? {
            guard case let .live(_, encoded) = phase else { return nil }
            return encoded
        }

        public var remaining: TimeInterval? {
            liveCode?.timeRemaining(at: now)
        }
    }
#endif
