import Foundation
import Testing
@testable import RouterCore

/// R28 — the `/extensions` family, **through `ControlHandler.handle`**.
///
/// Through the handler rather than by calling the response builders, for the reason
/// `ControlBoardRoutesTests` gives in its own words: `D-j` was never a broken function, it was a
/// missing dispatch arm, and a test that calls the function cannot fail when the arm is deleted.
/// The daemon's own wiring is a third thing again, and neither of those can see it missing —
/// `scripts/acceptance/r28-extensions.sh` drives the socket for that.
@Suite("R28 control routes")
struct ControlExtensionRoutesTests {
    typealias Support = ControlAuthSupport

    /// A scratch store per test. Real, for the reason ``ExtensionStoreTests`` states.
    private static func store() -> DiskExtensionStore {
        DiskExtensionStore(
            root: NSTemporaryDirectory() + "mcprouter-r28-routes-" + UUID().uuidString,
            clock: FixedMillisecondClock(1000)
        )
    }

    private static let skillBody = """
    {"name":"alpha","files":[{"path":"SKILL.md",\
    "text":"---\\nname: alpha\\ndescription: a test skill\\n---\\n"}]}
    """

    private static func answer(
        _ path: String,
        method: String = "GET",
        body: String? = nil,
        authorized: Bool = true,
        contentType: Bool = true,
        _ deps: inout ControlDeps
    ) async -> (status: Int, body: String) {
        var headers: [(name: String, value: String)] = []
        if contentType { headers.append((name: "content-type", value: "application/json")) }
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

    // MARK: - The family answers at all

    @Test("R1 — a kind is added, listed, read and removed over the routes")
    func roundTripOverTheWire() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store

        let added = await Self.answer(
            "/extensions/skills", method: "POST", body: Self.skillBody, &deps
        )
        #expect(added.status == 201)
        #expect(added.body == #"{"added":"alpha","kind":"skills","files":1,"bytes":46}"#)

        let listed = await Self.answer("/extensions/skills", &deps)
        #expect(listed.status == 200)
        #expect(listed.body.contains(#""count":1"#))
        #expect(listed.body.contains(#""name":"alpha""#))
        #expect(listed.body.contains(#""description":"a test skill""#))
        #expect(listed.body.contains(#""problem":null"#))

        let one = await Self.answer("/extensions/skills/alpha", &deps)
        #expect(one.status == 200)
        #expect(one.body.contains(#""title":"alpha""#))

        let removed = await Self.answer("/extensions/skills/alpha", method: "DELETE", &deps)
        #expect(removed.status == 200)
        #expect(removed.body.contains(#""removed":"alpha""#))
        #expect(removed.body.contains(#""restorePath":"#))

        let empty = await Self.answer("/extensions/skills", &deps)
        #expect(empty.body.contains(#""count":0"#))
        // The staging area is the store's workspace and outlives an add; what must never survive
        // is an entry inside it.
        let staged = (try? FileManager.default.contentsOfDirectory(
            atPath: store.root + "/.staging"
        )) ?? []
        #expect(staged.isEmpty)
    }

    @Test("R2 — one request answers all four kinds with a count each")
    func inventoryCoversFourKinds() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store
        _ = await Self.answer("/extensions/skills", method: "POST", body: Self.skillBody, &deps)

        let inventory = await Self.answer("/extensions", &deps)
        #expect(inventory.status == 200)
        // The two servers are the fixture's, read from the same live map `GET /servers` reads, so
        // the two routes cannot disagree about how many there are.
        #expect(inventory.body.hasPrefix(
            #"{"counts":{"servers":2,"skills":1,"plugins":0,"marketplaces":0}"#
        ))
        for kind in ExtensionKind.allCases {
            #expect(inventory.body.contains(#""kind":"\#(kind.rawValue)""#))
        }
    }

    // MARK: - Refusals

    @Test("R3 — a malformed add is refused with its reason and registers nothing")
    func malformedAddIsRefused() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store

        let refused = await Self.answer(
            "/extensions/skills", method: "POST",
            body: #"{"name":"alpha","files":[{"path":"SKILL.md","text":"no frontmatter"}]}"#,
            &deps
        )
        #expect(refused.status == 400)
        #expect(refused.body.contains(#""reason":"malformedDescriptor""#))

        let escape = await Self.answer(
            "/extensions/skills", method: "POST",
            body: #"{"name":"alpha","files":[{"path":"../out.md","text":"x"}]}"#, &deps
        )
        #expect(escape.status == 400)
        #expect(escape.body.contains(#""reason":"invalidFilePath""#))

        // Half-registered is what the ordering exists to prevent, and this is the assertion that
        // would see it: after two refusals the collection is still empty.
        let listed = await Self.answer("/extensions/skills", &deps)
        #expect(listed.body.contains(#""count":0"#))
    }

    @Test("R4 — a body with no name, and one with no files, are each refused")
    func bodyShapeIsRefused() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store

        let noName = await Self.answer(
            "/extensions/skills", method: "POST", body: #"{"files":[]}"#, &deps
        )
        #expect(noName.status == 400)
        #expect(noName.body == #"{"error":"name is required"}"#)

        let noFiles = await Self.answer(
            "/extensions/skills", method: "POST", body: #"{"name":"alpha"}"#, &deps
        )
        #expect(noFiles.status == 400)
        #expect(noFiles.body == #"{"error":"files is required, as an array of {path, text}"}"#)
    }

    @Test("R5 — an unknown kind is 404, an unknown entry is 404 in the route's own words")
    func unknownsAre404() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store

        let kind = await Self.answer("/extensions/widgets", &deps)
        #expect(kind.status == 404)
        #expect(kind.body == #"{"error":"no extension kind named \"widgets\""}"#)

        let entry = await Self.answer("/extensions/plugins/ghost", &deps)
        #expect(entry.status == 404)
        #expect(entry.body == #"{"error":"no plugin named \"ghost\""}"#)

        let removal = await Self.answer("/extensions/plugins/ghost", method: "DELETE", &deps)
        #expect(removal.status == 404)
        #expect(removal.body.contains(#""reason":"unknown""#))
    }

    @Test("R6 — a method the family does not serve is 405, not 404")
    func wrongMethodIs405() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store

        // `isControlPath` claims the path, so "the method is wrong" is the true answer.
        let patched = await Self.answer("/extensions/skills", method: "PATCH", body: "{}", &deps)
        #expect(patched.status == 405)
        let deeper = await Self.answer("/extensions/skills/alpha/extra", &deps)
        #expect(deeper.status == 405)
    }

    // MARK: - The gates in front of it

    @Test("R7 — an untokened mutation is 401 and one without JSON is 415")
    func mutationsAreGated() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store

        let untokened = await Self.answer(
            "/extensions/skills", method: "POST", body: Self.skillBody, authorized: false, &deps
        )
        #expect(untokened.status == 401)

        let unTyped = await Self.answer(
            "/extensions/skills", method: "POST", body: Self.skillBody, contentType: false, &deps
        )
        #expect(unTyped.status == 415)

        let listed = await Self.answer("/extensions/skills", &deps)
        #expect(listed.body.contains(#""count":0"#))
    }

    @Test("R8 — with no store the family says so rather than answering an empty inventory")
    func absentStoreIsDeclared() async throws {
        var deps = try Support.makeDeps()
        deps.extensions = nil
        for path in ["/extensions", "/extensions/skills", "/extensions/skills/alpha"] {
            let answer = await Self.answer(path, &deps)
            #expect(answer.status == 503)
            #expect(answer.body.contains("extension storage is unavailable"))
        }
    }

    @Test("R9 — a name arrives percent-decoded, and a malformed escape is 400")
    func namesAreDecoded() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store
        _ = await Self.answer("/extensions/skills", method: "POST", body: Self.skillBody, &deps)

        let encoded = await Self.answer("/extensions/skills/%61lpha", &deps)
        #expect(encoded.status == 200)
        #expect(encoded.body.contains(#""name":"alpha""#))

        let malformed = await Self.answer("/extensions/skills/%ZZ", &deps)
        #expect(malformed.status == 400)
        #expect(malformed.body == #"{"error":"URI malformed"}"#)
    }
}
