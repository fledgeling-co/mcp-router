import Foundation
import Testing
@testable import RouterCore

/// F6 — `GET /extensions/updates`, **through `ControlHandler.handle`**.
///
/// Through the handler rather than by calling the response builder, for the reason
/// `ControlExtensionRoutesTests` gives: `D-j` was never a broken function, it was a missing
/// dispatch arm, and a test that calls the function cannot fail when the arm is deleted. This
/// route has a sharper version of that problem — `/extensions/updates` and `/extensions/:kind`
/// collide by shape, so a dispatch in the wrong order answers
/// `404 no extension kind named "updates"` while every unit of the report stays green.
///
/// The daemon's own wiring is a third thing again, and neither of those can see it missing —
/// `scripts/acceptance/f6-updates.sh` drives the socket for that.
@Suite("F6 control route")
struct ControlUpdateRoutesTests {
    typealias Support = ControlAuthSupport

    private static func store() -> DiskExtensionStore {
        DiskExtensionStore(
            root: NSTemporaryDirectory() + "mcprouter-f6-routes-" + UUID().uuidString,
            clock: FixedMillisecondClock(1000)
        )
    }

    /// Written with `FileManager` rather than through `add`, and that is the subject rather than
    /// convenience. `add` refuses a descriptor whose `name` differs from the entry name, and the
    /// real store cannot satisfy it: R30 stores a plugin under `<plugin>@<marketplace>` while the
    /// `plugin.json` Claude wrote says `<plugin>`, which is why R30 uses `adopt` and not `add`. A
    /// fixture built through `add` would be a shape the product never holds.
    private static func write(
        _ store: DiskExtensionStore, _ kind: ExtensionKind, _ name: String, _ text: String
    ) {
        let entry = ((store.root as NSString).appendingPathComponent(kind.rawValue) as NSString)
            .appendingPathComponent(name)
        let descriptor = (entry as NSString).appendingPathComponent(kind.descriptorPath)
        try? FileManager.default.createDirectory(
            atPath: (descriptor as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? text.write(toFile: descriptor, atomically: true, encoding: .utf8)
    }

    private static func stocked(_ store: DiskExtensionStore) {
        write(store, .marketplaces, "mkt",
              #"{"name":"mkt","plugins":[{"name":"a","version":"2.0.0"},{"name":"b"}]}"#)
        write(store, .plugins, "a@mkt", #"{"name":"a","version":"1.0.0"}"#)
        write(store, .plugins, "b@mkt", #"{"name":"b","version":"1.0.0"}"#)
        write(store, .skills, "s", "---\nname: s\ndescription: a skill\n---\n")
    }

    private static func answer(
        _ path: String,
        method: String = "GET",
        query: [(name: String, value: String)] = [],
        _ deps: inout ControlDeps
    ) async -> (status: Int, body: String) {
        // The content type is sent on every call, including the GETs where it is ignored. Without
        // it a POST is refused 415 before dispatch, which would let U4 pass against a router that
        // routed the write perfectly well once a caller sent a header.
        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: method, encodedPath: path, query: query,
                headers: [
                    (name: "content-type", value: "application/json"),
                    (name: "x-mcpr-token", value: Support.token)
                ],
                body: nil
            ),
            &deps
        )
        guard case let .bytes(bytes) = response.body else { return (response.status, "") }
        // swiftlint:disable:next optional_data_string_conversion
        return (response.status, String(decoding: bytes, as: UTF8.self))
    }

    // MARK: - The route exists, and is reached before the :kind match

    /// Both directions. The route answering is half the assertion; the other half is that
    /// `/extensions/nonsense` STILL 404s as a kind, so this arm cannot be satisfied by a dispatch
    /// that swallows every path under `/extensions/`.
    @Test("U1 — /extensions/updates is claimed before :kind, and :kind still refuses a bad name")
    func routedAheadOfKind() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store
        Self.stocked(store)

        let updates = await Self.answer("/extensions/updates", &deps)
        #expect(updates.status == 200)
        #expect(updates.body.contains(#""summary":"#))
        #expect(!updates.body.contains("no extension kind named"))

        let nonsense = await Self.answer("/extensions/nonsense", &deps)
        #expect(nonsense.status == 404)
        #expect(nonsense.body.contains(#"no extension kind named \"nonsense\""#))
    }

    @Test("U2 — the report carries the four verdicts the fixture puts in it")
    func verdicts() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store
        Self.stocked(store)

        let answer = await Self.answer("/extensions/updates", &deps)
        #expect(answer.status == 200)
        #expect(answer.body.contains(#""state":"update-available""#))
        #expect(answer.body.contains(#""state":"catalogue-declares-no-version""#))
        #expect(answer.body.contains(#""state":"no-catalogue""#))
        #expect(answer.body.contains(#""updatesAvailable":1"#))
        // compared + uncomparable == total, on the wire. Four rows: two plugins, one skill, one
        // marketplace.
        #expect(answer.body.contains(#""total":4"#))
        #expect(answer.body.contains(#""compared":1"#))
        #expect(answer.body.contains(#""uncomparable":3"#))
    }

    /// A15's shape: an unobserved figure is `null`, never `0`. A zero age reads as *just
    /// refreshed*, which would make every verdict taken against a missing catalogue look checked.
    @Test("U3 — a catalogue block carries its age, and null rather than zero when it has none")
    func catalogueAges() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store
        Self.write(store, .plugins, "x@gone", #"{"name":"x","version":"1.0.0"}"#)

        let answer = await Self.answer("/extensions/updates", &deps)
        #expect(answer.body.contains(#""name":"gone""#))
        #expect(answer.body.contains(#""ageMs":null"#))
        #expect(answer.body.contains(#""newestModifiedMs":null"#))
        #expect(answer.body.contains(#""stale":false"#))
        #expect(answer.body.contains(#""refreshable":false"#))
    }

    // MARK: - Read-only by construction

    /// A3 of the spec. There is no mutating verb in this family, so `handle` answers its own 405 —
    /// the honest reply for a path `isControlPath` claims and this router does not route for that
    /// method.
    ///
    /// **405 rather than 404 is the assertion, and it caught a real defect.** Before
    /// `routeExtensions` was taught to decline `/extensions/updates`, a `DELETE` on it fell through
    /// to the `:kind` match and answered `404 no extension kind named "updates"` — a reply that
    /// denies the existence of a path the router serves. A test asserting only "did not act" would
    /// have passed over it.
    @Test(
        "U4 — every mutating verb is 405, not 404 and not an action",
        arguments: ["POST", "PUT", "PATCH", "DELETE"]
    )
    func readOnly(method: String) async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store
        Self.stocked(store)

        let before = store.list(.plugins).records.count
        let answer = await Self.answer("/extensions/updates", method: method, &deps)
        #expect(answer.status == 405)
        #expect(store.list(.plugins).records.count == before)
    }

    // MARK: - The parameters

    @Test("U5 — kind narrows the rows, and an unknown kind is refused")
    func kindFilter() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store
        Self.stocked(store)

        let plugins = await Self.answer(
            "/extensions/updates", query: [(name: "kind", value: "plugins")], &deps
        )
        #expect(plugins.status == 200)
        #expect(plugins.body.contains(#""total":2"#))

        let bad = await Self.answer(
            "/extensions/updates", query: [(name: "kind", value: "widgets")], &deps
        )
        #expect(bad.status == 404)
    }

    /// A window that cannot be read is refused rather than silently replaced by the default. A
    /// caller who typed `staleAfterMs=1h` asked a question, and answering the default one would
    /// report every catalogue fresh against a window they did not choose.
    @Test(
        "U6 — an unreadable staleAfterMs is a 400, and an absent one takes the default",
        arguments: ["1h", "-1", "abc", "1.5", ""]
    )
    func staleWindowRefused(raw: String) async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store
        Self.stocked(store)

        let refused = await Self.answer(
            "/extensions/updates", query: [(name: "staleAfterMs", value: raw)], &deps
        )
        #expect(refused.status == 400)
        #expect(refused.body.contains("staleAfterMs"))

        let defaulted = await Self.answer("/extensions/updates", &deps)
        #expect(defaulted.status == 200)
        #expect(defaulted.body.contains(#""staleAfterMs":86400000"#))
    }

    /// A negative age is not a young one.
    ///
    /// This suite's clock is fixed (`ControlAuthSupport`), and the fixture's files carry the real
    /// filesystem's own mtime — so the catalogue is stamped **ahead** of the router's clock, which
    /// is the skew case in miniature. Reported as a number it would be a large negative `ageMs`
    /// that no window can exceed, and the catalogue would read as fresh forever. It is `null` with
    /// the reason instead, and `staleAfterMs=0` — a window nothing measurable can satisfy — is what
    /// makes that visible: even at zero this catalogue is not counted stale, because its age was
    /// never taken.
    @Test("U7 — a catalogue stamped ahead of the clock has a null age, not a negative one")
    func futureStampedCatalogue() async throws {
        var deps = try Support.makeDeps()
        let store = Self.store()
        defer { try? FileManager.default.removeItem(atPath: store.root) }
        deps.extensions = store
        Self.stocked(store)

        let answer = await Self.answer(
            "/extensions/updates", query: [(name: "staleAfterMs", value: "0")], &deps
        )
        #expect(answer.status == 200)
        #expect(answer.body.contains(#""ageMs":null"#))
        #expect(!answer.body.contains(#""ageMs":-"#))
        #expect(answer.body.contains("stamped ahead of this router's clock"))
        // The catalogue still read, so nothing it offers is suppressed.
        #expect(answer.body.contains(#""problem":null"#))
        #expect(answer.body.contains(#""staleCatalogues":0"#))
        // And the verdict is untouched by any of it — an unknown age puts a sentence beside an
        // answer, it does not replace one.
        #expect(answer.body.contains(#""state":"update-available""#))
    }

    // MARK: - The dependency

    /// `ControlDeps.extensions` is optional exactly as `registry` and `authFlow` are, and both of
    /// those shipped nil in `RouterServiceDispatch` with a green suite. Absent, the route names the
    /// missing capability rather than answering an empty report — which a router holding nothing
    /// would be indistinguishable from.
    @Test("U8 — no store is a 503 that names the capability, not an empty report")
    func noStore() async throws {
        var deps = try Support.makeDeps()
        deps.extensions = nil
        let answer = await Self.answer("/extensions/updates", &deps)
        #expect(answer.status == 503)
        #expect(answer.body.contains("extension storage is unavailable"))
        #expect(!answer.body.contains(#""summary""#))
    }
}
