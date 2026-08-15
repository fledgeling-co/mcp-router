import Foundation
import Testing
@testable import RouterCore

/// `D-p1-c` — a flow that settles before its observer arrives must be reported as it settled.
///
/// `settle` resumes any waiting observer and then calls `cleanup`, which clears `current`. Nothing
/// recorded what had happened, so an observer arriving after that saw a coordinator with nothing in
/// flight and was told `no authorization is in flight`. ``ControlPorts`` states the requirement
/// directly — *a flow that settles between the two calls must still be reported here as
/// authorized* — and the route turns a breach of it into an `onIncomplete` warn with no
/// `clearPending` and no re-index: the tokens land on disk and the tools never appear.
///
/// The ordering is not exotic. The browser redirect races the route: the callback can land while
/// the route is still between `begin` and `awaitCompletion`, and on a loaded machine it often does.
///
/// **Where this is proven.** At the unit boundary, and deliberately not at the wire: nothing
/// conforms to ``AuthTransport`` yet (`D-p1-a`), which is why `control-auth-post-http` is a blocked
/// parity row. These tests do not claim a wire proof.
@Suite("D-p1-c — a settled flow is reported as it settled, not as absent")
struct AuthSettledFlowTests {
    private let server = JSString("linear")

    private func begin(
        _ coordinator: AuthFlowCoordinator,
        _ listener: FakeListener,
        server: String = "linear"
    ) async throws {
        _ = try await coordinator.begin(
            server: JSString(server), listener: listener, transport: FakeAuthTransport(),
            port: 8880, authorizationURL: { "https://provider.example/authorize" }
        )
    }

    @Test("a success that lands BEFORE awaitCompletion is reported as authorized")
    func successBeforeObserverIsReported() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = FakeListener()
        try await begin(coordinator, listener)

        // The callback wins the race: the flow settles with nothing observing it.
        _ = await listener.deliver("/callback?code=abc")
        #expect(await coordinator.currentFlow() == nil, "the flow has settled and been cleaned up")

        // The route arrives afterwards. Before this fix it was told `no authorization is in
        // flight`, and a successful authorization became an onIncomplete warn with no re-index.
        try await coordinator.awaitCompletion(server: server)
    }

    @Test("a failure that lands before the observer carries its own reason, not 'no authorization'")
    func failureBeforeObserverKeepsItsReason() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = FakeListener()
        try await begin(coordinator, listener)

        _ = await listener.deliver("/callback?error=access_denied")

        var message: String?
        do {
            try await coordinator.awaitCompletion(server: server)
        } catch {
            message = (error as? AuthFailure)?.message
        }
        #expect(message != nil)
        #expect(
            message != "no authorization is in flight",
            "a rejected flow must report its rejection, not report itself absent"
        )
    }

    /// The complement, and the reason this fix cannot be a blanket success. Without this case a
    /// coordinator that answered every call would pass the test above.
    @Test("a server that never authorized is still reported absent")
    func neverStartedIsStillAbsent() async throws {
        let coordinator = AuthFlowCoordinator()
        var message: String?
        do {
            try await coordinator.awaitCompletion(server: JSString("never-started"))
        } catch {
            message = (error as? AuthFailure)?.message
        }
        #expect(message == "no authorization is in flight")
    }

    /// The scenario an out-of-family critic found in the first version of this fix, which cleared
    /// the record on EVERY `begin`. `AuthRoutes.authStart` captures `awaitCompletion` and runs it
    /// in a detached `Task`, so an authorization for a second server can begin — and settle —
    /// before the first server's observer is ever scheduled. With one shared slot, the first
    /// server's success was erased and its observer was told `no authorization is in flight`:
    /// the very defect this suite exists to close, reachable on any sufficiently loaded machine.
    @Test("another server's flow does not erase this server's outcome")
    func anotherServersFlowDoesNotEraseThisOne() async throws {
        let coordinator = AuthFlowCoordinator()
        let first = FakeListener()
        try await begin(coordinator, first)
        _ = await first.deliver("/callback?code=abc")

        // A second server authorizes, start to finish, before anyone observes the first.
        let second = FakeListener()
        try await begin(coordinator, second, server: "notion")
        _ = await second.deliver("/callback?code=def")

        // Both outcomes must still be readable, each by its own server.
        try await coordinator.awaitCompletion(server: server)
        try await coordinator.awaitCompletion(server: JSString("notion"))
    }

    /// A record belongs to one flow of one server. A fresh authorization for the SAME server must
    /// not be answered by the previous one's success.
    @Test("a new flow for the same server clears that server's previous outcome")
    func newFlowClearsTheRecord() async throws {
        let coordinator = AuthFlowCoordinator()
        let first = FakeListener()
        try await begin(coordinator, first)
        _ = await first.deliver("/callback?code=abc")

        // The same server authorizes again. The earlier success must not answer for this flow.
        let second = FakeListener()
        try await begin(coordinator, second)

        let settled = SettledFlag()
        Task {
            do {
                try await coordinator.awaitCompletion(server: server)
                await settled.set("resolved")
            } catch {
                await settled.set("threw")
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(
            await settled.value() == nil,
            "the observer must wait on the NEW flow, not be handed the previous flow's success"
        )
    }

    /// The record is consumed when it is read, so a stray call long afterwards is answered
    /// honestly rather than with an outcome from an authorization nobody is waiting on.
    @Test("a recorded outcome is read once")
    func recordedOutcomeIsReadOnce() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = FakeListener()
        try await begin(coordinator, listener)
        _ = await listener.deliver("/callback?code=abc")

        try await coordinator.awaitCompletion(server: server)

        var message: String?
        do {
            try await coordinator.awaitCompletion(server: server)
        } catch {
            message = (error as? AuthFailure)?.message
        }
        #expect(message == "no authorization is in flight")
    }

    /// B85 is unchanged: a superseded flow is torn down through `cleanup`, which does not settle
    /// and therefore records nothing. Its observer must still see `abandoned` rather than inherit
    /// an outcome.
    @Test("B85 — a superseded flow is still abandoned, never reported authorized")
    func supersededStillAbandoned() async throws {
        let coordinator = AuthFlowCoordinator()
        let first = FakeListener()
        try await begin(coordinator, first, server: "alpha")

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

        let second = FakeListener()
        try await begin(coordinator, second, server: "beta")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(await settled.value() == "abandoned")
    }
}
