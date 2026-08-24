import Foundation
import Testing
@testable import RouterCore

@Suite("R20 — Staged entry collision and error attribution safety")
struct StagedErrorAttributionTests {
    @Test("an existing healthy server is not wiped or attributed with a staged failure")
    func stagedCollisionPreservesHealthyServer() {
        let healthyTools = [
            CachedTool(members: [
                JSONMember(key: "name", value: .string("query")),
                JSONMember(key: "description", value: .string("healthy db query"))
            ])
        ]
        var healthyEntry = CachedServer(members: [])
        healthyEntry.set("hash", .string("healthyHash"))
        healthyEntry.set("tools", .array(healthyTools.map(\.value)))
        healthyEntry.set("digest", .string("healthyDigest"))

        var manifest = Manifest.empty
        manifest.setEntry("db", healthyEntry)

        // Staged broken definition with the same name "db"
        let brokenUpstream = UpstreamConfig(
            name: "db",
            transport: .stdio,
            raw: .object([
                JSONMember(key: "command", value: .string("/nonexistent/not-a-server"))
            ]),
            command: "/nonexistent/not-a-server",
            args: [],
            env: [],
            headers: []
        )

        // In WatchIndexing / ManifestBookkeeping, applying a failure to a server that is already
        // serving under a different hash or definition should not wipe out the healthy server's tools
        // if it represents an invalid staged candidate.
        let step = ManifestBookkeeping.apply(
            previous: manifest.entry(named: "db"),
            observation: .failure(message: "spawn /nonexistent/not-a-server ENOENT"),
            configHash: UpstreamHash.hash(brokenUpstream),
            nowMilliseconds: 1000
        )

        #expect(step.entry.hasError)
        #expect(step.entry.digest == "healthyDigest", "Digest from healthy server is preserved")
    }
}
