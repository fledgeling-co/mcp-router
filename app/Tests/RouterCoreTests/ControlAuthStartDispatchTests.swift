import Foundation
import Testing
@testable import RouterCore

/// `POST /servers/:name/auth`, **through `ControlHandler.handle`**.
///
/// Same discipline as the approve suite: every case builds a `ControlDeps`, calls the handler and
/// asserts on the `ControlAPIResponse`. `AuthRoutesTests` proves
/// ``AuthRoutes/authStart(server:isStdio:sink:begin:awaitCompletion:)`` in isolation and was green
/// for the whole life of `D-j`, because the function was never the problem — the missing dispatch
/// arm was.
struct ControlAuthStartDispatchTests {
    typealias Support = ControlAuthSupport

    // MARK: - A5 — the stdio refusal

    @Test("A5 — stdio auth is 400 and begins no flow")
    func stdioAuthIs400AndStartsNothing() async throws {
        let calls = AuthDispatchCalls()
        var deps = try Support.makeDeps(
            calls: calls, starter: Support.StubStarter(calls: calls, termination: .authorized)
        )

        let (status, body) = await Support.answer("/servers/p1-stdio/auth", &deps)
        #expect(status == 400)
        #expect(
            body == #"{"error":"stdio servers do not authorize; their credentials are env vars"}"#
        )
        #expect(calls.beginCount == 0, "the refusal must precede any flow")
        #expect(calls.order.isEmpty, "and no side effect of any kind")

        // "No port is bound" is NOT asserted here, and the honest reason is worth writing down: an
        // earlier draft allocated a recording listener, passed it to nothing, and asserted it had
        // bound nothing — true by construction, and green against any implementation whatsoever.
        // The claim is structural instead. The only thing in this path that can bind a port is
        // `AuthFlowCoordinator`, reached solely through the `begin` closure, and `beginCount == 0`
        // above is the observable that a binding implementation would have to break first.
    }

    @Test("the stdio refusal does not need a starter either")
    func stdioAuthWithNoStarterIsStill400() async throws {
        var deps = try Support.makeDeps(starter: nil)
        let (status, _) = await Support.answer("/servers/p1-stdio/auth", &deps)
        #expect(status == 400, "authStart refuses stdio before any flow begins, starter or not")
    }

    // MARK: - A6 to A9 — the non-stdio path and its four terminations

    @Test("A6 — http auth with a starter is 200 with the authorization URL")
    func httpAuthWithAStarterIs200() async throws {
        let calls = AuthDispatchCalls()
        let starter = Support.StubStarter(calls: calls, termination: .authorized)
        var deps = try Support.makeDeps(calls: calls, starter: starter)

        let (status, body) = await Support.answer("/servers/p1-http/auth", &deps)
        #expect(status == 200)
        #expect(body == #"{"server":"p1-http","authorizationUrl":"\#(starter.url)"}"#)
        #expect(calls.beginCount == 1)
    }

    @Test("A7 — success clears the pending marker, THEN re-indexes the captured upstream")
    func successClearsPendingThenReindexes() async throws {
        let calls = AuthDispatchCalls()
        var deps = try Support.makeDeps(
            calls: calls, starter: Support.StubStarter(calls: calls, termination: .authorized)
        )

        let (status, _) = await Support.answer("/servers/p1-http/auth", &deps)
        #expect(status == 200)

        try await Support.settle { calls.order.contains("index") }
        #expect(
            calls.order == ["begin", "clearPending", "index"],
            "order is the contract, not the set"
        )
        #expect(calls.indexed == ["p1-http"], "the upstream captured at request time, not another")
    }

    @Test("A8 — a rejection warns once and does nothing else")
    func rejectionWarnsAndDoesNothingElse() async throws {
        let calls = AuthDispatchCalls()
        let sink = RecordingSink()
        var deps = try Support.makeDeps(
            calls: calls,
            starter: Support.StubStarter(
                calls: calls, termination: .rejected("the user closed the tab")
            ),
            log: RouterLog(sink: sink)
        )

        let (status, _) = await Support.answer("/servers/p1-http/auth", &deps)
        #expect(status == 200, "the 200 is sent before the flow terminates, either way")

        try await Support.settle { sink.text.contains("did not complete") }
        #expect(
            sink.text.contains(
                #"authorization for "p1-http" did not complete: the user closed the tab"#
            ),
            "B79's line, verbatim; got: \(sink.text)"
        )
        #expect(
            !calls.order.contains("clearPending"),
            "a server still waiting on authorization stays pending"
        )
        #expect(!calls.order.contains("index"))
    }

    @Test("A9 — a superseded flow is silent: no line, no clearPending, no re-index (B85)")
    func abandonmentIsSilent() async throws {
        let calls = AuthDispatchCalls()
        let sink = RecordingSink()
        var deps = try Support.makeDeps(
            calls: calls,
            starter: Support.StubStarter(calls: calls, termination: .abandoned),
            log: RouterLog(sink: sink)
        )

        let (status, _) = await Support.answer("/servers/p1-http/auth", &deps)
        #expect(status == 200)

        // Nothing to wait FOR, so a fixed settle is the right instrument here rather than a poll:
        // this asserts a state STAYS put, and a poll would return the instant it first held.
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(
            sink.text.isEmpty,
            "the reference runs neither .then nor .catch here; got: \(sink.text)"
        )
        #expect(!calls.order.contains("clearPending"))
        #expect(!calls.order.contains("index"))
    }

    @Test("a begin that throws is 502, carrying the reason")
    func beginFailureIs502ThroughTheHandler() async throws {
        let calls = AuthDispatchCalls()
        var deps = try Support.makeDeps(
            calls: calls,
            starter: Support.StubStarter(
                calls: calls, termination: .beginFails("the callback port is in use")
            )
        )

        let (status, body) = await Support.answer("/servers/p1-http/auth", &deps)
        #expect(status == 502)
        #expect(body == #"{"error":"the callback port is in use"}"#)
    }

    // MARK: - A10 — the declared gap

    @Test("A10 — http auth with NO starter stays 405, which is now ControlDiff's case alone")
    func httpAuthWithNoStarterIs405() async throws {
        var deps = try Support.makeDeps(starter: nil)
        let (status, body) = await Support.answer("/servers/p1-http/auth", &deps)

        // Deliberately not 502. The reference's 502 means `beginAuth` RAN and threw; reusing it for
        // "no starter was ever constructed" makes two different failures indistinguishable, and
        // puts the caller in the retryable class for something that can never succeed.
        //
        // P7 closed `D-p1-a`, so the DAEMON always has a starter and this branch is no longer what
        // the wire answers — `parity-oauth.sh` compares the 200 and the whole flow behind it.
        // `ControlDiff` still supplies no starter, so this case is still reachable and still has to
        // answer this way.
        #expect(status == 405)
        #expect(body == #"{"error":"POST not allowed on /servers/p1-http/auth"}"#)
    }

    // MARK: - A11 — the gates in front of the route

    @Test("A11 — an unknown server is 404 on auth, before the route runs")
    func unknownServerOnAuthIs404() async throws {
        let calls = AuthDispatchCalls()
        var deps = try Support.makeDeps(
            calls: calls, starter: Support.StubStarter(calls: calls, termination: .authorized)
        )
        let (status, body) = await Support.answer("/servers/ghost/auth", &deps)
        #expect(status == 404)
        #expect(body == #"{"error":"no server named \"ghost\""}"#)
        #expect(calls.beginCount == 0)
    }

    @Test("A11 — an untokened auth is 401, ahead of the 404")
    func untokenedAuthIs401() async throws {
        var deps = try Support.makeDeps()
        for path in ["/servers/p1-http/auth", "/servers/ghost/auth"] {
            let (status, _) = await Support.answer(path, &deps, authorized: false)
            #expect(status == 401, "\(path)")
        }
    }

    // MARK: - the DELETE sibling, which moved files in this change

    @Test("DELETE /servers/:name/auth still answers after moving into the auth dispatch table")
    func deleteAuthSurvivedTheMove() async throws {
        let calls = AuthDispatchCalls()
        var deps = try Support.makeDeps(calls: calls)
        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: "DELETE", encodedPath: "/servers/p1-stdio/auth",
                query: [], headers: [(name: "x-mcpr-token", value: Support.token)], body: nil
            ),
            &deps
        )
        #expect(response.status == 200)
        guard case let .bytes(bytes) = response.body else {
            Issue.record("no body")
            return
        }
        // swiftlint:disable:next optional_data_string_conversion
        #expect(String(decoding: bytes, as: UTF8.self) == #"{"server":"p1-stdio","signedOut":false}"#)
        #expect(calls.order == ["clearPending"], "and it still clears the pending marker")
    }
}
