import Foundation
import Testing
@testable import RouterCore

/// One vector file, the rows it exists for, and the assertion that consumes it.
///
/// `compare` returns **how many cases it actually compared**. That return value is the point of the
/// whole structure: counting the cases in a file proves nothing, because a decoded-but-never-
/// compared vector is indistinguishable from a checked one, and a mislabelled or placeholder case
/// passes a name check. A consumer that has to report its own execution count cannot quietly skip.
struct RegisteredVectorFile {
    let file: String
    let rows: [String]
    let consumer: String
    let compare: ([JSONValue]) async throws -> Int
}

/// The corpus, and what each part of it is for.
enum VectorRegistry {
    // MARK: - Named adversarial inputs (spec A40)

    /// Every input named in N1–N13 and D1–D5, by the vector that carries it.
    ///
    /// This is what stops the corpus quietly shrinking to the easy cases. A port that drops the
    /// UTF-16 ordering pair or the duplicate-name pair still passes every remaining fixture, which
    /// is exactly the failure mode the out-of-family review demonstrated with working code.
    static let namedVectors: [(row: String, file: String, id: String)] = [
        ("N1", "upstream-hash", "env-utf16-ordering"),
        ("N1", "upstream-hash", "header-utf16-ordering"),
        ("N1", "string-ordering", "ordering-2"),
        ("N1", "tools-digest", "utf16-name-ordering"),
        ("N2", "upstream-hash", "args-order-za"),
        ("N2", "upstream-hash", "args-order-az"),
        ("N3", "load-config", "explicit-zeroes-honoured"),
        ("N3", "load-config", "option-zero-outranks-the-file"),
        ("N4", "split-tool-name", "split-1"), // a__b__c
        ("N4", "split-tool-name", "split-2"), // a____b
        ("N5", "visible-to", "trailing-slash-project"),
        ("N5", "visible-to", "empty-project-matches-everything"),
        ("N5", "visible-to", "prefix-needs-separator"),
        ("N6", "tools-digest", "duplicate-names-ab"),
        ("N6", "tools-digest", "duplicate-names-ba"),
        ("N7", "tools-digest", "schema-order-za"),
        ("N7", "tools-digest", "schema-order-az"),
        ("N7", "json-roundtrip", "member-order-za"),
        ("N7", "json-roundtrip", "member-order-az"),
        ("N8", "build-manifest", "failure-destroys-approved-tools"),
        ("N8", "union-tools", "unreachable-placard-after-failure"),
        ("N9", "self-reference", "default-port-80"),
        ("N9", "self-reference", "default-port-443"),
        ("N10", "load-config", "skipped-follow-enumeration-order"),
        ("N11", "diff-tools", "invisible-u2066-negative"),
        ("N11", "diff-tools", "invisible-zero-width"),
        ("N12", "parse-server", "url-ftp-scheme-accepted"),
        ("N13", "parse-server", "sse-stays-sse"),
        // D1's divergence is that Swift errors where the reference loads nothing, so its evidence
        // is a red-green test rather than a recorded value — the reference cannot be its own oracle
        // for a deliberate difference. The vectors below are the inputs those tests use.
        ("D1", "manifest-parse", "servers-array-accepted"),
        ("D2", "manifest-parse", "not-json"),
        ("D3", "manifest-parse", "unknown-top-level-preserved"),
        ("D4", "log-line", "manifest-unreadable"),
        ("D5", "log-line", "server-index-failed")
    ]

    // MARK: - The files, and the assertions that consume them

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
                let input = (testCase.member("input")?.asArray ?? []).compactMap { $0.asString }
                let expected = (testCase.member("sorted")?.asArray ?? []).compactMap { $0.asString }
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
                    #expect(reason == ManifestVectors.text(testCase.member("reason")), "registry/parse-server")
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
                    loaded.config.startupTimeoutMs == Int(testCase.member("startupTimeoutMs")?.asNumber ?? -1),
                    "startup/\(id)"
                )
                let skipped = (testCase.member("skipped")?.asArray ?? []).compactMap { ManifestVectors.text($0) }
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

/// Shared so the registry and the log suite cannot drift apart on which event a vector stands for.
enum LogEventMapping {
    static func event(for id: String) -> LogEvent? {
        switch id {
        case "manifest-unreadable": .manifestUnreadable(path: "/p/manifest.json", reason: "bad")
        case "manifest-reloaded": .manifestReloaded(serverCount: 3)
        case "manifest-reload-failed": .manifestReloadFailed(reason: "bad")
        case "manifest-current", "debug-suppressed-when-quiet": .manifestCurrent(server: "alpha")
        case "server-indexed": .serverIndexed(server: "alpha", toolCount: 7)
        case "server-surface-changed": .serverSurfaceChanged(server: "alpha", changeCount: 2)
        case "server-index-failed": .serverIndexFailed(server: "alpha", reason: "spawn failed")
        default: nil
        }
    }
}

@Suite("Vector registry — the corpus cannot shrink, drift or go unread")
struct VectorRegistryTests {
    /// The count `make parity` gates on. Raising it is a deliberate act; a corpus that shrinks below
    /// it fails the build rather than quietly proving less than it did yesterday.
    static let executedFloor = 224

    /// The attestation. Every registered file is loaded, every case is put through the assertion
    /// that consumes it, and the consumer reports how many it compared — so a vector that is
    /// decoded and never checked cannot pass, and neither can a file with no consumer.
    @Test("every registered vector file is loaded and every case in it is compared")
    func everyRegisteredFileIsFullyCompared() async throws {
        var executed = 0
        for registered in VectorRegistry.files {
            let cases = try ManifestVectors.cases(registered.file)
            #expect(!cases.isEmpty, "\(registered.file) is registered but empty")
            let compared = try await registered.compare(cases)
            #expect(
                compared == cases.count,
                "\(registered.file): \(compared) of \(cases.count) cases were compared by \(registered.consumer)"
            )
            executed += compared
        }
        // Read by `make parity`. A count printed by the thing that did the work, not inferred.
        print("PARITY-VECTORS-EXECUTED: \(executed)")
        #expect(
            executed >= Self.executedFloor,
            "the corpus executed \(executed) cases, below the floor of \(Self.executedFloor)"
        )
    }

    /// A40. A corpus that loses the UTF-16 ordering pair or the duplicate-name pair still passes
    /// every remaining fixture, which is the exact failure the out-of-family review demonstrated
    /// with four working-but-wrong implementations.
    @Test("every adversarial input named in N1-N13 and D1-D5 is present")
    func everyNamedAdversarialInputIsPresent() async throws {
        var byFile: [String: Set<String>] = [:]
        for registered in VectorRegistry.files {
            let cases = try ManifestVectors.cases(registered.file)
            byFile[registered.file] = Set(cases.compactMap { ManifestVectors.text($0.member("id")) })
        }
        for named in VectorRegistry.namedVectors {
            #expect(
                byFile[named.file]?.contains(named.id) == true,
                "\(named.row) needs \(named.file)/\(named.id), which is not in the corpus"
            )
        }
        // Every N row and every D row is accounted for by at least one vector.
        let covered = Set(VectorRegistry.namedVectors.map(\.row))
        for row in (1 ... 13).map({ "N\($0)" }) + (1 ... 5).map({ "D\($0)" }) {
            #expect(covered.contains(row), "\(row) has no named vector at all")
        }
    }

    /// A vector cannot be a copy of another wearing a different name. Without this a corpus can
    /// carry the right count and the right ids and still test one input several times.
    @Test("no vector is a duplicate of another in the same file")
    func noVectorDuplicatesAnother() throws {
        for registered in VectorRegistry.files {
            let cases = try ManifestVectors.cases(registered.file)
            var seen: [String: String] = [:]
            for testCase in cases {
                let id = ManifestVectors.text(testCase.member("id")) ?? "?"
                // The payload is everything except the id, so two cases differing only by name
                // collide here.
                let payload = JSStringify.compact(
                    .object(testCase.asObjectMembers?.filter { $0.key != JSString("id") } ?? [])
                )
                let fingerprint = UpstreamHash.digest(of: payload)
                if let previous = seen[fingerprint] {
                    Issue.record("\(registered.file): \(id) is a copy of \(previous)")
                }
                seen[fingerprint] = id
            }
        }
    }

    /// An orphan vector file — one on disk with no consumer — is a file nobody reads, and it is how
    /// a corpus grows a decorative wing.
    @Test("every vector file on disk is registered with a consumer")
    func everyVectorFileOnDiskIsRegistered() throws {
        let onDisk = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Vectors") ?? []
        #expect(!onDisk.isEmpty, "the vectors are not being bundled, so nothing here proves anything")
        let registered = Set(VectorRegistry.files.map(\.file))
        for url in onDisk {
            let name = url.deletingPathExtension().lastPathComponent
            #expect(registered.contains(name), "\(name).json is in the corpus but no assertion consumes it")
        }
        #expect(registered.count == onDisk.count, "registry and corpus differ in size")
    }
}
