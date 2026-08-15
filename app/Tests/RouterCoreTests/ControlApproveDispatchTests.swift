import Foundation
import Testing
@testable import RouterCore

/// `POST /servers/:name/approve`, **through `ControlHandler.handle`**.
///
/// Going through the handler rather than calling
/// ``AuthRoutes/approve(server:manifestPath:fileSystem:nowMilliseconds:log:)``
/// is the point of this file rather than an incidental style choice. `AuthRoutesTests` already
/// proves that function in isolation and passed throughout the entire life of `D-j` — the defect
/// was never in the function, it was that `dispatchServer` carried no arm for it, so the wire
/// answered 405 to a route the reference answers 409. A test that calls `AuthRoutes.approve` cannot
/// fail when the dispatch arm is deleted, which makes it worthless as a guard for this item.
struct ControlApproveDispatchTests {
    typealias Support = ControlAuthSupport

    @Test("A1 — approve with no pending change is 409 through the handler")
    func approveWithNoPendingIs409() async throws {
        let (fileSystem, path) = Support.seedManifest(#"{"tools":[],"digest":"d1","builtAt":"t1"}"#)
        var deps = try Support.makeDeps(fileSystem: fileSystem, manifestPath: path)
        let (status, body) = await Support.answer("/servers/p1-stdio/approve", &deps)
        #expect(status == 409)
        #expect(body == #"{"error":"no pending change for \"p1-stdio\""}"#)
    }

    @Test("A2 — approve promotes the pending surface, and the file on disk says so")
    func approvePromotesThroughTheHandler() async throws {
        let (fileSystem, path) = Support.seedManifest("""
        {"tools":[{"name":"old"}],"digest":"d1","builtAt":"t1",\
        "pending":{"tools":[{"name":"a"},{"name":"b"}],"digest":"d2"}}
        """)
        var deps = try Support.makeDeps(fileSystem: fileSystem, manifestPath: path)

        let (status, body) = await Support.answer("/servers/p1-stdio/approve", &deps)
        #expect(status == 200)
        #expect(body == #"{"server":"p1-stdio","approved":2}"#)

        // The bytes on disk, not the reply — a route that answers correctly and writes nothing is
        // the worse of the two failures and the one a response-only assertion cannot see. The tool
        // list is read back through `ManifestIO` rather than matched as a substring, because the
        // manifest is written pretty-printed and a `"name":"a"` test would be asserting the
        // writer's whitespace rather than what it wrote.
        let written = try #require(fileSystem.memory.contents(atPath: path))
        let reloaded = ManifestIO.load(path: path, fileSystem: fileSystem).manifest
        let entry = try #require(reloaded.entry(named: "p1-stdio"))
        #expect(entry.tools.map { $0.name?.string } == ["a", "b"])
        #expect(entry.pending == nil, "pending must be removed, not emitted as null")
        #expect(!written.contains("\"pending\""), "and it must be gone from the bytes too")
        #expect(written.contains(#""digest": "d2""#))
        #expect(!written.contains("\"old\""), "the superseded tool must not survive")

        // And the surface the user reads next agrees: `/changes` now reports nothing pending. It
        // reads `deps.manifest`, the in-memory snapshot, so this also pins that the two do not
        // silently disagree after a write.
        deps.manifest = ManifestIO.load(path: path, fileSystem: fileSystem).manifest
        let changes = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: "GET", encodedPath: "/servers/p1-stdio/changes",
                query: [], headers: [], body: nil
            ),
            &deps
        )
        guard case let .bytes(bytes) = changes.body else {
            Issue.record("no body")
            return
        }
        // swiftlint:disable:next optional_data_string_conversion
        #expect(String(decoding: bytes, as: UTF8.self).contains(#""pending":false"#))
    }

    @Test("A3 — the count is taken before the write, and the manifest is read fresh from disk")
    func approveCountsBeforeTheWriteAndReadsFresh() async throws {
        // Deps are built against an entry with ONE pending tool...
        let (fileSystem, path) = Support.seedManifest("""
        {"tools":[],"digest":"d1","builtAt":"t1","pending":{"tools":[{"name":"a"}],"digest":"d2"}}
        """)
        var deps = try Support.makeDeps(fileSystem: fileSystem, manifestPath: path)
        deps.manifest = ManifestIO.load(path: path, fileSystem: fileSystem).manifest

        // ...and the file is then rewritten with THREE behind the snapshot's back. The reference
        // reads the file here and its cached copy in `/changes`; a port that shares the cache
        // answers 1 and diverges whenever the cache is stale (B88).
        fileSystem.memory.seed("""
        {
          "version": 1,
          "servers": {
            "p1-stdio": {"tools":[],"digest":"d1","builtAt":"t1",\
        "pending":{"tools":[{"name":"a"},{"name":"b"},{"name":"c"}],"digest":"d3"}}
          }
        }
        """, atPath: path)

        let (status, body) = await Support.answer("/servers/p1-stdio/approve", &deps)
        #expect(status == 200)
        #expect(
            body == #"{"server":"p1-stdio","approved":3}"#,
            "the disk state must win over the snapshot"
        )
    }

    @Test("A4 — a manifest write that fails is recorded behaviour, not an assumed success")
    func approveWithARefusingFileSystem() async throws {
        let (fileSystem, path) = Support.seedManifest("""
        {"tools":[],"digest":"d1","builtAt":"t1","pending":{"tools":[{"name":"a"}],"digest":"d2"}}
        """)
        // The keys are the FileSystem method names, not shorthand — `fail("write")` registers a
        // failure for an operation nothing performs, and this test would then pass by writing
        // successfully while claiming to have proven the refusal path.
        fileSystem.memory.fail("writeFile")
        fileSystem.memory.fail("moveItem")
        var deps = try Support.makeDeps(fileSystem: fileSystem, manifestPath: path)

        let (status, _) = await Support.answer("/servers/p1-stdio/approve", &deps)

        // MEASURED, not chosen. `AuthRoutes.approve` uses `try? ManifestIO.save` and answers 200
        // whether or not the bytes landed; the reference's own `saveManifest` throws. That is a
        // real divergence, it is R5's shipped behaviour, and P1 does not move a wire status outside
        // its remit — so it is pinned here rather than left undiscovered. The day someone changes
        // it, this test makes the change deliberate. Registered in spec-P1 §8.
        #expect(status == 200, "documenting `try?`: the route reports success it did not achieve")
        let onDisk = try #require(fileSystem.memory.contents(atPath: path))
        #expect(onDisk.contains("\"pending\""), "and the pending change is genuinely still there")
    }

    @Test("A11 — an unknown server is 404 on approve, before the route runs")
    func unknownServerOnApproveIs404() async throws {
        var deps = try Support.makeDeps()
        let (status, body) = await Support.answer("/servers/ghost/approve", &deps)
        #expect(status == 404)
        #expect(body == #"{"error":"no server named \"ghost\""}"#)
    }

    @Test("A11 — an untokened approve is 401, ahead of the 404")
    func untokenedApproveIs401() async throws {
        var deps = try Support.makeDeps()
        // `ghost` does not exist, so a 401 for it pins the ORDER too: the token gate is stage 2 and
        // the live-map lookup is stage 6, and a handler checking existence first would 404.
        for path in ["/servers/p1-stdio/approve", "/servers/ghost/approve"] {
            let (status, _) = await Support.answer(path, &deps, authorized: false)
            #expect(status == 401, "\(path)")
        }
    }
}
