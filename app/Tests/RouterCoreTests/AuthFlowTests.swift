import Foundation
import Testing
@testable import RouterCore

// MARK: - The flow

@Suite("R5 auth — the flow and its terminations")
struct AuthFlowTests {
    private func begin(
        _ coordinator: AuthFlowCoordinator,
        server: String,
        listener: FakeListener,
        transport: FakeAuthTransport,
        url: String = "https://provider.example/authorize"
    ) async throws -> LiveFlow {
        try await coordinator.begin(
            server: JSString(server), listener: listener, transport: transport,
            port: 8880, authorizationURL: { url }
        )
    }

    @Test("currentFlow reports the live flow and its URL")
    func currentFlowIsReported() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = FakeListener()
        _ = try await begin(coordinator, server: "linear", listener: listener, transport: FakeAuthTransport())
        let live = await coordinator.currentFlow()
        #expect(live?.server == JSString("linear"))
        #expect(live?.url == "https://provider.example/authorize")
    }

    @Test("B85 — a superseded flow is cleaned up but NEVER settles")
    func supersededFlowNeverSettles() async throws {
        let coordinator = AuthFlowCoordinator()
        let firstListener = FakeListener()
        let firstTransport = FakeAuthTransport()
        _ = try await begin(coordinator, server: "alpha", listener: firstListener, transport: firstTransport)

        // Observe the first flow's completion. It must never resume.
        let settled = SettledFlag()
        Task {
            do {
                try await coordinator.awaitCompletion(server: JSString("alpha"))
                await settled.set("resolved")
            } catch is AuthAbandoned {
                await settled.set("abandoned")
            } catch {
                await settled.set("rejected")
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // Supersede it.
        _ = try await begin(
            coordinator,
            server: "beta",
            listener: FakeListener(),
            transport: FakeAuthTransport()
        )

        // Bounded wait: silence is the assertion.
        try await Task.sleep(nanoseconds: 250_000_000)
        // The reference neither resolves nor rejects a superseded flow — nothing runs. The Swift
        // equivalent must release the observer (a dropped continuation strands its task forever and
        // trips SWIFT TASK CONTINUATION MISUSE) with an outcome that produces no side effect and no
        // warn. "abandoned" is that outcome; "resolved" or "rejected" would both be divergences.
        let outcome = await settled.value()
        #expect(outcome == "abandoned", "got: \(String(describing: outcome))")
        #expect(await firstListener.stopped, "but it IS torn down")
        #expect(await firstTransport.closed)
        #expect(await coordinator.currentFlow()?.server == JSString("beta"))
    }

    @Test("B96 — a superseded flow's late callback cannot null the flow that replaced it")
    func lateCleanupIsGuarded() async throws {
        let coordinator = AuthFlowCoordinator()
        let firstListener = FakeListener()
        _ = try await begin(
            coordinator,
            server: "alpha",
            listener: firstListener,
            transport: FakeAuthTransport()
        )
        _ = try await begin(
            coordinator,
            server: "beta",
            listener: FakeListener(),
            transport: FakeAuthTransport()
        )

        // Drive the OLD listener, as a browser tab that finally lands would.
        _ = await firstListener.deliver("/callback?code=late")

        #expect(
            await coordinator.currentFlow()?.server == JSString("beta"),
            "an unguarded clear would have nulled beta"
        )
    }

    @Test("B84 — a listen failure surfaces as a throw and performs NO cleanup")
    func listenFailurePerformsNoCleanup() async {
        let coordinator = AuthFlowCoordinator()
        let listener = FakeListener()
        await listener.setStartError(AuthFailure("listen EADDRINUSE 127.0.0.1:8880"))
        let transport = FakeAuthTransport()

        await #expect(throws: AuthFailure.self) {
            _ = try await coordinator.begin(
                server: JSString("linear"), listener: listener, transport: transport,
                port: 8880, authorizationURL: { "https://x" }
            )
        }
        #expect(await transport.closed == false, "the reference's listen-error path closes nothing")
        #expect(await coordinator.currentFlow() == nil)
    }

    @Test("B84 — the 20s URL race rejects with its own message AND cleans up")
    func urlRaceCleansUp() async {
        let coordinator = AuthFlowCoordinator(urlTimeoutMilliseconds: 40)
        let listener = FakeListener()
        let transport = FakeAuthTransport()

        await #expect(throws: AuthFailure.self) {
            _ = try await coordinator.begin(
                server: JSString("linear"), listener: listener, transport: transport, port: 8880,
                authorizationURL: {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return "never"
                }
            )
        }
        #expect(await listener.stopped, "this path DOES clean up, unlike the listen failure")
        #expect(await transport.closed)
        #expect(await coordinator.currentFlow() == nil)
    }

    @Test("the overall timeout settles with the reference's message and renders no page")
    func flowTimeout() async throws {
        let coordinator = AuthFlowCoordinator(flowTimeoutMilliseconds: 40)
        let listener = FakeListener()
        _ = try await begin(coordinator, server: "linear", listener: listener, transport: FakeAuthTransport())

        let settled = SettledFlag()
        Task {
            do {
                try await coordinator.awaitCompletion(server: JSString("linear")); await settled
                    .set("resolved")
            } catch { await settled.set((error as? AuthFailure)?.message ?? "?") }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(await settled.value() == "authorization timed out")
        #expect(await listener.stopped)
        #expect(await coordinator.currentFlow() == nil)
    }

    @Test("B82 — a stray request mid-flow leaves the flow live and completable")
    func strayRequestDoesNotEndTheFlow() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = FakeListener()
        _ = try await begin(coordinator, server: "linear", listener: listener, transport: FakeAuthTransport())

        let reply = await listener.deliver("/favicon.ico")
        #expect(reply.status == 404)
        #expect(await listener.stopped == false, "the listener must stay bound")
        #expect(await coordinator.currentFlow()?.server == JSString("linear"))

        // And it still completes normally afterwards.
        let done = await listener.deliver("/callback?code=abc")
        #expect(done.status == 200)
        #expect(await coordinator.currentFlow() == nil)
    }
}

actor SettledFlag {
    private var stored: String?
    func set(_ value: String) {
        if stored == nil { stored = value }
    }

    func value() -> String? {
        stored
    }
}
