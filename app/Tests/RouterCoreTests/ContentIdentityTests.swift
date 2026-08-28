import Foundation
import Testing
@testable import RouterCore

/// A probe with no disk behind it, for the rules that are decisions rather than readings.
struct StubCacheProbe: CacheProbing {
    var entries: [NpxEntry] = []
    var versions: [PluginVersion] = []
    /// The files that exist, and the stamp each currently has.
    var stamps: [(path: String, stamp: String)] = []
    let removed = RemovalLog()

    final class RemovalLog: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []
        func record(_ path: String) {
            lock.lock(); defer { lock.unlock() }
            paths.append(path)
        }

        var all: [String] {
            lock.lock(); defer { lock.unlock() }
            return paths
        }
    }

    func npxEntries() -> [NpxEntry] { entries }
    func pluginVersions() -> [PluginVersion] { versions }
    func fileStamp(_ path: String) -> String? { stamps.first { $0.path == path }?.stamp }
    func removeDirectory(_ path: String) -> String? {
        removed.record(path)
        return nil
    }
}

enum CacheFixture {
    static func upstream(_ name: String, command: String, args: [String]) throws -> UpstreamConfig {
        let quoted = args.map { "\"\($0)\"" }.joined(separator: ",")
        let raw = try JSONParser.parse(#"{"command":"\#(command)","args":[\#(quoted)]}"#)
        guard case let .upstream(parsed) = ServerParser.parse(name: name, raw: raw) else {
            throw CacheFixtureProblem.unparseable(name)
        }
        return parsed
    }

    static func http(_ name: String) throws -> UpstreamConfig {
        let raw = try JSONParser.parse(#"{"type":"http","url":"https://example.test/mcp"}"#)
        guard case let .upstream(parsed) = ServerParser.parse(name: name, raw: raw) else {
            throw CacheFixtureProblem.unparseable(name)
        }
        return parsed
    }

    static func entry(_ directory: String, _ name: String, spec: String, version: String?, bytes: Int?)
        -> NpxEntry {
        NpxEntry(
            directory: directory,
            requested: [NpxRequest(name: name, spec: spec, installedVersion: version)],
            bytes: bytes
        )
    }
}

enum CacheFixtureProblem: Error {
    case unparseable(String)
}

/// R31 — the content component of the manifest key.
///
/// The property under test throughout is the one `UpstreamHash` cannot express: a change that
/// leaves command, args and env identical. Every case here holds the config constant and moves
/// only what is behind it, because a case that changed the config would be testing the identity
/// hash that already worked.
@Suite("R31 — content identity")
struct ContentIdentityTests {
    // MARK: - Parsing

    @Test("R1 — the package spec is found past npx's own flags, including -p's value")
    func specIsFoundPastFlags() {
        #expect(ContentResolution.packageSpec(["-y", "ref-tools-mcp@3.0.3"]) == "ref-tools-mcp@3.0.3")
        #expect(ContentResolution.packageSpec(["-y", "mcp-remote", "https://x.test/mcp"]) == "mcp-remote")
        // `-p pkg cmd` runs `cmd` out of `pkg`, so the flag's VALUE is the package. Skipping it as
        // a flag would resolve `cmd` and digest a package that was never fetched.
        #expect(ContentResolution.packageSpec(["-p", "some-pkg", "some-bin"]) == "some-pkg")
        #expect(ContentResolution.packageSpec(["-y"]) == nil)
    }

    @Test("R2 — a scoped package keeps its leading @")
    func scopedNamesSurvive() {
        #expect(ContentResolution.packageName("ref-tools-mcp@3.0.3") == "ref-tools-mcp")
        #expect(ContentResolution.packageName("@modelcontextprotocol/server-github")
            == "@modelcontextprotocol/server-github")
        #expect(ContentResolution.packageName("@antv/mcp-server-chart@^0.9.10") == "@antv/mcp-server-chart")
        #expect(ContentResolution.packageName("media-gen-pro-mcp@latest") == "media-gen-pro-mcp")
    }

    // MARK: - The property this item exists for

    @Test("R3 — @latest keeps one config hash while its digest moves with the fetched version")
    func floatingSpecMovesWithoutTheConfig() throws {
        let upstream = try CacheFixture.upstream(
            "media-gen-pro", command: "npx", args: ["-y", "media-gen-pro-mcp@latest"]
        )
        let before = StubCacheProbe(entries: [
            CacheFixture.entry("/npx/aaa", "media-gen-pro-mcp", spec: "^0.3.2", version: "0.3.2", bytes: 71)
        ])
        let after = StubCacheProbe(entries: [
            CacheFixture.entry("/npx/aaa", "media-gen-pro-mcp", spec: "^0.3.2", version: "0.4.0", bytes: 74)
        ])
        let first = ContentResolution.resolve(upstream, probe: before)
        let second = ContentResolution.resolve(upstream, probe: after)

        // The identity hash — the key the cache has always had — cannot tell these apart, which is
        // the whole defect. Asserted here rather than assumed, because the content component only
        // earns its place if the thing beside it really is blind.
        #expect(UpstreamHash.hash(upstream) == UpstreamHash.hash(upstream))
        #expect(first.contentClass == .npxPackage)
        #expect(first.digest != nil)
        #expect(first.digest != second.digest)
    }

    @Test("R4 — a rebuilt local entry point moves the digest; an untouched one does not")
    func localFileTracksItsStamp() throws {
        let upstream = try CacheFixture.upstream(
            "dossier", command: "node", args: ["/repo/packages/mcp/dist/index.js"]
        )
        let before = StubCacheProbe(stamps: [(path: "/repo/packages/mcp/dist/index.js", stamp: "120:9.0")])
        let same = StubCacheProbe(stamps: [(path: "/repo/packages/mcp/dist/index.js", stamp: "120:9.0")])
        let rebuilt = StubCacheProbe(stamps: [(path: "/repo/packages/mcp/dist/index.js", stamp: "120:11.0")])

        let first = ContentResolution.resolve(upstream, probe: before)
        #expect(first.contentClass == .localFile)
        #expect(first.source == "/repo/packages/mcp/dist/index.js")
        #expect(ContentResolution.resolve(upstream, probe: same).digest == first.digest)
        // Same size, later mtime — a rebuild that produced identical-length output still moves it.
        #expect(ContentResolution.resolve(upstream, probe: rebuilt).digest != first.digest)
    }

    @Test("R5 — two entries for one package are one digest, and either of them moves it")
    func severalEntriesForOnePackage() throws {
        let upstream = try CacheFixture.upstream(
            "ref-tools-mcp", command: "npx", args: ["-y", "ref-tools-mcp@3.0.3"]
        )
        // Measured on this machine 2026-08-28: `ref-tools-mcp` really does hold two entries, at
        // 154 MB each. npm keys an entry on a hash of the spec string it was handed, which this
        // router cannot compute, so naming the live one would be a guess.
        let both = StubCacheProbe(entries: [
            CacheFixture.entry("/npx/aaa", "ref-tools-mcp", spec: "^3.0.3", version: "3.0.3", bytes: 1),
            CacheFixture.entry("/npx/bbb", "ref-tools-mcp", spec: "^3.0.3", version: "3.0.3", bytes: 2)
        ])
        let secondMoved = StubCacheProbe(entries: [
            CacheFixture.entry("/npx/aaa", "ref-tools-mcp", spec: "^3.0.3", version: "3.0.3", bytes: 1),
            CacheFixture.entry("/npx/bbb", "ref-tools-mcp", spec: "^3.0.3", version: "3.1.0", bytes: 2)
        ])
        let base = ContentResolution.resolve(upstream, probe: both)
        #expect(base.source == "/npx/aaa, /npx/bbb")
        #expect(ContentResolution.resolve(upstream, probe: secondMoved).digest != base.digest)
    }

    // MARK: - What is deliberately NOT movement

    @Test("R6 — an unresolvable upstream carries a reason and is never movement")
    func unresolvedIsNotMovement() throws {
        let http = try CacheFixture.http("mobbin")
        let bare = try CacheFixture.upstream("odd", command: "some-binary", args: ["serve"])
        let uncached = try CacheFixture.upstream(
            "new", command: "npx", args: ["-y", "never-fetched-mcp@1.0.0"]
        )
        let probe = StubCacheProbe()

        for upstream in [http, bare, uncached] {
            let identity = ContentResolution.resolve(upstream, probe: probe)
            #expect(identity.contentClass == .unresolved)
            #expect(identity.digest == nil)
            #expect(identity.reason?.isEmpty == false)
            let verdict = ContentStaleness.verdict(recorded: nil, upstream: upstream, probe: probe)
            #expect(verdict.hasMoved == false)
            if case .unresolvable = verdict {} else {
                Issue.record("an unresolved reading must not read as first sight")
            }
        }
    }

    @Test("R7 — an entry written before this member existed reads as first sight, not as movement")
    func absentRecordIsFirstSight() throws {
        let upstream = try CacheFixture.upstream(
            "dossier", command: "node", args: ["/repo/dist/index.js"]
        )
        let probe = StubCacheProbe(stamps: [(path: "/repo/dist/index.js", stamp: "1:1.0")])
        // Exactly the members the reference writes: no `content` anywhere.
        var legacy = CachedServer(members: [])
        legacy.set("hash", .string(JSString(UpstreamHash.hash(upstream))))
        legacy.set("digest", .string(JSString("abc")))

        let verdict = ContentStaleness.verdict(recorded: legacy, upstream: upstream, probe: probe)
        #expect(verdict.hasMoved == false)
        if case .firstSight = verdict {} else {
            Issue.record("a manifest with no content member must not re-derive every row at once")
        }
    }

    @Test("R8 — recorded, then compared: same is same and moved is moved")
    func recordedThenCompared() throws {
        let upstream = try CacheFixture.upstream(
            "dossier", command: "node", args: ["/repo/dist/index.js"]
        )
        let probe = StubCacheProbe(stamps: [(path: "/repo/dist/index.js", stamp: "1:1.0")])
        var entry = CachedServer(members: [])
        ContentStaleness.record(ContentResolution.resolve(upstream, probe: probe), on: &entry)
        #expect(ContentStaleness.recordedDigest(entry) != nil)
        #expect(ContentStaleness.verdict(recorded: entry, upstream: upstream, probe: probe).hasMoved == false)

        let rebuilt = StubCacheProbe(stamps: [(path: "/repo/dist/index.js", stamp: "2:2.0")])
        let verdict = ContentStaleness.verdict(recorded: entry, upstream: upstream, probe: rebuilt)
        #expect(verdict.hasMoved)
        // `isStale` must be unmoved by all of it: it is the reference's own test, compared against
        // it by the parity harness, and this item adds a component beside it rather than to it.
        var manifest = Manifest.empty
        manifest.setEntry(upstream.name, entry)
        #expect(ToolUnion.isStale(manifest, upstream) == false)
    }
}
