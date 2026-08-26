import Foundation
import Testing
@testable import RouterCore

@Suite("Manifest reading and writing parity with src/manifest.ts")
struct ManifestIOParityTests {
    /// A20 and A19 together: what the shallow parser accepts, and the bytes a re-serialise produces.
    @Test("every manifest loads to the value the reference loads, and re-serialises to its bytes")
    func loadMatches() throws {
        let cases = try ManifestVectors.cases("manifest-parse")
        #expect(!cases.isEmpty)
        for testCase in cases {
            let id = ManifestVectors.text(testCase.member("id")) ?? "?"
            let fileSystem = MemoryFileSystem()
            let path = "/router/manifest.json"
            fileSystem.seed(ManifestVectors.text(testCase.member("text")) ?? "", atPath: path)

            let load = ManifestIO.load(path: path, fileSystem: fileSystem)
            ManifestVectors.expectSameBytes(
                JSStringify.compact(load.manifest.value),
                ManifestVectors.text(testCase.member("loaded")) ?? "",
                "load/\(id)"
            )
            // A19 — the bytes the TypeScript *serializer* would produce for this value, which is a
            // different and stronger claim than echoing the input file back.
            ManifestVectors.expectSameBytes(
                JSStringify.prettyTwoSpace(load.manifest.value),
                ManifestVectors.text(testCase.member("reserialised")) ?? "",
                "reserialise/\(id)"
            )
            let degraded = testCase.member("degraded")?.asBool ?? false
            #expect((load.problem != nil) == degraded, "degradation/\(id)")
        }
    }

    /// A20's named vector, asserted on its own so it cannot be lost in the loop above.
    @Test("servers: [] is accepted, because typeof [] === object")
    func serversArrayIsAccepted() {
        let fileSystem = MemoryFileSystem()
        fileSystem.seed(#"{"version":1,"servers":[]}"#, atPath: "/m.json")
        let load = ManifestIO.load(path: "/m.json", fileSystem: fileSystem)
        #expect(load.problem == nil, "a stricter parser here would reject manifests the reference reads")
        #expect(load.manifest.serverEntries.isEmpty)
    }

    /// D2 — the divergence. The reference returns the same empty manifest for both, and says which
    /// only in a log line. A surface rendering "you have no cached tools" when the truth is "your
    /// cache is corrupt" is the failure this exists to prevent.
    @Test("a cold cache and a corrupt one are different values, not the same empty manifest")
    func coldIsDistinguishableFromCorrupt() {
        let fileSystem = MemoryFileSystem()
        let cold = ManifestIO.load(path: "/absent.json", fileSystem: fileSystem)
        fileSystem.seed("{oh no", atPath: "/corrupt.json")
        let corrupt = ManifestIO.load(path: "/corrupt.json", fileSystem: fileSystem)

        #expect(cold.problem == nil)
        #expect(corrupt.problem != nil)
        // The manifests themselves are identical, which is exactly why the value alone cannot carry
        // the distinction and R4 can ignore this divergence.
        #expect(cold.manifest == corrupt.manifest)
        if case .cold = cold {} else { Issue.record("an absent file should read as cold, not degraded") }

        fileSystem.fail("readFile", at: "/unreadable.json")
        fileSystem.seed("{}", atPath: "/unreadable.json")
        let unreadable = ManifestIO.load(path: "/unreadable.json", fileSystem: fileSystem)
        #expect(unreadable.problem != nil)
    }

    @Test("the degradation message is the reference's wording")
    func degradationCopyIsVerbatim() {
        let problem = ManifestIO.Problem.malformed(path: "/x/manifest.json", reason: "bad")
        #expect(problem.description == "manifest at /x/manifest.json unreadable (bad); rebuilding")
    }

    /// A23. The rename is what makes a reader unable to observe a half-written manifest.
    @Test("a save writes a temp file and renames it over the target")
    func saveIsAtomic() throws {
        let recorder = OperationRecorder()
        let fileSystem = MemoryFileSystem(recorder: recorder)
        let path = "/router/manifest.json"
        fileSystem.seed("previous", atPath: path)

        try ManifestIO.save(.empty, toPath: path, fileSystem: fileSystem)

        #expect(fileSystem.createdDirectories.contains("/router"))
        let operations = recorder.operations
        let wrote = try #require(operations.firstIndex { $0.hasPrefix("writeFile:\(path).tmp-") })
        let moved = try #require(operations.firstIndex { $0.hasPrefix("moveItem:\(path).tmp-") })
        #expect(wrote < moved, "the temp file is written before it is renamed into place")
        #expect(fileSystem.contents(atPath: path) == "{\n  \"version\": 1,\n  \"servers\": {}\n}")
        #expect(
            !fileSystem.paths.contains { $0.contains(".tmp-") },
            "a successful save leaves no temporary behind"
        )
    }

    /// The reference does not clean up after a failed write, and neither does this. The temp file
    /// is the only evidence of what was being written when the disk filled.
    @Test("a failed rename leaves the temp file in place and propagates")
    func failedSaveKeepsTheTemporary() {
        let fileSystem = MemoryFileSystem()
        let path = "/router/manifest.json"
        fileSystem.fail("moveItem")
        #expect(throws: (any Error).self) {
            try ManifestIO.save(.empty, toPath: path, fileSystem: fileSystem)
        }
        #expect(
            fileSystem.paths.contains { $0.hasPrefix("\(path).tmp-") },
            "the partial write survives rather than being swallowed"
        )
        #expect(fileSystem.contents(atPath: path) == nil, "the target was never touched")
    }
}

@Suite("Manifest bookkeeping parity with buildManifest")
struct ManifestBookkeepingParityTests {
    /// A26 and N8. Every branch is replayed against what the reference actually produced for the
    /// same inputs, with its clock frozen so `builtAt` is comparable.
    @Test("every bookkeeping branch matches the reference, byte for byte")
    func branchesMatch() throws {
        let cases = try ManifestVectors.cases("build-manifest")
        #expect(!cases.isEmpty)
        for testCase in cases {
            let id = ManifestVectors.text(testCase.member("id")) ?? "?"
            let upstream = try #require(testCase.member("upstream").map(ManifestVectors.upstream))
            var manifest = ManifestVectors.manifest(servers: testCase.member("servers"))
            let observed = testCase.member("observation")
            let observation: ManifestBookkeeping.Observation =
                if let message = ManifestVectors.text(observed?.member("error")) {
                    .failure(message: message)
                } else {
                    .tools(ManifestVectors.tools(observed?.member("tools")))
                }
            let stamp = testCase.member("builtAtMs")?.asNumber ?? 0

            let report = ManifestBookkeeping.build(
                manifest: &manifest,
                upstreams: [upstream],
                force: testCase.member("force")?.asBool ?? false,
                nowMilliseconds: { stamp },
                observe: { _ in observation }
            )

            ManifestVectors.expectSameBytes(
                JSStringify.compact(manifest.value),
                ManifestVectors.text(testCase.member("manifest")) ?? "",
                "build/\(id)"
            )
            let built = (testCase.member("built")?.asArray ?? []).compactMap { ManifestVectors.text($0) }
            let failed = (testCase.member("failed")?.asArray ?? []).compactMap { ManifestVectors.text($0) }
            #expect(report.built == built, "built/\(id)")
            #expect(report.failed == failed, "failed/\(id)")
        }
    }

    /// N8 stated on its own, because it is the defect this port is required to preserve and the one
    /// most likely to be "fixed" by a later reader who does not know why it is there.
    @Test("an indexing failure destroys the approved tools")
    func failureDestroysApprovedTools() throws {
        let cases = try ManifestVectors.cases("build-manifest")
        let failure = try #require(
            cases.first { ManifestVectors.text($0.member("id")) == "failure-destroys-approved-tools" }
        )
        let recorded = try #require(ManifestVectors.text(failure.member("manifest")))
        #expect(recorded.contains("\"tools\":[]"), "the reference itself empties them")
        #expect(recorded.contains("\"error\":\"spawn failed\""))
        #expect(
            recorded.contains("\"digest\":\"dd\""),
            "R18 preserves digest across index failure so modified surfaces stay held"
        )
    }

    /// A26's spread branch: a member the reference does not model survives a held-for-approval
    /// update, and keeps its position.
    @Test("a changed surface keeps the approved tools and any unmodeled fields")
    func changedSurfaceKeepsUnmodeledFields() throws {
        let cases = try ManifestVectors.cases("build-manifest")
        let changed = try #require(
            cases.first { ManifestVectors.text($0.member("id")) == "changed-digest-holds-pending" }
        )
        let recorded = try #require(ManifestVectors.text(changed.member("manifest")))
        #expect(recorded.contains("\"x-vendor\":\"kept\""), "the spread carries unmodeled members through")
        #expect(recorded.contains("\"pending\""))
        #expect(!recorded.contains("\"error\""), "error: undefined is omitted by the serializer")
    }
}

@Suite("Manifest store — the four paths, driven as traces")
struct ManifestStoreTraceTests {
    private let valid = #"{"version":1,"servers":{"a":{"hash":"h","builtAt":"t","tools":[]}}}"#
    private let other = #"{"version":1,"servers":{"b":{"hash":"h","builtAt":"t","tools":[]}}}"#

    /// The normal path: a re-read happens only when mtime or size moved.
    @Test("a changed file is re-read and an unchanged one is not")
    func reReadsOnlyWhenTheStampMoves() async {
        let fileSystem = MemoryFileSystem()
        let clock = ManualClock(milliseconds: 10000)
        fileSystem.seed(valid, atPath: "/m.json", modified: Date(timeIntervalSince1970: 1))
        let store = ManifestStore(path: "/m.json", fileSystem: fileSystem, clock: clock)

        #expect(await store.current().serverEntries.map(\.name) == [JSString("a")])

        // Same bytes, same stamp: nothing is re-read.
        fileSystem.seed(other, atPath: "/m.json", modified: Date(timeIntervalSince1970: 1), size: valid.count)
        #expect(
            await store.current().serverEntries.map(\.name) == [JSString("a")],
            "an identical mtime and size means the file is assumed unchanged"
        )

        // Move the stamp and it is picked up.
        fileSystem.seed(other, atPath: "/m.json", modified: Date(timeIntervalSince1970: 2))
        #expect(await store.current().serverEntries.map(\.name) == [JSString("b")])
    }

    /// The `or` in "mtime **or** size moved", which the case above cannot reach.
    ///
    /// That test moves both stamps together, so an implementation comparing only the mtime passes
    /// it and passes the unchanged case too — the size half of the condition is never exercised.
    /// An editor that rewrites a file within the same second is exactly how this happens in life.
    @Test("a file whose size moved is re-read even when its mtime did not")
    func reReadsWhenOnlyTheSizeMoves() async {
        let fileSystem = MemoryFileSystem()
        let stamp = Date(timeIntervalSince1970: 1)
        fileSystem.seed(valid, atPath: "/m.json", modified: stamp)
        let store = ManifestStore(
            path: "/m.json", fileSystem: fileSystem, clock: ManualClock(milliseconds: 10000)
        )
        #expect(await store.current().serverEntries.map(\.name) == [JSString("a")])

        // Same mtime, genuinely different length.
        let longer = #"{"version":1,"servers":{"b":{"hash":"hh","builtAt":"tt","tools":[],"e":""}}}"#
        #expect(longer.count != valid.count, "the fixture must differ in length or this proves nothing")
        fileSystem.seed(longer, atPath: "/m.json", modified: stamp)
        #expect(
            await store.current().serverEntries.map(\.name) == [JSString("b")],
            "a size change alone must trigger the re-read"
        )
    }

    /// The failed-reload path, and the exact back-off. A window longer than a second would satisfy
    /// every property stated about this and leave a corrected file unread for as long as it lasted.
    @Test("a failed reload keeps the previous manifest and backs off exactly one second")
    func failedReloadBacksOffOneSecond() async {
        let fileSystem = MemoryFileSystem()
        let clock = ManualClock(milliseconds: 1000)
        fileSystem.seed(valid, atPath: "/m.json", modified: Date(timeIntervalSince1970: 1))
        let store = ManifestStore(path: "/m.json", fileSystem: fileSystem, clock: clock)
        #expect(await store.current().serverEntries.map(\.name) == [JSString("a")])

        // A half-written file arrives.
        fileSystem.seed("{trunc", atPath: "/m.json", modified: Date(timeIntervalSince1970: 2))
        #expect(
            await store.current().serverEntries.map(\.name) == [JSString("a")],
            "a truncated file must never empty the tool list"
        )
        #expect(await store.lastProblem != nil)

        // The writer finishes. Inside the back-off window the corrected file is still not read.
        fileSystem.seed(other, atPath: "/m.json", modified: Date(timeIntervalSince1970: 3))
        clock.set(1999)
        #expect(await store.current().serverEntries.map(\.name) == [JSString("a")], "999ms is inside")

        clock.set(2000)
        #expect(
            await store.current().serverEntries.map(\.name) == [JSString("b")],
            "exactly 1000ms after the failure the retry happens"
        )
        #expect(await store.lastProblem == nil, "a good reload clears the recorded problem")
    }

    /// A latent defect in the reference, ported deliberately: the constructor records the stamp of a
    /// file it could not parse, so it never looks again until something writes to it.
    @Test("a manifest malformed at construction is not retried until the file changes")
    func malformedAtConstructionRecordsItsStamp() async {
        let fileSystem = MemoryFileSystem()
        let clock = ManualClock(milliseconds: 5000)
        fileSystem.seed("{not json", atPath: "/m.json", modified: Date(timeIntervalSince1970: 1))
        let store = ManifestStore(path: "/m.json", fileSystem: fileSystem, clock: clock)

        #expect(await store.current().serverEntries.isEmpty)
        clock.set(100_000)
        #expect(
            await store.current().serverEntries.isEmpty,
            "no amount of elapsed time helps: the stamp was recorded, so the file looks unchanged"
        )

        fileSystem.seed(valid, atPath: "/m.json", modified: Date(timeIntervalSince1970: 2))
        #expect(
            await store.current().serverEntries.map(\.name) == [JSString("a")],
            "only a moved stamp gets it re-read"
        )
    }

    /// The second latent defect: a deleted file leaves the previous manifest *and* the previous
    /// stamp, so a file that reappears with that same stamp is never read.
    @Test("a deleted manifest keeps the previous one and does not clear the stamp")
    func deletionKeepsThePreviousManifestAndStamp() async {
        let fileSystem = MemoryFileSystem()
        let clock = ManualClock(milliseconds: 1000)
        fileSystem.seed(valid, atPath: "/m.json", modified: Date(timeIntervalSince1970: 1))
        let store = ManifestStore(path: "/m.json", fileSystem: fileSystem, clock: clock)
        #expect(await store.current().serverEntries.map(\.name) == [JSString("a")])

        fileSystem.delete("/m.json")
        #expect(
            await store.current().serverEntries.map(\.name) == [JSString("a")],
            "a vanished file must not empty the tool list"
        )

        // Recreated with the identical stamp: not re-read, because the stamp was never cleared.
        fileSystem.seed(other, atPath: "/m.json", modified: Date(timeIntervalSince1970: 1), size: valid.count)
        #expect(
            await store.current().serverEntries.map(\.name) == [JSString("a")],
            "identical mtime and size after a delete reads as no change at all"
        )

        fileSystem.seed(other, atPath: "/m.json", modified: Date(timeIntervalSince1970: 9))
        #expect(await store.current().serverEntries.map(\.name) == [JSString("b")])
    }
}
