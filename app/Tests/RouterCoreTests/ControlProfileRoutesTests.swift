import Foundation
import Testing
@testable import RouterCore

/// F8 — the `/profiles` family, **through `ControlHandler.handle`**.
///
/// Through the handler rather than by calling the response builders, for the reason
/// `ControlExtensionRoutesTests` gives: `D-j` was never a broken function, it was a missing
/// dispatch arm, and a test that calls the function cannot fail when the arm is deleted. The
/// daemon's own wiring is a third thing again and neither of those can see it missing —
/// `scripts/acceptance/f8-profiles.sh` drives the socket for that.
@Suite("F8 control routes")
struct ControlProfileRoutesTests {
    typealias Support = ControlAuthSupport

    private static func store() -> DiskProfileStore {
        DiskProfileStore(
            root: NSTemporaryDirectory() + "mcprouter-f8-routes-" + UUID().uuidString,
            clock: FixedMillisecondClock(1000)
        )
    }

    private static func extensionStore(skills: [String]) -> DiskExtensionStore {
        let store = DiskExtensionStore(
            root: NSTemporaryDirectory() + "mcprouter-f8-ext-" + UUID().uuidString,
            clock: FixedMillisecondClock(1000)
        )
        for name in skills {
            _ = store.add(.skills, name: name, files: [ExtensionFile(
                path: "SKILL.md", text: "---\nname: \(name)\ndescription: a skill\n---\n"
            )])
        }
        return store
    }

    private static func answer(
        _ path: String,
        method: String = "GET",
        body: String? = nil,
        authorized: Bool = true,
        _ deps: inout ControlDeps
    ) async -> (status: Int, body: String) {
        var headers = [
            (name: "content-type", value: "application/json")
        ]
        if authorized { headers.append((name: "x-mcpr-token", value: Support.token)) }
        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: method, encodedPath: path, query: [], headers: headers,
                body: body.map { Data($0.utf8) }
            ),
            &deps
        )
        guard case let .bytes(bytes) = response.body else { return (response.status, "") }
        // swiftlint:disable:next optional_data_string_conversion
        return (response.status, String(decoding: bytes, as: UTF8.self))
    }

    @Test("C1 — a profile is written, listed, read and removed over the routes")
    func roundTripOverTheWire() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.profiles = store

        let empty = await Self.answer("/profiles", &deps)
        #expect(empty.status == 200)
        #expect(empty.body.contains(#""count":0"#))
        #expect(empty.body.contains(#""unreadable":null"#))

        let written = await Self.answer(
            "/profiles/frontend", method: "POST",
            body: #"{"title":"Frontend Dev","skills":["design-craft"],"servers":["github"]}"#, &deps
        )
        #expect(written.status == 200)
        #expect(written.body.contains(#""name":"frontend""#))
        #expect(written.body.contains(#""skills":["design-craft"]"#))

        let listed = await Self.answer("/profiles", &deps)
        #expect(listed.body.contains(#""count":1"#))
        #expect(listed.body.contains(#""problem":null"#))

        let one = await Self.answer("/profiles/frontend", &deps)
        #expect(one.status == 200)
        #expect(one.body.contains(#""title":"Frontend Dev""#))

        let removed = await Self.answer("/profiles/frontend", method: "DELETE", &deps)
        #expect(removed.status == 200)
        #expect(removed.body.contains(#""restorePath""#))
        #expect(await Self.answer("/profiles/frontend", &deps).status == 404)
    }

    /// The absence of the store is a **named capability**, not an empty list.
    ///
    /// The control is in the same test: with the store supplied the same request is 200, so a route
    /// that answered 503 unconditionally would fail here.
    @Test("C2 — with no store every route says which capability is missing")
    func absentStoreIs503() async throws {
        var deps = try Support.makeDeps()
        deps.profiles = nil
        let refused = await Self.answer("/profiles", &deps)
        #expect(refused.status == 503)
        #expect(refused.body.contains("no profile store"))

        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.profiles = store
        #expect(await Self.answer("/profiles", &deps).status == 200)
    }

    /// The projection needs two more dependencies, and each absence is reported on its own.
    @Test("C3 — the projection names whichever of its two dependencies is missing")
    func projectionReportsEachAbsence() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.profiles = store
        _ = await Self.answer("/profiles/p", method: "POST", body: #"{"skills":["s"]}"#, &deps)

        deps.extensions = nil
        deps.skillRoots = FixtureSkillRoots(roots: [], absent: [])
        let noStore = await Self.answer("/profiles/p/projection", &deps)
        #expect(noStore.status == 503)
        #expect(noStore.body.contains("extension storage"))

        deps.extensions = Self.extensionStore(skills: [])
        deps.skillRoots = nil
        let noRoots = await Self.answer("/profiles/p/projection", &deps)
        #expect(noRoots.status == 503)
        #expect(noRoots.body.contains("skill roots"))
    }

    /// The projection body says `applies: false`, and it carries the reach counts.
    @Test("C4 — the projection reports its reach split and that it applies nothing")
    func projectionBody() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        let extensions = Self.extensionStore(skills: ["design-craft"])
        defer {
            try? FileManager.default.removeItem(atPath: store.root)
            try? FileManager.default.removeItem(atPath: extensions.root)
        }
        deps.profiles = store
        deps.extensions = extensions
        deps.skillRoots = FixtureSkillRoots(
            roots: [SkillRootInventory(
                client: .cursor, path: "/scratch/skills", exists: true,
                entries: [SkillEntry(
                    name: "design-craft", kind: .dangling(target: "/gone/design-craft")
                )]
            )],
            absent: [.grokCLI]
        )
        _ = await Self.answer(
            "/profiles/p", method: "POST",
            body: #"{"skills":["design-craft"],"servers":["fixture-stdio"]}"#, &deps
        )

        let projected = await Self.answer("/profiles/p/projection", &deps)
        #expect(projected.status == 200)
        #expect(projected.body.contains(#""applies":false"#))
        #expect(projected.body.contains(#""stepCount":2"#))
        #expect(projected.body.contains(#""durable":1"#))
        #expect(projected.body.contains(#""tell-elsewhere":1"#))
        #expect(projected.body.contains(#""refused":0"#))
        #expect(projected.body.contains(#""action":"repair""#))
        #expect(projected.body.contains(#""target":"/gone/design-craft""#))
        #expect(projected.body.contains(#""withoutSkillRoot":["grokCLI"]"#))
    }

    /// The gates in front of the family, and a sub-path it does not serve.
    @Test("C5 — the token, the method and an unserved sub-path")
    func gatesAndFallthrough() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.profiles = store

        // Stage 2 precedes the store lookup, so an untokened POST is 401 and not 404.
        let untokened = await Self.answer(
            "/profiles/p", method: "POST", body: "{}", authorized: false, &deps
        )
        #expect(untokened.status == 401)

        // `PATCH` is not served on an item, and the path IS claimed, so "the method is wrong" is
        // the true answer rather than "no such route".
        #expect(await Self.answer("/profiles/p", method: "PATCH", body: "{}", &deps).status == 405)
        #expect(await Self.answer("/profiles/p/nothing", &deps).status == 405)

        // A member of the wrong shape is a refusal, not an empty selection.
        let wrongShape = await Self.answer(
            "/profiles/p", method: "POST", body: #"{"skills":"design-craft"}"#, &deps
        )
        #expect(wrongShape.status == 400)
        #expect(wrongShape.body.contains("skills must be an array of strings"))

        // A name that escapes the store is refused with its slug beside the sentence.
        let escaping = await Self.answer(
            "/profiles/..%2Fescape", method: "POST", body: "{}", &deps
        )
        #expect(escaping.status == 400)
        #expect(escaping.body.contains(#""reason":"bad-name""#))
    }

    /// The invariant the C5 failure taught, held for whoever adds the next route here.
    ///
    /// `ControlAPIRequest.isMutating` is `POST || DELETE || PATCH` and **PUT is not in it**, so a
    /// route in this family that served PUT would serve it unauthenticated. This asserts that no
    /// method outside the gate's set gets a 2xx without a token — and its control is the same call
    /// with a token, which must still be refused by the router rather than merely by the gate.
    @Test(
        "C6 — no method outside the token gate's set is served here",
        arguments: ["PUT", "HEAD", "OPTIONS", "TRACE"]
    )
    func ungatedMethodsAreNotServed(method: String) async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.profiles = store

        let untokened = await Self.answer(
            "/profiles/p", method: method, body: "{}", authorized: false, &deps
        )
        #expect(untokened.status >= 400)
        // The control: a POST with no token IS refused by the gate, so the assertion above is
        // about these methods rather than about the handler refusing everything.
        let gated = await Self.answer(
            "/profiles/p", method: "POST", body: "{}", authorized: false, &deps
        )
        #expect(gated.status == 401)
    }
}
