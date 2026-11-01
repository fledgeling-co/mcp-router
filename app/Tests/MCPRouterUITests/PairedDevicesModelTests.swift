#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    @MainActor
    @Suite("Security paired-device management")
    struct PairedDevicesModelTests {
        static let phone = ConfirmedPairedPhone(
            phoneId: "one",
            phoneName: "Test iPhone",
            pairedAt: .init(timeIntervalSince1970: 100)
        )
        static let other = ConfirmedPairedPhone(
            phoneId: "two",
            phoneName: "Other iPhone",
            pairedAt: .init(timeIntervalSince1970: 200)
        )
        static func state(_ phones: [ConfirmedPairedPhone]?) -> PairingState {
            PairingState(
                code: nil,
                listener: .init(enabled: false, port: nil, advertising: false),
                confirmedPhones: phones
            )
        }

        private static func model(_ script: DeviceScript) -> (PairedDevicesModel, RecordingControlAPIClient) {
            let client = RecordingControlAPIClient(
                wrapping: FixtureControlAPIClient(),
                pairingStateOverride: { () async throws(ControlAPIError) -> PairingState in
                    try await script.read()
                },
                phoneRevokeOverride: { (id: String) async throws(ControlAPIError) -> String in
                    try await script.revoke(id)
                }
            )
            return (PairedDevicesModel(client: client), client)
        }

        @Test(
            "confirmation revokes only the named peer then reads actual remaining peers from the same client"
        )
        func successfulReadback() async {
            let script = DeviceScript([.success(Self.state([Self.phone, Self.other])),
                                       .success(Self.state([Self.phone, Self.other])),
                                       .success(Self.state([Self.other]))])
            let (model, client) = Self.model(script)
            await model.load()
            model.requestRevoke(Self.phone)
            #expect(client.calls.pairingPhoneRevokes.isEmpty)
            await model.confirmRevoke()
            #expect(client.calls.pairingPhoneRevokes == ["one"])
            #expect(client.calls.pairingStateReads == 3)
            #expect(model.phones == [Self.other])
            #expect(model.state?.listener.enabled == false)
            #expect(model.pendingPhone == nil && model.error == nil)
            #expect(model.notice?.contains("Test iPhone") == true)
        }

        @Test("cancel and an unavailable legacy device list make no revocation request")
        func cancelAndUnavailable() async {
            let (model, client) = Self.model(DeviceScript([.success(Self.state([Self.phone]))]))
            await model.load()
            model.requestRevoke(Self.phone)
            model.cancelRevoke()
            await model.confirmRevoke()
            #expect(client.calls.pairingPhoneRevokes.isEmpty)
            let (legacy, legacyClient) = Self.model(DeviceScript([.success(Self.state(nil))]))
            await legacy.load()
            legacy.requestRevoke(Self.phone)
            #expect(!legacy.canRevoke && legacy.pendingPhone == nil)
            #expect(legacyClient.calls.pairingPhoneRevokes.isEmpty)
            let missing = PairedDevicesModel(client: nil)
            await missing.load()
            #expect(missing.error != nil && !missing.canRevoke)
        }

        @Test("a renamed or replaced peer invalidates the reviewed confirmation")
        func changedPeerRefusesMutation() async {
            let renamed = ConfirmedPairedPhone(
                phoneId: "one",
                phoneName: "Changed phone",
                pairedAt: Self.phone.pairedAt
            )
            let (model, client) = Self.model(DeviceScript([
                .success(Self.state([Self.phone])),
                .success(Self.state([renamed]))
            ]))
            await model.load()
            model.requestRevoke(Self.phone)
            await model.confirmRevoke()
            #expect(client.calls.pairingPhoneRevokes.isEmpty)
            #expect(model.phones == [renamed])
            #expect(model.notice?.contains("changed") == true)
        }

        @Test("a failed refresh keeps only a labelled old reading and disables changes")
        func staleReading() async {
            let (model, client) = Self.model(DeviceScript([.success(Self.state([Self.phone])),
                                                           .failure(.routerNotRunning)]))
            await model.load()
            await model.load()
            model.requestRevoke(Self.phone)
            #expect(model.phones == [Self.phone])
            #expect(model.error == .routerNotRunning && !model.canRevoke)
            #expect(model.pendingPhone == nil && client.calls.pairingPhoneRevokes.isEmpty)
        }

        @Test("failed deletion preserves the refusal and reads back instead of removing a cached row")
        func failedDelete() async {
            let script = DeviceScript(
                [.success(Self.state([Self.phone]))],
                revokeError: .server(status: 500, message: "fixture refusal")
            )
            let (model, client) = Self.model(script)
            await model.load()
            model.requestRevoke(Self.phone)
            await model.confirmRevoke()
            #expect(model.phones == [Self.phone])
            #expect(model.error == .server(status: 500, message: "fixture refusal"))
            #expect(client.calls.pairingStateReads == 3)
            #expect(!model.canRevoke)
        }

        @Test("a failed post-write read cannot present a verified removal")
        func failedReadback() async {
            let (model, _) = Self.model(DeviceScript([
                .success(Self.state([Self.phone])),
                .success(Self.state([Self.phone])),
                .failure(.routerNotRunning)
            ]))
            await model.load()
            model.requestRevoke(Self.phone)
            await model.confirmRevoke()
            #expect(model.phones == nil && model.error == .routerNotRunning)
            #expect(model.notice?.contains("could not be verified") == true)
            #expect(!model.canRevoke)
        }

        @Test("a second confirmation and refresh cannot race an in-flight revocation")
        func singleFlight() async throws {
            let gate = DeviceReadGate()
            let script = DeviceScript([.success(Self.state([Self.phone])), .success(Self.state([Self.phone])),
                                       .success(Self.state([]))], gate: gate)
            let (model, client) = Self.model(script)
            await model.load()
            model.requestRevoke(Self.phone)
            let first = Task { await model.confirmRevoke() }
            try await ShellTestSupport.waitUntil { model.isRevoking }
            await model.confirmRevoke()
            await model.load()
            #expect(client.calls.pairingPhoneRevokes.isEmpty)
            await gate.open()
            await first.value
            #expect(client.calls.pairingPhoneRevokes == ["one"])
            #expect(client.calls.pairingStateReads == 3)
        }

        @Test("an acknowledgement that leaves the peer listed is not a success")
        func stillListed() async {
            let (model, _) = Self.model(DeviceScript([.success(Self.state([Self.phone]))]))
            await model.load()
            model.requestRevoke(Self.phone)
            await model.confirmRevoke()
            #expect(model
                .error == .malformedResponse(detail: "the router still lists this phone as confirmed"))
            #expect(model.phones == nil)
        }
    }

    private actor DeviceScript {
        let states: [Result<PairingState, ControlAPIError>]
        let revokeError: ControlAPIError?
        var index = 0
        let gate: DeviceReadGate?
        init(
            _ states: [Result<PairingState, ControlAPIError>],
            revokeError: ControlAPIError? = nil,
            gate: DeviceReadGate? = nil
        ) {
            self.states = states
            self.revokeError = revokeError
            self.gate = gate
        }

        func read() async throws(ControlAPIError) -> PairingState {
            let current = index
            let next = states[min(current, states.count - 1)]
            index += 1
            if current == 1 { await gate?.wait() }
            switch next {
            case let .success(state): return state
            case let .failure(error): throw error
            }
        }

        func revoke(_ id: String) throws(ControlAPIError) -> String {
            if let revokeError { throw revokeError }
            return id
        }
    }

    private actor DeviceReadGate {
        var continuation: CheckedContinuation<Void, Never>?
        var isOpen = false
        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }
#endif
