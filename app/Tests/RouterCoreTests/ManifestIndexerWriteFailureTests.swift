import Foundation
import Testing
@testable import RouterCore

/// What `ManifestIndexer` reports when the manifest write does not land — DEF-049's half of it.
///
/// This file began as a characterisation, written by the sitting that found the defect: it pinned
/// `try? ManifestIO.save` at `ServicePorts.swift:347` reporting a clean index over a manifest that
/// does not exist, and said in its own doc comment that it documented rather than corrected. R10 is
/// the correction, so the same cases now assert the contract instead of the defect.
///
/// Found by a denial control rather than by reading the code:
/// `planning/test-campaign/bin/witness-arm-denial.sh` points the CLI at a router home with mode
/// `dr-x------`, and `index --force` printed `ok    witness-fixture (1 tools)` and exited 0 over a
/// `manifest.json` that does not exist. The verb's own closing line said `0 tools cached`, because
/// it re-reads the manifest from disk to count — so the output disagreed with itself inside eight
/// lines and nothing compared them.
///
/// It also carries the half of the same disagreement that has **no filesystem in it at all**: a
/// server whose tool surface changed is held for approval, so the tools it just listed are pending
/// while the manifest keeps serving the approved set — and an outcome carrying only `tools` gives a
/// reporter the wrong number to print beside the closing count.
///
/// **The exit code is deliberately not changed here**, and `CLIIndexWriteDeniedTests` pins it as it
/// stands so that moving it later is a decision somebody takes rather than a side effect. The same
/// `try?` is pinned on the control-API side at
/// `ControlApproveDispatchTests.approveWithARefusingFileSystem`, deliberately, as R5's shipped
/// behaviour; that half is M28's docket, not this item's.
@Suite("ManifestIndexer — a manifest write that fails")
struct ManifestIndexerWriteFailureTests {
    /// A session that answers `tools/list` with one real tool, so indexing has something to store.
    ///
    /// `PoolTestSupport.FakeSession` deliberately throws from `listTools`, which is right for the
    /// pool tests and useless here: a throwing list would take the indexer down its failure arm
    /// and this file would pin the wrong path.
    private final class ListingSession: UpstreamSession, @unchecked Sendable {
        /// Named rather than counted, because the bookkeeping compares a DIGEST of the surface: two
        /// sessions listing one tool each are the same surface only if it is the same tool.
        let toolNames: [String]
        let processIdentifier: Int32? = 4242

        init(toolNames: [String] = ["echo"]) {
            self.toolNames = toolNames
        }

        func waitUntilEnded() async {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }

        func shutdown() async {}
        func listTools() async throws -> JSONValue {
            .object([
                JSONMember(key: "tools", value: .array(toolNames.map { name in
                    .object([
                        JSONMember(key: "name", value: .string(JSString(name))),
                        JSONMember(key: "description", value: .string("returns its argument"))
                    ])
                }))
            ])
        }

        func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
            .object([])
        }
    }

    private struct ListingTransport: UpstreamTransporting, Sendable {
        var toolNames: [String] = ["echo"]

        func open(
            _ upstream: UpstreamConfig, timeoutMilliseconds: Int
        ) async throws -> any UpstreamSession {
            ListingSession(toolNames: toolNames)
        }
    }

    /// A transport whose open fails, for the arm where the upstream never answers at all.
    private struct RefusingTransport: UpstreamTransporting, Sendable {
        func open(
            _ upstream: UpstreamConfig, timeoutMilliseconds: Int
        ) async throws -> any UpstreamSession {
            throw PoolError.spawnFailed(name: upstream.name, reason: "the fixture refused to start")
        }
    }

    private func indexer(
        _ fileSystem: MemoryFileSystem,
        path: String = "/router/manifest.json",
        transport: any UpstreamTransporting = ListingTransport(),
        log: RouterLog? = nil
    ) -> ManifestIndexer {
        ManifestIndexer(
            startupTimeoutMs: 2000,
            transporting: transport,
            manifestPath: path,
            fileSystem: fileSystem,
            log: log
        )
    }

    /// `ManifestIO.save` writes a temp file and renames it, so refusing only one of the two leaves
    /// the other arm working and the manifest lands anyway — which would make every test below pass
    /// while proving nothing.
    private func refuseBothWriteArms(_ fileSystem: MemoryFileSystem) {
        fileSystem.fail("writeFile")
        fileSystem.fail("moveItem")
    }

    @Test("the control: a writable manifest really does gain the tool, and reports it cached")
    func aWritableManifestGainsTheTool() async throws {
        let fileSystem = MemoryFileSystem()
        let path = "/router/manifest.json"
        let outcome = await indexer(fileSystem).index(stdioUpstream("fixture"))

        #expect(outcome.error == nil)
        #expect(outcome.tools == 1)
        #expect(outcome.cached, "the write landed, so nothing is owed to the reader")
        #expect(outcome.cacheFailure == nil)
        let onDisk = try #require(
            fileSystem.contents(atPath: path),
            "without this the refusal test below could pass because indexing never ran"
        )
        #expect(onDisk.contains("echo"))
        #expect(onDisk.contains("fixture"))
    }

    @Test("a refused write is reported as a refused write, not as a successful index")
    func aRefusedWriteIsReportedAsSuch() async {
        let fileSystem = MemoryFileSystem()
        let path = "/router/manifest.json"
        refuseBothWriteArms(fileSystem)

        let outcome = await indexer(fileSystem).index(stdioUpstream("fixture"))

        #expect(
            !outcome.cached,
            "this is the defect: `try? ManifestIO.save` left the caller no way to ask"
        )
        #expect(outcome.cacheFailure != nil, "and the reason travels, so a terminal can print it")
        #expect(
            outcome.error == nil,
            "the UPSTREAM did not fail, and `error` is what the control API turns into 422"
        )
        #expect(outcome.tools == 1, "the index really did read one tool")
        #expect(
            fileSystem.contents(atPath: path) == nil,
            "while nothing reached the manifest at all"
        )
    }

    @Test("the two numbers the verb prints are no longer free to disagree unnoticed")
    func theCountTheVerbPrintsIsReconciledWithTheOneItReports() async {
        let fileSystem = MemoryFileSystem()
        let path = "/router/manifest.json"
        refuseBothWriteArms(fileSystem)

        let outcome = await indexer(fileSystem).index(stdioUpstream("fixture"))
        // The CLI's own closing arithmetic, from `MCPRouterCLI.swift`: re-read the manifest, union
        // it against the configured upstreams, print that number. Re-derived here rather than
        // asserted as a string, because the defect is that the two numbers differ and a test
        // asserting one of them in isolation cannot see it.
        let after = ManifestIO.load(path: path, fileSystem: fileSystem).manifest
        let cached = ToolUnion.unionTools(
            manifest: after, upstreams: [stdioUpstream("fixture")]
        ).count

        #expect(outcome.tools == 1, "one tool was read from the upstream")
        #expect(cached == 0, "and none of it is on disk")
        #expect(
            outcome.tools != cached,
            "the two numbers still differ — they describe different things and always could"
        )
        #expect(
            !outcome.cached,
            "what changed is that the difference is now reported, so the verb can say which is which"
        )
    }

    @Test("the refusal reaches the log, so the control API's reindex route is not silent either")
    func theRefusalIsLogged() async {
        let sink = RecordingSink()
        let log = RouterLog(sink: sink, fileSystem: MemoryFileSystem(), clock: SystemClock())
        let fileSystem = MemoryFileSystem()
        refuseBothWriteArms(fileSystem)

        _ = await indexer(fileSystem, log: log).index(stdioUpstream("fixture"))

        let text = sink.text
        #expect(text.contains("did not reach /router/manifest.json"), "the path is named")
        #expect(text.contains("the manifest row for \"fixture\""), "and so is the server")
        #expect(
            text.contains("whatever that file holds for it is from an earlier run"),
            """
            A claim about PROVENANCE, not about absence. The line said "nothing this run read \
            from it is cached", which is false whenever the refused update carried tools an older \
            row already holds — the same falsehood the CLI's closing sentence was rewritten to \
            drop, and it survived here after that rewrite.
            """
        )
        #expect(text.contains("permissions"), "and what to do about it")
    }

    @Test("the control: a landing write logs no refusal")
    func aLandingWriteLogsNoRefusal() async {
        let sink = RecordingSink()
        let log = RouterLog(sink: sink, fileSystem: MemoryFileSystem(), clock: SystemClock())

        _ = await indexer(MemoryFileSystem(), log: log).index(stdioUpstream("fixture"))

        #expect(
            !sink.text.contains("did not reach"),
            "without this the assertion above could be satisfied by a line that always fires"
        )
    }

    @Test("the rename arm alone: the temp file is written and the manifest still does not move")
    func aRefusedRenameIsAlsoAWriteThatDidNotLand() async {
        let recorder = OperationRecorder()
        let fileSystem = MemoryFileSystem(recorder: recorder)
        let path = "/router/manifest.json"
        // Only the SECOND arm of `ManifestIO.save`. The temp file lands and the rename does not —
        // the arm the both-arms test above can never reach, because a refused `writeFile` means
        // `moveItem` is never called at all.
        fileSystem.fail("moveItem")

        let outcome = await indexer(fileSystem).index(stdioUpstream("fixture"))

        #expect(!outcome.cached, "a rename that did not happen is a row that did not land")
        #expect(outcome.cacheFailure != nil)
        #expect(outcome.error == nil, "the upstream was fine; the filesystem was not")
        #expect(fileSystem.contents(atPath: path) == nil, "nothing reached the manifest itself")
        // The temp write is what proves which arm failed: it is recorded only after its own
        // injected-failure check passes, so seeing it means the first arm succeeded and the refusal
        // can only have come from the rename. Asserting a stray `.tmp-` file instead would pin the
        // missing cleanup as an invariant, and go red the day somebody adds a `defer` to
        // `ManifestIO.save` for a good reason.
        #expect(
            recorder.operations.contains { $0.hasPrefix("writeFile:\(path).tmp-") },
            "the temp file was written, so the refusal came from the rename and nothing else"
        )
    }

    @Test("a manifest that already holds an older row keeps it when the update cannot be written")
    func anOlderRowSurvivesARefusedUpdate() async {
        let fileSystem = MemoryFileSystem()
        let path = "/router/manifest.json"

        let first = await indexer(fileSystem).index(stdioUpstream("fixture"))
        #expect(first.cached, "the control: the first index really did land")
        let before = fileSystem.contents(atPath: path)
        #expect(before != nil, "and there is a row on disk to be preserved")

        refuseBothWriteArms(fileSystem)
        let second = await indexer(fileSystem).index(stdioUpstream("fixture"))

        #expect(!second.cached, "the update did not land")
        #expect(
            fileSystem.contents(atPath: path) == before,
            """
            The older row is untouched, so the summary count is NOT zero here — and a report \
            saying the lost server is missing from that count would be false.
            """
        )
    }

    @Test("an upstream that fails AND a refused write reports both, and confuses neither")
    func anUpstreamFailureWithARefusedWriteReportsBoth() async {
        let fileSystem = MemoryFileSystem()
        refuseBothWriteArms(fileSystem)

        let outcome = await indexer(fileSystem, transport: RefusingTransport())
            .index(stdioUpstream("fixture"))

        #expect(outcome.error?.contains("refused to start") == true, "the upstream's failure stands")
        #expect(!outcome.cached, "and the failure entry did not reach disk either")
        #expect(outcome.tools == 0)
    }

    @Test("a changed surface reports the changes it is holding, not the tools it just read")
    func aHeldSurfaceCarriesItsChangeCount() async {
        let fileSystem = MemoryFileSystem()

        let first = await indexer(fileSystem).index(stdioUpstream("fixture"))
        #expect(first.heldChanges == nil, "first sight is approved, not held")
        #expect(first.tools == 1)

        // Same server, one more tool: the digest moves, so the new surface is held as `pending` and
        // the manifest keeps serving the approved one.
        let second = await indexer(fileSystem, transport: ListingTransport(toolNames: ["echo", "reverse"]))
            .index(stdioUpstream("fixture"))

        #expect(second.heldChanges == 1, "one added tool is one change held for approval")
        #expect(second.tools == 2, "and `tools` still says what the upstream listed — both are true")
        #expect(second.cached, "nothing was refused; the entry with its pending block did land")
        // The number the CLI's closing line prints, derived the way that line derives it. It counts
        // the APPROVED surface, so a reporter printing `tools` beside it prints 2 against 1.
        let after = ManifestIO.load(path: "/router/manifest.json", fileSystem: fileSystem).manifest
        let cached = ToolUnion.unionTools(
            manifest: after, upstreams: [stdioUpstream("fixture")]
        ).count
        #expect(cached == 1, "the served surface is unchanged while the change is pending")
        #expect(
            second.tools != cached,
            "which is why `heldChanges` exists: without it the verb has only the wrong number"
        )
    }

    @Test("an unusable answer from an upstream is not reported as a filesystem refusal")
    func anUpstreamWithNoToolsArrayReportsNoCacheFailure() async {
        let outcome = await indexer(MemoryFileSystem(), transport: EmptyListingTransport())
            .index(stdioUpstream("fixture"))

        #expect(outcome.error == "the upstream returned no tools array")
        #expect(
            outcome.cacheFailure == nil,
            """
            This arm returns before any save is attempted, on a filesystem that would have \
            accepted one. Reporting it as a cache failure puts `not cached — check that \
            directory's permissions` in front of a reader whose directory is fine; `error` \
            already says what actually went wrong.
            """
        )
    }
}

/// A session that answers `tools/list` with an object carrying no `tools` member at all.
private final class EmptyListingSession: UpstreamSession, @unchecked Sendable {
    let processIdentifier: Int32? = 4243

    func waitUntilEnded() async {
        try? await Task.sleep(nanoseconds: 60_000_000_000)
    }

    func shutdown() async {}

    func listTools() async throws -> JSONValue {
        .object([])
    }

    func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        .object([])
    }
}

private struct EmptyListingTransport: UpstreamTransporting, Sendable {
    func open(
        _ upstream: UpstreamConfig, timeoutMilliseconds: Int
    ) async throws -> any UpstreamSession {
        EmptyListingSession()
    }
}
