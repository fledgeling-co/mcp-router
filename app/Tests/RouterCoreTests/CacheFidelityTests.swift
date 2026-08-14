import Foundation
import MCP
import Testing
@testable import RouterCore

@Suite("Cache fidelity — what the persistence type must not lose")
struct CacheFidelityTests {
    private let wire = #"{"name":"x","description":"d","inputSchema":{"z":1,"a":2},"x-vendor":{"keep":true}}"#

    /// A18. What the cache holds is what gets served, so a member the router drops is a member the
    /// upstream advertised and the client never sees.
    @Test("a cached tool round-trips byte-for-byte, member order and unmodeled fields included")
    func toolRoundTripsLosslessly() throws {
        let tool = try #require(try CachedTool(JSONParser.parse(wire)))
        ManifestVectors.expectSameBytes(JSStringify.compact(tool.value), wire, "cached tool round trip")
        #expect(tool.rawMember("x-vendor") != nil)
    }

    /// A18's second half, and the one that catches a lazy implementation: an unchanged save can be a
    /// byte copy of the input file. This one *modifies* the entry first, so the whole value has to
    /// be reconstructed from the parsed representation and the unmodeled fields have to survive
    /// that reconstruction.
    @Test("unmodeled fields survive a save that changed something")
    func unmodeledFieldsSurviveAModifyingSave() throws {
        let text = """
        {"version":1,"servers":{"a":{"hash":"h","builtAt":"OLD","tools":[\(wire)],"x-entry":42}}}
        """
        let fileSystem = MemoryFileSystem()
        fileSystem.seed(text, atPath: "/m.json")

        var manifest = ManifestIO.load(path: "/m.json", fileSystem: fileSystem).manifest
        var entry = try #require(manifest.entry(named: "a"))
        entry.set("builtAt", .string(JSString("NEW")))
        manifest.setEntry("a", entry)
        try ManifestIO.save(manifest, toPath: "/m.json", fileSystem: fileSystem)

        let reloaded = ManifestIO.load(path: "/m.json", fileSystem: fileSystem).manifest
        let reloadedEntry = try #require(reloaded.entry(named: "a"))
        #expect(reloadedEntry.builtAt == JSString("NEW"), "the change landed")
        #expect(reloadedEntry.member("x-entry") == .number(42), "an unmodeled entry field survived")
        let tool = try #require(reloadedEntry.tools.first)
        ManifestVectors.expectSameBytes(
            JSStringify.compact(tool.value),
            wire,
            "the tool is still exactly what the server advertised"
        )
    }

    /// A37. The SDK's tool type is pinned and used at the protocol boundary, and is deliberately
    /// **not** the persistence type. Both paths are run over the same input so the difference is
    /// demonstrated rather than asserted.
    @Test("the SDK type loses what the cached type keeps")
    func sdkTypeIsLossyWhereTheCacheIsNot() throws {
        let cached = try #require(try CachedTool(JSONParser.parse(wire)))
        ManifestVectors.expectSameBytes(JSStringify.compact(cached.value), wire, "cache path")

        let decoded = try JSONDecoder().decode(Tool.self, from: Data(wire.utf8))
        let reencoded = try #require(String(bytes: JSONEncoder().encode(decoded), encoding: .utf8))
        #expect(
            !reencoded.contains("x-vendor"),
            "the SDK models a fixed set of keys, so an unmodeled member is gone after one hop"
        )
        #expect(decoded.name == "x", "the modelled fields do survive — the loss is specific")
    }

    /// The other half of the same loss, and the deterministic way to state it: the SDK's value type
    /// stores an object as a Swift dictionary, so it **cannot represent** member order at all. Two
    /// schemas that hash differently are the same value to it.
    @Test("the SDK value type cannot distinguish two member orders that hash differently")
    func sdkValueCannotRepresentMemberOrder() throws {
        #expect(
            Value.object(["z": .int(1), "a": .int(2)]) == Value.object(["a": .int(2), "z": .int(1)]),
            "a dictionary has no order, so the distinction is gone before any encoding happens"
        )

        let za = try #require(try CachedTool(JSONParser.parse(#"{"name":"t","inputSchema":{"z":1,"a":2}}"#)))
        let az = try #require(try CachedTool(JSONParser.parse(#"{"name":"t","inputSchema":{"a":2,"z":1}}"#)))
        #expect(
            ToolsDigest.digest(of: [za]) != ToolsDigest.digest(of: [az]),
            "but the digest does distinguish them, which is why the cache cannot go through that type"
        )
    }

    /// A lone surrogate cannot survive Swift's `String`, so a namespaced name built by converting
    /// through it would be silently corrupted.
    @Test("a namespaced tool name is built over code units, not through String")
    func namespacingPreservesLoneSurrogates() throws {
        let manifest = Manifest(members: [
            JSONMember(key: "version", value: .number(1)),
            JSONMember(key: "servers", value: .object([
                JSONMember(key: "srv", value: .object([
                    JSONMember(key: "hash", value: .string("h")),
                    JSONMember(key: "tools", value: .array([
                        .object([
                            JSONMember(key: "name", value: .string(JSString(units: [0xD800, 0x61]))),
                            JSONMember(key: "description", value: .string("d"))
                        ])
                    ]))
                ]))
            ]))
        ])
        let upstream = UpstreamConfig(
            name: "srv", transport: .stdio, raw: .object([]), args: [], env: [], headers: []
        )
        let union = ToolUnion.unionTools(manifest: manifest, upstreams: [upstream], cwd: nil)
        let name = try #require(union.first?.name)
        #expect(
            name.units == Array("srv__".utf16) + [0xD800, 0x61],
            "the unpaired surrogate is still there; a trip through String would have replaced it"
        )
    }
}

@Suite("The whole path, end to end")
struct IntegrationPathTests {
    /// The check no unit test can make.
    ///
    /// Each module can pass its own tests and still disagree at the boundary — or quietly reach for
    /// `JSONSerialization` or the SDK's decoder and bypass the ordered representation entirely,
    /// which nothing in a single file would notice. So this runs the whole public path over one
    /// input carrying **reordered object members** and **unmodeled tool fields**, and asserts both
    /// survive from the config on disk to the tool list a client would be served.
    @Test("reordered members and unmodeled fields survive config to served tool list")
    func wholePathPreservesOrderAndUnknownFields() async throws {
        let fileSystem = MemoryFileSystem()

        // 1. A config whose env keys are deliberately out of order.
        let configText = """
        {"port":8879,"mcpServers":{"alpha":{"command":"node","args":["s.js"],"env":{"Z":"1","A":"2"}}}}
        """
        fileSystem.seed(configText, atPath: "/home/servers.json")
        let loaded = try ConfigLoader.load(
            options: ConfigLoader.Options(configPath: "/home/servers.json"),
            home: RouterHome(root: "/home"),
            fileSystem: fileSystem
        )
        let upstream = try #require(loaded.config.upstreams.first)
        let hash = UpstreamHash.hash(upstream)

        // 2. A cold manifest, then one round of bookkeeping over a tool with an unmodeled member
        //    and a schema whose members are not in sorted order.
        var manifest = ManifestIO.load(path: "/home/manifest.json", fileSystem: fileSystem).manifest
        let toolText = #"{"name":"run","description":"runs","inputSchema":{"z":1,"a":2},"x-vendor":"keep"}"#
        let tool = try #require(try CachedTool(JSONParser.parse(toolText)))
        let report = ManifestBookkeeping.build(
            manifest: &manifest,
            upstreams: [upstream],
            nowMilliseconds: { 1_755_100_000_123 },
            observe: { _ in .tools([tool]) }
        )
        #expect(report.built == ["alpha (1 tools)"])

        // 3. Save, and reload through the store rather than the loader.
        try ManifestIO.save(manifest, toPath: "/home/manifest.json", fileSystem: fileSystem)
        let store = ManifestStore(
            path: "/home/manifest.json",
            fileSystem: fileSystem,
            clock: ManualClock(milliseconds: 10000)
        )

        let reloaded = await store.current()
        let entry = try #require(reloaded.entry(named: "alpha"))
        #expect(entry.hash == JSString(hash), "the config identity survived the round trip")

        // 4. The digest is still the one taken over the unsorted schema.
        let cachedTool = try #require(entry.tools.first)
        ManifestVectors.expectSameBytes(
            JSStringify.compact(cachedTool.value),
            toolText,
            "the tool came back exactly as it went in"
        )
        #expect(
            entry.digest == JSString(ToolsDigest.digest(of: [tool])),
            "recomputing the digest from the reloaded cache agrees with the stored one"
        )

        // 5. And the served list still carries the unmodeled member.
        let union = ToolUnion.unionTools(manifest: reloaded, upstreams: [upstream], cwd: nil)
        let served = try #require(union.first)
        #expect(served.name == JSString("alpha__run"))
        #expect(served.descriptionText == JSString("[alpha] runs"))
        #expect(
            served.rawMember("x-vendor") == .string(JSString("keep")),
            "an unmodeled field reached the client's tool list, which is the whole point of A18"
        )
        #expect(
            JSStringify.compact(served.value).contains(#""inputSchema":{"z":1,"a":2}"#),
            "and the schema members are still in the order the server sent them"
        )
    }

    /// D3's fault injection: a process killed between the temp write and the rename must leave the
    /// previous file intact, because a truncated `servers.json` is exactly the unrecognisable shape
    /// D1 exists to reject.
    @Test("a write interrupted before the rename leaves the previous file untouched")
    func interruptedWriteLeavesTheOriginal() throws {
        let fileSystem = MemoryFileSystem()
        let original = #"{"port":1,"mcpServers":{"a":{"command":"x"}},"startupTimeoutMs":9}"#
        fileSystem.seed(original, atPath: "/home/servers.json")
        fileSystem.fail("moveItem")

        #expect(throws: (any Error).self) {
            try ConfigWriter.write(
                servers: [],
                port: 2,
                host: "h",
                idleMs: 3,
                toPath: "/home/servers.json",
                fileSystem: fileSystem
            )
        }
        #expect(
            fileSystem.contents(atPath: "/home/servers.json") == original,
            "the live server list is still the one that was there"
        )
    }
}
