#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    @MainActor
    @Suite("Settings history reset")
    struct SettingsHistoryResetTests {
        static let since = "2026-11-02T01:00:00.000Z"
        private static func client(_ script: ResetScript) -> RecordingControlAPIClient {
            RecordingControlAPIClient(
                wrapping: FixtureControlAPIClient(),
                resetOverride: { () async throws(ControlAPIError) -> UsageReset in
                    try await script.reset()
                },
                summaryOverride: { () async throws(ControlAPIError) -> UsageSummary in
                    try await script.summary()
                }
            )
        }

        @Test("cancel and closed-sheet confirmation send no reset request")
        func cancelWritesNothing() async {
            let client = Self.client(ResetScript())
            let model = SettingsWindowModel(store: InMemoryTokenStore(), client: client)
            model.requestHistoryReset()
            #expect(model.sheet == .resetHistory)
            model.cancelHistoryReset()
            await model.resetHistory()
            #expect(client.calls.usageResets == 0 && client.calls.usageSummaryReads == 0)
        }

        @Test("confirm is single-flight and dismisses only after authoritative readback")
        func confirmedReadback() async throws {
            let script = ResetScript()
            await script.holdReset()
            let client = Self.client(script)
            var refreshed = 0
            let model = SettingsWindowModel(
                store: InMemoryTokenStore(),
                client: client,
                refreshHistory: { refreshed += 1 }
            )
            model.requestHistoryReset()
            let first = Task { await model.resetHistory() }
            try await ShellTestSupport.waitUntil { client.calls.usageResets == 1 }
            #expect(model.isResetting && model.sheet == .resetHistory && model.resetNotice == nil)
            await model.resetHistory()
            model.cancelHistoryReset()
            #expect(model.sheet == .resetHistory && client.calls.usageResets == 1)
            await script.releaseReset()
            await first.value
            #expect(model.sheet == nil && model.resetError == nil)
            #expect(client.calls.usageResets == 1 && client.calls.usageSummaryReads == 1)
            #expect(model.resetSummary?.since == Self.since && refreshed == 1)
            #expect(
                model.resetSummary?.servers.first?.calls == 2,
                "calls recorded after reset must survive the readback"
            )
            #expect(model.resetNotice?.contains(Self.since) == true)
        }

        @Test("write refusal remains visible; a readback retry does not repeat a successful reset")
        func failureAndReadRetry() async {
            let script = ResetScript()
            await script.refuseReset()
            let client = Self.client(script)
            let model = SettingsWindowModel(store: InMemoryTokenStore(), client: client)
            model.requestHistoryReset()
            await model.resetHistory()
            #expect(model.sheet == .resetHistory && model.resetError != nil)
            #expect(model.resetSummary == nil && client.calls.usageSummaryReads == 0)
            await script.allowResetAndRefuseRead()
            await model.resetHistory()
            #expect(model.sheet == .resetHistory && model.resetAcknowledgement != nil && model
                .resetError != nil)
            #expect(client.calls.usageResets == 2)
            await script.allowRead()
            await model.resetHistory()
            #expect(model.sheet == nil && model.resetError == nil)
            #expect(client.calls.usageResets == 2 && client.calls.usageSummaryReads == 2)
        }

        @Test(
            "a successful write with an unreadable timestamp is remembered and never submitted again on retry"
        )
        func malformedAcknowledgementDoesNotRepeatWrite() async {
            let script = ResetScript()
            await script.malformedTime()
            let client = Self.client(script)
            let model = SettingsWindowModel(store: InMemoryTokenStore(), client: client)
            model.requestHistoryReset()
            await model.resetHistory()
            #expect(model.resetAcknowledgement?.ok == true)
            #expect(model.resetAcknowledgement?.since == "unreadable-time")
            #expect(model.resetError != nil && model.resetSummary == nil && model.resetNotice == nil)
            await model.resetHistory()
            #expect(client.calls.usageResets == 1 && client.calls.usageSummaryReads == 2)
            #expect(model.sheet == .resetHistory && model.resetError != nil)
            #expect(model.resetAcknowledgement?.since == "unreadable-time")
        }

        @Test("older readback and a false acknowledgement cannot certify a reset")
        func staleReadbackAndRefusal() async {
            let script = ResetScript()
            await script.staleReadback()
            let client = Self.client(script)
            let model = SettingsWindowModel(store: InMemoryTokenStore(), client: client)
            model.requestHistoryReset()
            await model.resetHistory()
            #expect(model.sheet == .resetHistory && model.resetSummary == nil && model.resetError != nil)
            let refused = ResetScript()
            await refused.refuseAcknowledgement()
            let refusedClient = Self.client(refused)
            let refusedModel = SettingsWindowModel(store: InMemoryTokenStore(), client: refusedClient)
            refusedModel.requestHistoryReset()
            await refusedModel.resetHistory()
            #expect(refusedModel.resetError != nil && refusedModel.resetAcknowledgement == nil)
            #expect(refusedClient.calls.usageSummaryReads == 0)
            let missing = SettingsWindowModel(store: InMemoryTokenStore())
            missing.requestHistoryReset()
            await missing.resetHistory()
            #expect(missing.resetError != nil && missing.sheet == .resetHistory)
        }
    }

    private actor ResetScript {
        var resetFailure = false
        var falseAcknowledgement = false
        var malformedTimestamp = false
        var readFailure = false
        var stale = false
        var held = false
        var gate: CheckedContinuation<Void, Never>?
        func holdReset() {
            held = true
        }

        func releaseReset() {
            held = false; gate?.resume(); gate = nil
        }

        func refuseReset() {
            resetFailure = true
        }

        func allowResetAndRefuseRead() {
            resetFailure = false; readFailure = true
        }

        func allowRead() {
            readFailure = false
        }

        func malformedTime() {
            malformedTimestamp = true
        }

        func refuseAcknowledgement() {
            falseAcknowledgement = true
        }

        func staleReadback() {
            stale = true
        }

        func reset() async throws(ControlAPIError) -> UsageReset {
            if held { await withCheckedContinuation { gate = $0 } }
            if resetFailure { throw .routerNotRunning }
            return UsageReset(
                ok: !falseAcknowledgement,
                since: malformedTimestamp ? "unreadable-time" : "2026-11-02T01:00:00.000Z"
            )
        }

        func summary() throws(ControlAPIError) -> UsageSummary {
            if readFailure { throw .routerNotRunning }
            let since = stale ? "2020-01-01T00:00:00Z" : "2026-11-02T01:00:00.000Z"
            return UsageSummary(
                since: since,
                servers: [ServerSummary(
                    name: "after-reset",
                    calls: 2,
                    errors: 0,
                    projects: [:],
                    projectNames: []
                )]
            )
        }
    }
#endif
