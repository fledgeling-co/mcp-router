import Foundation
import Testing
@testable import RouterCore

/// One vector file, the rows it exists for, and the assertion that consumes it.
///
/// `compare` returns **how many cases it actually compared**. That return value is the point of the
/// whole structure: counting the cases in a file proves nothing, because a decoded-but-never-
/// compared vector is indistinguishable from a checked one, and a mislabelled or placeholder case
/// passes a name check. A consumer that has to report its own execution count cannot quietly skip.
struct RegisteredVectorFile: Sendable {
    let file: String
    let rows: [String]
    let consumer: String
    /// `@Sendable` because the registry is a `static let`: under Swift 6 strict concurrency a shared
    /// static must be `Sendable`, and the closure is what makes the struct non-`Sendable` otherwise.
    /// Every consumer builds its own fixtures inside the closure and captures nothing, so this
    /// costs nothing and is what the code already does.
    let compare: @Sendable ([JSONValue]) async throws -> Int
}

/// An adversarial input the spec names, and the vector that carries it. A named type rather than a
/// bare triple so the three strings cannot be transposed at a call site.
struct NamedVector: Sendable {
    let row: String
    let file: String
    let id: String

    init(_ row: String, _ file: String, _ id: String) {
        self.row = row
        self.file = file
        self.id = id
    }
}

/// The corpus, and what each part of it is for.
enum VectorRegistry {
    // MARK: - Named adversarial inputs (spec A40)

    /// Every input named in N1–N13 and D1–D5, by the vector that carries it.
    ///
    /// This is what stops the corpus quietly shrinking to the easy cases. A port that drops the
    /// UTF-16 ordering pair or the duplicate-name pair still passes every remaining fixture, which
    /// is exactly the failure mode the out-of-family review demonstrated with working code.
    static let namedVectors: [NamedVector] = [
        NamedVector("N1", "upstream-hash", "env-utf16-ordering"),
        NamedVector("N1", "upstream-hash", "header-utf16-ordering"),
        NamedVector("N1", "string-ordering", "ordering-2"),
        NamedVector("N1", "tools-digest", "utf16-name-ordering"),
        NamedVector("N2", "upstream-hash", "args-order-za"),
        NamedVector("N2", "upstream-hash", "args-order-az"),
        NamedVector("N3", "load-config", "explicit-zeroes-honoured"),
        NamedVector("N3", "load-config", "option-zero-outranks-the-file"),
        NamedVector("N4", "split-tool-name", "split-1"), // a__b__c
        NamedVector("N4", "split-tool-name", "split-2"), // a____b
        NamedVector("N5", "visible-to", "trailing-slash-project"),
        NamedVector("N5", "visible-to", "empty-project-matches-everything"),
        NamedVector("N5", "visible-to", "prefix-needs-separator"),
        NamedVector("N6", "tools-digest", "duplicate-names-ab"),
        NamedVector("N6", "tools-digest", "duplicate-names-ba"),
        NamedVector("N7", "tools-digest", "schema-order-za"),
        NamedVector("N7", "tools-digest", "schema-order-az"),
        NamedVector("N7", "json-roundtrip", "member-order-za"),
        NamedVector("N7", "json-roundtrip", "member-order-az"),
        NamedVector("N8", "build-manifest", "failure-destroys-approved-tools"),
        NamedVector("N8", "union-tools", "unreachable-placard-after-failure"),
        NamedVector("N9", "self-reference", "default-port-80"),
        NamedVector("N9", "self-reference", "default-port-443"),
        NamedVector("N10", "load-config", "skipped-follow-enumeration-order"),
        NamedVector("N11", "diff-tools", "invisible-u2066-negative"),
        NamedVector("N11", "diff-tools", "invisible-zero-width"),
        NamedVector("N12", "parse-server", "url-ftp-scheme-accepted"),
        NamedVector("N13", "parse-server", "sse-stays-sse"),
        // D1's divergence is that Swift errors where the reference loads nothing, so its evidence
        // is a red-green test rather than a recorded value — the reference cannot be its own oracle
        // for a deliberate difference. The vectors below are the inputs those tests use.
        NamedVector("D1", "manifest-parse", "servers-array-accepted"),
        NamedVector("D2", "manifest-parse", "not-json"),
        NamedVector("D3", "manifest-parse", "unknown-top-level-preserved"),
        NamedVector("D4", "log-line", "manifest-unreadable"),
        NamedVector("D5", "log-line", "server-index-failed")
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
            let message = "\(registered.file): \(compared) of \(cases.count) cases were "
                + "compared by \(registered.consumer)"
            #expect(compared == cases.count, "\(message)")
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
    func everyNamedAdversarialInputIsPresent() throws {
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
    func everyVectorFileOnDiskIsRegistered() {
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
