import Foundation
import Testing
@testable import RouterCore

/// A listener whose `stop()` genuinely **suspends**, the way the real one does while it waits for
/// its socket to come back.
///
/// `FakeListener.stop()` returns without suspending, which closes the re-entrancy window in
/// `cleanup` entirely — so the whole double-based suite could pass while the production pairing
/// trapped. That is the specific way a test double lies: not by asserting the wrong thing, but by
/// removing the interleaving the real component has.
actor SlowStopListener: CallbackListening {
    private var handler: (@Sendable (String) async -> CallbackReply)?
    private let stopDelayNanoseconds: UInt64
    private(set) var stopped = false

    init(stopDelayNanoseconds: UInt64 = 200_000_000) {
        self.stopDelayNanoseconds = stopDelayNanoseconds
    }

    func start(port _: Int, handler: @escaping @Sendable (String) async -> CallbackReply) async throws {
        self.handler = handler
    }

    func stop() async {
        try? await Task.sleep(nanoseconds: stopDelayNanoseconds)
        stopped = true
    }

    /// Drive a request as a browser would, mid-teardown.
    func deliver(_ target: String) async -> CallbackReply {
        guard let handler else { return CallbackReply(status: 0, contentType: nil, body: "") }
        return await handler(target)
    }
}

@Suite("R5 auth — cleanup's re-entrancy window", .serialized)
struct AuthCleanupRaceTests {
    @Test("a callback landing during cleanup's teardown cannot resume the observer twice")
    func callbackDuringCleanupDoesNotDoubleResume() async throws {
        let coordinator = AuthFlowCoordinator()
        let slow = SlowStopListener()
        _ = try await coordinator.begin(
            server: JSString("alpha"), listener: slow, transport: FakeAuthTransport(),
            port: 8880, authorizationURL: { "https://a.example" }
        )

        let settled = SettledFlag()
        Task {
            do {
                try await coordinator.awaitCompletion(server: JSString("alpha"))
                await settled.set("resolved")
            } catch is AuthAbandoned {
                await settled.set("abandoned")
            } catch {
                await settled.set("rejected:\((error as? AuthFailure)?.message ?? "?")")
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // Supersede. This enters `cleanup(alpha)` and suspends inside the slow `stop()`.
        let superseding = Task {
            _ = try? await coordinator.begin(
                server: JSString("beta"), listener: SlowStopListener(stopDelayNanoseconds: 0),
                transport: FakeAuthTransport(), port: 8880,
                authorizationURL: { "https://b.example" }
            )
        }
        try await Task.sleep(nanoseconds: 60_000_000)

        // The browser's callback lands on alpha's still-bound socket, mid-teardown. With `current`
        // cleared only *after* the teardown awaits, this passes cleanup's own guard, settles the
        // flow, and leaves the first cleanup holding a stale copy of the same continuation — which
        // it then resumes a second time. A `CheckedContinuation` resumed twice traps the process,
        // so the red signal for this test is the whole run dying, not an expectation failing.
        _ = await slow.deliver("/callback?code=late")
        await superseding.value
        try await Task.sleep(nanoseconds: 300_000_000)

        // Exactly one outcome, and it is the one B85 requires of a superseded flow.
        let outcome = await settled.value()
        #expect(outcome == "abandoned")
        let live = await coordinator.currentFlow()
        #expect(live?.server == JSString("beta"))
    }

    @Test("an observer registering during that window is told the truth, not stranded")
    func observerRegisteringDuringCleanupIsNotStranded() async throws {
        let coordinator = AuthFlowCoordinator()
        let slow = SlowStopListener()
        _ = try await coordinator.begin(
            server: JSString("alpha"), listener: slow, transport: FakeAuthTransport(),
            port: 8880, authorizationURL: { "https://a.example" }
        )

        let superseding = Task {
            _ = try? await coordinator.begin(
                server: JSString("beta"), listener: SlowStopListener(stopDelayNanoseconds: 0),
                transport: FakeAuthTransport(), port: 8880,
                authorizationURL: { "https://b.example" }
            )
        }
        try await Task.sleep(nanoseconds: 60_000_000)

        // Mid-teardown. The caller must get an answer rather than a continuation nobody holds —
        // a dropped continuation suspends its task forever and prints CONTINUATION MISUSE.
        let settled = SettledFlag()
        let observer = Task {
            do {
                try await coordinator.awaitCompletion(server: JSString("alpha"))
                await settled.set("resolved")
            } catch is AuthAbandoned {
                await settled.set("abandoned")
            } catch {
                await settled.set("rejected:\((error as? AuthFailure)?.message ?? "?")")
            }
        }
        _ = await observer.value
        await superseding.value

        let outcome = await settled.value()
        #expect(outcome == "rejected:no authorization is in flight")
    }
}
