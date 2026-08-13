import Foundation
import Testing
@testable import RouterCore

/// The registered vector files, and the assertion that consumes each one.
///
/// Split out of `VectorRegistry.swift` so neither file outgrows the repo's length limits: the
/// registry proper holds the named-input table and the attestation tests, this holds the consumers.
extension VectorRegistry {
    static let files: [RegisteredVectorFile] = [
        RegisteredVectorFile(
            file: "json-roundtrip", rows: ["N7"], consumer: "JSONParityTests.compactRoundTrip"
        ) { cases in
            for testCase in cases {
                let value = try JSONParser.parse(ManifestVectors.text(testCase.member("text")) ?? "")
                ManifestVectors.expectSameBytes(
                    JSStringify.compact(value),
                    ManifestVectors.text(testCase.member("compact")) ?? "",
                    "registry/json-compact"
                )
                ManifestVectors.expectSameBytes(
                    JSStringify.prettyTwoSpace(value),
                    ManifestVectors.text(testCase.member("pretty")) ?? "",
                    "registry/json-pretty"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "string-ordering", rows: ["N1"], consumer: "JSONParityTests.stringOrdering"
        ) { cases in
            for testCase in cases {
                let input = (testCase.member("input")?.asArray ?? []).compactMap(\.asString)
                let expected = (testCase.member("sorted")?.asArray ?? []).compactMap(\.asString)
                #expect(input.sorted() == expected, "registry/string-ordering")
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "parse-server", rows: ["N12", "N13"], consumer: "ConfigParityTests.parseServer"
        ) { cases in
            for testCase in cases {
                let parsed = ServerParser.parse(
                    name: ManifestVectors.text(testCase.member("name")) ?? "",
                    raw: testCase.member("raw") ?? .null
                )
                switch parsed {
                case let .skipped(reason):
                    #expect(
                        reason == ManifestVectors.text(testCase.member("reason")),
                        "registry/parse-server"
                    )
                case let .upstream(upstream):
                    #expect(testCase.member("reason") == .null, "registry/parse-server unexpected accept")
                    #expect(
                        UpstreamHash.hash(upstream) == ManifestVectors.text(testCase.member("hash")),
                        "registry/parse-server hash"
                    )
                }
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "upstream-hash", rows: ["N1", "N2"], consumer: "ConfigParityTests.upstreamHash"
        ) { cases in
            for testCase in cases {
                guard let raw = testCase.member("upstream") else { continue }
                let upstream = ManifestVectors.upstream(raw)
                #expect(
                    UpstreamHash.hash(upstream) == ManifestVectors.text(testCase.member("hash")),
                    "registry/upstream-hash \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "self-reference", rows: ["N9"], consumer: "ConfigParityTests.selfReference"
        ) { cases in
            for testCase in cases {
                let result = SelfReference.isSelfReference(
                    name: ManifestVectors.text(testCase.member("name")) ?? "",
                    raw: testCase.member("raw") ?? .null,
                    port: Int(testCase.member("port")?.asNumber ?? 0)
                )
                #expect(
                    result == (testCase.member("result")?.asBool ?? false),
                    "registry/self-reference \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "url-parse", rows: ["N9", "N12"], consumer: "ConfigParityTests.urlParsing"
        ) { cases in
            for testCase in cases {
                let parsed = JSURL(ManifestVectors.text(testCase.member("input")) ?? "")
                let expectedOK = testCase.member("ok")?.asBool ?? false
                #expect((parsed != nil) == expectedOK, "registry/url-parse")
                if let parsed {
                    #expect(parsed.host == ManifestVectors.text(testCase.member("hostname")))
                    #expect(parsed.port == ManifestVectors.text(testCase.member("port")))
                }
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "load-config", rows: ["N3", "N10"], consumer: "ConfigPrecedenceParityTests"
        ) { cases in
            for testCase in cases {
                let fileSystem = MemoryFileSystem()
                let path = "/home/servers.json"
                fileSystem.seed(ManifestVectors.text(testCase.member("text")) ?? "", atPath: path)
                let options = testCase.member("opts")
                let loaded = try ConfigLoader.load(
                    options: ConfigLoader.Options(
                        configPath: path,
                        port: options?.member("port")?.asNumber.map(Int.init),
                        host: ManifestVectors.text(options?.member("host")),
                        idleMs: options?.member("idleMs")?.asNumber.map(Int.init)
                    ),
                    home: RouterHome(root: "/home"),
                    fileSystem: fileSystem
                )
                let id = ManifestVectors.text(testCase.member("id")) ?? ""
                #expect(loaded.config.port == Int(testCase.member("port")?.asNumber ?? -1), "port/\(id)")
                #expect(loaded.config.host == ManifestVectors.text(testCase.member("host")), "host/\(id)")
                #expect(loaded.config.idleMs == Int(testCase.member("idleMs")?.asNumber ?? -1), "idle/\(id)")
                #expect(
                    loaded.config
                        .startupTimeoutMs == Int(testCase.member("startupTimeoutMs")?.asNumber ?? -1),
                    "startup/\(id)"
                )
                let skipped = (testCase.member("skipped")?.asArray ?? [])
                    .compactMap { ManifestVectors.text($0) }
                #expect(loaded.skipped == skipped, "skipped/\(id)")
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "tools-digest", rows: ["N1", "N6", "N7"], consumer: "ToolsDigestParityTests"
        ) { cases in
            for testCase in cases {
                #expect(
                    ToolsDigest.digest(of: ManifestVectors.tools(testCase.member("tools")))
                        == ManifestVectors.text(testCase.member("digest")),
                    "registry/tools-digest \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "diff-tools", rows: ["N11"], consumer: "DiffToolsParityTests"
        ) { cases in
            for testCase in cases {
                let changes = DiffTools.diff(
                    before: ManifestVectors.tools(testCase.member("before")),
                    after: ManifestVectors.tools(testCase.member("after"))
                )
                // The registry checks the invisible report and the change count; the full JSON
                // projection is compared in DiffToolsParityTests.
                let recorded = ManifestVectors.text(testCase.member("diff")) ?? ""
                let expectedCount = (try? JSONParser.parse(recorded))?.asArray?.count ?? -1
                #expect(
                    changes.count == expectedCount,
                    "registry/diff-tools \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
                for change in changes where change.invisible != nil {
                    #expect(recorded.contains("invisible"), "an invisible report the reference did not make")
                }
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "visible-to", rows: ["N5"], consumer: "ToolUnionParityTests.visibilityMatches"
        ) { cases in
            for testCase in cases {
                guard let raw = testCase.member("upstream") else { continue }
                #expect(
                    ToolUnion.visibleTo(
                        ManifestVectors.upstream(raw),
                        cwd: ManifestVectors.text(testCase.member("cwd"))
                    ) == (testCase.member("visible")?.asBool ?? false),
                    "registry/visible-to \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "split-tool-name", rows: ["N4"], consumer: "ToolUnionParityTests.splitMatches"
        ) { cases in
            for testCase in cases {
                let split = ToolUnion.splitToolName(ManifestVectors.text(testCase.member("input")) ?? "")
                #expect(split?.server == ManifestVectors.text(testCase.member("server")), "registry/split")
                #expect(split?.tool == ManifestVectors.text(testCase.member("tool")), "registry/split")
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "is-stale", rows: ["A25"], consumer: "ToolUnionParityTests.stalenessMatches"
        ) { cases in
            for testCase in cases {
                guard let raw = testCase.member("upstream") else { continue }
                #expect(
                    ToolUnion.isStale(
                        ManifestVectors.manifest(servers: testCase.member("servers")),
                        ManifestVectors.upstream(raw)
                    ) == (testCase.member("stale")?.asBool ?? false),
                    "registry/is-stale \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "union-tools", rows: ["N5", "N8"], consumer: "ToolUnionParityTests.unionMatches"
        ) { cases in
            for testCase in cases {
                let union = ToolUnion.unionTools(
                    manifest: ManifestVectors.manifest(servers: testCase.member("servers")),
                    upstreams: (testCase.member("upstreams")?.asArray ?? []).map(ManifestVectors.upstream),
                    cwd: ManifestVectors.text(testCase.member("cwd"))
                )
                ManifestVectors.expectSameBytes(
                    JSStringify.compact(.array(union.map(\.value))),
                    ManifestVectors.text(testCase.member("union")) ?? "",
                    "registry/union \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "manifest-parse", rows: ["D2"], consumer: "ManifestIOParityTests.loadMatches"
        ) { cases in
            for testCase in cases {
                let fileSystem = MemoryFileSystem()
                fileSystem.seed(ManifestVectors.text(testCase.member("text")) ?? "", atPath: "/m.json")
                let load = ManifestIO.load(path: "/m.json", fileSystem: fileSystem)
                ManifestVectors.expectSameBytes(
                    JSStringify.compact(load.manifest.value),
                    ManifestVectors.text(testCase.member("loaded")) ?? "",
                    "registry/manifest-parse \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "manifest-missing", rows: ["D2"], consumer: "ManifestIOParityTests.coldIsDistinguishable"
        ) { cases in
            for testCase in cases {
                let load = ManifestIO.load(path: "/nowhere.json", fileSystem: MemoryFileSystem())
                ManifestVectors.expectSameBytes(
                    JSStringify.compact(load.manifest.value),
                    ManifestVectors.text(testCase.member("loaded")) ?? "",
                    "registry/manifest-missing"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "build-manifest", rows: ["N8"], consumer: "ManifestBookkeepingParityTests"
        ) { cases in
            for testCase in cases {
                guard let raw = testCase.member("upstream") else { continue }
                var manifest = ManifestVectors.manifest(servers: testCase.member("servers"))
                let observed = testCase.member("observation")
                let observation: ManifestBookkeeping.Observation =
                    if let message = ManifestVectors.text(observed?.member("error")) {
                        .failure(message: message)
                    } else {
                        .tools(ManifestVectors.tools(observed?.member("tools")))
                    }
                let stamp = testCase.member("builtAtMs")?.asNumber ?? 0
                _ = ManifestBookkeeping.build(
                    manifest: &manifest,
                    upstreams: [ManifestVectors.upstream(raw)],
                    force: testCase.member("force")?.asBool ?? false,
                    nowMilliseconds: { stamp },
                    observe: { _ in observation }
                )
                ManifestVectors.expectSameBytes(
                    JSStringify.compact(manifest.value),
                    ManifestVectors.text(testCase.member("manifest")) ?? "",
                    "registry/build \(ManifestVectors.text(testCase.member("id")) ?? "")"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "iso8601", rows: ["A30"], consumer: "LogParityTests.timestampsMatch"
        ) { cases in
            for testCase in cases {
                ManifestVectors.expectSameBytes(
                    JSDate.iso8601(milliseconds: testCase.member("ms")?.asNumber ?? 0),
                    ManifestVectors.text(testCase.member("text")) ?? "",
                    "registry/iso8601"
                )
            }
            return cases.count
        },

        RegisteredVectorFile(
            file: "log-line", rows: ["D4", "D5", "A30"], consumer: "LogParityTests.linesMatch"
        ) { cases in
            for testCase in cases {
                let id = ManifestVectors.text(testCase.member("id")) ?? ""
                guard let event = LogEventMapping.event(for: id) else {
                    Issue.record("no log event is mapped for vector \(id)")
                    continue
                }
                let sink = RecordingSink()
                let log = RouterLog(
                    sink: sink,
                    fileSystem: MemoryFileSystem(),
                    clock: ManualClock(milliseconds: 1_755_100_000_123),
                    verbose: id != "debug-suppressed-when-quiet"
                )
                await log.log(event)
                ManifestVectors.expectSameBytes(
                    sink.text,
                    ManifestVectors.text(testCase.member("line")) ?? "",
                    "registry/log-line \(id)"
                )
            }
            return cases.count
        }
    ]
}
