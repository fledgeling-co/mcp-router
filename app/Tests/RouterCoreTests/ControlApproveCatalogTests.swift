import Foundation
import Testing
@testable import RouterCore

/// M38's decision, read back at the catalog rather than at the response.
///
/// `POST /servers/:name/approve` is the write the whole staged-diff review stands on: the sheet
/// draws what changed, and this route is what happens when the user accepts it. R21 fixed the half
/// where the route answered 200 over a manifest write it had discarded, and
/// ``ControlApproveDispatchTests`` reads the promoted bytes back off disk.
///
/// **What nothing asked was whether a session is served them.** That is the question the user
/// actually has, and it is a different one: `ToolUnion.unionTools` skips an entry that is absent,
/// disabled, scoped out, or carrying no approved tools, so a promotion whose bytes are on disk can
/// still reach nobody. `planning/parity/surface.tsv:48` says the same from the parity side — *"the
/// 200 PROMOTION path is NOT two-router compared … a manifest-snapshotting differential helper is
/// the missing piece"* — so the wire lane cannot answer it either.
///
/// This file is K5's shape one route over. ``ControlDisableWriteTests`` struck `PATCH` and refused
/// to believe the handler's own account of its write; this strikes `/approve` and refuses the same
/// thing. The read-back is ``MCPEndpoint/listTools()`` over a ``ManifestStore`` built **before** the
/// strike and never handed to the control handler — the same two lines a connected client's
/// `tools/list` runs, over a store that has to notice the file moved to answer at all. Asserting on
/// the approve response would be asking the writer whether it wrote.
@Suite("M38 — approving a held surface moves what a session is served")
struct ControlApproveCatalogTests {
    /// Two stdio servers. `sibling` is the control in every test here: a route that promoted the
    /// whole manifest, or the wrong entry, passes every assertion about `held` on its own.
    private static let config = """
    {
      "mcpServers": {
        "held": { "command": "/bin/echo", "args": ["held"] },
        "sibling": { "command": "/bin/echo", "args": ["sibling"] }
      }
    }
    """

    /// `held` has one approved tool and two waiting behind the quarantine; `sibling` has one and
    /// nothing pending.
    ///
    /// The two sides are deliberately different lengths. `ManifestStore` reloads on a changed
    /// ``FileStamp``, which is modification time **and** size, so a promotion that happened to
    /// rewrite the file to the same byte count would be invisible to the store — and a fixture
    /// tuned to make the sizes match would be a test that could not fail for a reason nothing in
    /// the file would say.
    private static let manifest = """
    {
      "version": 1,
      "servers": {
        "held": {
          "hash": "h", "digest": "d1", "builtAt": "t1",
          "tools": [{"name": "old", "description": "the approved text"}],
          "pending": {
            "digest": "d2",
            "seenAt": "s1",
            "tools": [
              {"name": "promoted-one", "description": "the text the user is being shown"},
              {"name": "promoted-two", "description": "an input this tool did not previously ask for"}
            ]
          }
        },
        "sibling": {
          "hash": "h", "digest": "s1", "builtAt": "t1",
          "tools": [{"name": "steady", "description": "unchanged throughout"}]
        }
      }
    }
    """

    // MARK: - Harness

    /// The filesystem the control handler writes to and the endpoint reads from — one memory
    /// filesystem, two callers that share no other state.
    ///
    /// Seeded at the epoch rather than at ``MemoryFileSystem/seed(_:atPath:modified:size:)``'s
    /// default of one second, because ``ManifestIO/save(_:toPath:fileSystem:)`` writes a temporary
    /// and moves it, and a temporary written for the first time lands at one second. Seeding at the
    /// epoch makes the post-write stamp differ in **both** members rather than resting on the size.
    private static func seeded() -> (system: AuthTestFileSystem, path: String) {
        let fileSystem = AuthTestFileSystem()
        let path = ManifestLockScratch.path("m38-approve")
        fileSystem.memory.seed(manifest, atPath: path, modified: Date(timeIntervalSince1970: 0))
        return (fileSystem, path)
    }

    /// The serving side, built over the same filesystem and handed no part of the control handler.
    ///
    /// Constructed **before** the strike on purpose: its ``ManifestStore`` loads the pre-approval
    /// manifest at init, so a promotion only shows up here if the store notices the file moved and
    /// re-reads it — which is exactly what the serving process does between two `tools/list` calls.
    private static func endpoint(
        fileSystem: AuthTestFileSystem, manifestPath: String
    ) -> MCPEndpoint {
        let clock = ManualClock(milliseconds: 1_770_000_000_000)
        let upstreams = [stdioUpstream("held"), stdioUpstream("sibling")]
        let config = RouterConfig(
            port: 8971, host: "127.0.0.1", idleMs: 300_000, startupTimeoutMs: 60000,
            upstreams: upstreams, manifestPath: manifestPath,
            logPath: "/router/r.log", usagePath: "/router/none/usage.jsonl",
            statsPath: "/router/none/stats.json", authDir: "/router/auth"
        )
        return MCPEndpoint(
            deps: MCPEndpoint.Deps(
                config: config,
                upstreams: upstreams,
                manifest: ManifestStore(path: manifestPath, fileSystem: fileSystem, clock: clock),
                pool: UpstreamPool(
                    upstreams: upstreams,
                    defaultIdleMilliseconds: 60000,
                    defaultStartupTimeoutMilliseconds: 1000,
                    transporting: FakeTransport(),
                    clock: TestClock(),
                    log: nil
                ),
                usage: UsageStore(
                    logPath: "/router/none/usage.jsonl",
                    statsPath: "/router/none/stats.json",
                    clock: clock
                ),
                log: nil,
                clock: clock
            ),
            instructions: nil,
            identify: { _ in CallerIdentity(pid: nil, cwd: nil, client: nil) }
        )
    }

    /// What a session listing tools right now would be offered, by name.
    private static func served(_ endpoint: MCPEndpoint) async -> [String] {
        let result = await endpoint.listTools()
        return (result.member("tools")?.asArray ?? [])
            .compactMap { $0.member("name")?.asString?.string }
    }

    /// One `POST /servers/:name/approve` through the real handler, with its own deps.
    private static func approve(
        _ name: String, fileSystem: AuthTestFileSystem, manifestPath: String
    ) async throws -> (status: Int, body: String) {
        var deps = try ControlAuthSupport.makeDeps(
            fileSystem: fileSystem, manifestPath: manifestPath, config: config
        )
        return await ControlAuthSupport.answer("/servers/\(name)/approve", &deps)
    }

    /// `GET /servers/:name/changes`, read from a manifest reloaded off the file.
    ///
    /// Its own deps, loaded from disk after the strike: the route reads `deps.manifest`, so handing
    /// it the snapshot the striking call carried would report the state before the write.
    private static func changesBody(
        _ name: String, fileSystem: AuthTestFileSystem, manifestPath: String
    ) async throws -> String {
        var deps = try ControlAuthSupport.makeDeps(
            fileSystem: fileSystem, manifestPath: manifestPath, config: config
        )
        deps.manifest = ManifestIO.load(path: manifestPath, fileSystem: fileSystem).manifest
        let response = await ControlHandler(token: ControlAuthSupport.token).handle(
            ControlAPIRequest(
                method: "GET", encodedPath: "/servers/\(name)/changes",
                query: [], headers: [(name: "x-mcpr-token", value: ControlAuthSupport.token)],
                body: nil
            ), &deps
        )
        guard case let .bytes(bytes) = response.body else { return "<stream>" }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - The quarantine, and the decision that lifts it

    /// Oracle lines 5, 6 and 7 in one strike, because they are one claim seen before and after.
    @Test("a held surface is not served, and approving it is what starts serving it")
    func approvingMovesTheServedCatalog() async throws {
        let seed = Self.seeded()
        let endpoint = Self.endpoint(fileSystem: seed.system, manifestPath: seed.path)

        // Line 5. Stated before the strike, so the assertions after it are a measurement rather
        // than a restatement of a fixture that was already in the asserted state.
        let before = await Self.served(endpoint)
        #expect(
            before.contains("held__old"),
            "the approved surface is not being served at all, so nothing below is about approval: \(before)"
        )
        #expect(
            !before.contains("held__promoted-one") && !before.contains("held__promoted-two"),
            "a held change was already being served, which is the quarantine failing: \(before)"
        )

        let result = try await Self.approve("held", fileSystem: seed.system, manifestPath: seed.path)
        #expect(result.status == 200, "the promotion was refused: \(result.body)")

        // Line 6, through the store the handler never saw.
        let after = await Self.served(endpoint)
        #expect(
            after.contains("held__promoted-one") && after.contains("held__promoted-two"),
            "the approved tools reached the manifest and not the session: \(after)"
        )
        #expect(
            !after.contains("held__old"),
            "the superseded tool is still being served after its replacement was approved: \(after)"
        )

        // Line 7 — the control. Every assertion above is also passed by a route that promoted the
        // whole manifest, so the untouched sibling is what makes them about `held`.
        #expect(
            after.contains("sibling__steady"),
            "approving one server stopped another being served: \(after)"
        )
        #expect(
            after.filter { $0.hasPrefix("sibling__") } == before.filter { $0.hasPrefix("sibling__") },
            "the sibling's served tools moved: \(before) -> \(after)"
        )
    }

    /// Oracle line 8. R21's fix, read at the catalog rather than at the status code.
    ///
    /// The keys are the `FileSystem` method names. `fail("write")` would register a failure for an
    /// operation nothing performs, and this test would then pass by writing successfully while
    /// claiming to have proven the refusal.
    @Test("a refused manifest write leaves the served catalog exactly where it was")
    func aRefusedWriteChangesNothingASessionSees() async throws {
        let seed = Self.seeded()
        let endpoint = Self.endpoint(fileSystem: seed.system, manifestPath: seed.path)
        let before = await Self.served(endpoint)

        seed.system.memory.fail("writeFile")
        seed.system.memory.fail("moveItem")
        let result = try await Self.approve("held", fileSystem: seed.system, manifestPath: seed.path)
        #expect(result.status == 500, "a refused write did not report itself: \(result.body)")
        seed.system.memory.stopFailing("writeFile")
        seed.system.memory.stopFailing("moveItem")

        #expect(
            await Self.served(endpoint) == before,
            "a promotion that was never written changed what a session is served"
        )
        // And the decision is still available to be taken, rather than lost between the two.
        let changes = try await Self.changesBody("held", fileSystem: seed.system, manifestPath: seed.path)
        #expect(
            changes.contains(#""pending":true"#),
            "the held change disappeared without being approved: \(changes)"
        )
    }

    /// Oracle line 9, and the half a route that re-promoted a cleared entry would get wrong.
    @Test("a second approve is refused and the served catalog does not move again")
    func approvingTwiceIsRefusedAndChangesNothingFurther() async throws {
        let seed = Self.seeded()
        let endpoint = Self.endpoint(fileSystem: seed.system, manifestPath: seed.path)

        let first = try await Self.approve("held", fileSystem: seed.system, manifestPath: seed.path)
        #expect(first.status == 200)
        let promoted = await Self.served(endpoint)
        #expect(promoted.contains("held__promoted-one"), "the first approve did not land: \(promoted)")

        let second = try await Self.approve("held", fileSystem: seed.system, manifestPath: seed.path)
        #expect(second.status == 409, "a second approve was not refused: \(second.body)")
        #expect(
            await Self.served(endpoint) == promoted,
            "the refused second approve moved the catalog anyway"
        )

        // The surface the user reads next agrees there is nothing left held.
        let changes = try await Self.changesBody("held", fileSystem: seed.system, manifestPath: seed.path)
        #expect(
            changes.contains(#""pending":false"#),
            "the change reads as still pending after being approved: \(changes)"
        )
    }
}
