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
    ///
    /// **The code is the router's.** The sheet asks the router to mint it and takes it back on
    /// close, so the router's `pairing` state is the one record of what can be paired with. The
    /// Mac draws the code and encodes the payload; it does not decide whether a code is live.
    @MainActor
    @Observable
    public final class PairingSessionModel {
        /// What the sheet can show, which is a fact about this build before it is a fact about state.
        public enum Phase: Sendable, Equatable {
            /// No transport. **The only phase a Release build reaches.**
            case noEndpoint
            /// An endpoint exists and the router is being asked for a code.
            case preparing
            /// A code is on screen, with the text the QR encodes.
            case live(IssuedPairingCode, encoded: String)
            /// The code's window closed with the sheet still open.
            case expired(IssuedPairingCode)
            /// The issue attempt failed. Reached only from an observed failure.
            case failed(String)
        }

        @ObservationIgnored private let service: any InboxService
        @ObservationIgnored private let client: any ControlAPIClient
        @ObservationIgnored private let clock: @MainActor () -> Date
        /// Resolved when a code is issued rather than at init.
        ///
        /// `ProcessInfo.hostName` is ~40 ms on a cold call, and this model is now constructed during
        /// `ShellModel.init` — on the launch path, before the first frame. A Release build never
        /// issues a payload at all, so it should never pay for a host name it will not render.
        @ObservationIgnored private let macNameProvider: () -> String
        /// Bumped by every open, reissue and close. A router answer carries the generation it was
        /// asked under, and an answer whose generation has been overtaken is not shown.
        @ObservationIgnored private var issueGeneration = 0

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
            client: any ControlAPIClient,
            macName: @autoclosure @escaping () -> String = PairingSessionModel.hostName(),
            clock: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.service = service
            self.client = client
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

        /// Open the sheet and, where this build has an endpoint, ask the router for a code.
        ///
        /// **No endpoint means no request and no payload** — not a code with placeholder values. The
        /// early return is the control: a code only reaches the encoder through `requestCode(from:)`,
        /// which takes a `PairingEndpoint`, and an endpoint that could not produce a decodable payload
        /// cannot be constructed at all.
        public func open() {
            isOpen = true
            guard case let .available(endpoint) = service.availability() else {
                phase = .noEndpoint
                return
            }
            requestCode(from: endpoint)
            startTicking()
        }

        /// Close the sheet and take the router's code back.
        ///
        /// A code left live on the router is pairable by a phone for as long as its window runs, with
        /// nobody looking at it, so the revoke is sent here rather than left to expiry. A request that
        /// is still in flight when this runs is handled where its answer arrives.
        public func close() {
            isOpen = false
            issueGeneration += 1
            stopTicking()
            switch phase {
            case .preparing, .live:
                Task { await revokeOnRouter() }
            case .noEndpoint, .expired, .failed:
                break
            }
        }

        /// Mint a fresh code, which is what the expired state offers.
        public func reissue() {
            guard case let .available(endpoint) = service.availability() else {
                phase = .noEndpoint
                return
            }
            requestCode(from: endpoint)
        }

        // MARK: - Asking the router

        private func requestCode(from endpoint: PairingEndpoint) {
            phase = .preparing
            issueGeneration += 1
            let generation = issueGeneration
            Task { await issue(from: endpoint, generation: generation) }
        }

        /// Show the code the router answered with, unless the answer has been overtaken.
        ///
        /// The router keeps one live code, so an answer from a request that a newer open or a close has
        /// overtaken names a code the router has already replaced or is about to lose. It is not shown.
        /// If the sheet has closed since the request, the code it minted is taken back here: the close
        /// revoked before the router had minted anything, and nothing else would.
        private func issue(from endpoint: PairingEndpoint, generation: Int) async {
            let issued: IssuedPairingCode
            do {
                issued = try await client.issuePairingCode()
            } catch {
                guard generation == issueGeneration else { return }
                phase = .failed("The code could not be prepared.")
                return
            }
            guard generation == issueGeneration else {
                if !isOpen { await revokeOnRouter() }
                return
            }
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

        /// Take the router's live code back. A revoke that does not reach the router leaves a code
        /// that the router's five-minute window still bounds, so nothing here retries it.
        private func revokeOnRouter() async {
            _ = try? await client.revokePairingCode()
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

        /// The same window the countdown text reads, as a fraction of the issued window.
        ///
        /// Read off `now` rather than a fresh `clock()` call, so the ring and the text can never
        /// disagree about which second it is — they are two renderings of one reading, and a ring
        /// a tick ahead of its own label is worse than no ring.
        public var fractionRemaining: Double? {
            liveCode?.fractionRemaining(at: now)
        }
    }
#endif
