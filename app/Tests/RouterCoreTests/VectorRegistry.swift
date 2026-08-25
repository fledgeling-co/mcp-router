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

/// A vector that must carry a particular input, not merely exist under a particular name.
struct PinnedInput: Sendable {
    let file: String
    let id: String
    let member: String
    let text: String

    init(_ file: String, _ id: String, _ member: String, _ text: String) {
        self.file = file
        self.id = id
        self.member = member
        self.text = text
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

    /// The sub-requirements the *acceptance clauses* name one by one, as opposed to the N and D
    /// rows above.
    ///
    /// An out-of-family review made the distinction that earns this table its place: several
    /// clauses list branches or cases explicitly — A26's six bookkeeping branches, A27's placard
    /// and description cases, A28's five lexical inputs — and the tests iterated whatever the
    /// corpus happened to contain. An easier corpus therefore passed them all. Requiring the cases
    /// by name is the difference between "the vectors present were compared" and "the cases the
    /// clause is about were compared".
    static let clauseVectors: [NamedVector] = [
        // A26 — every buildManifest branch, not merely the destructive one N8 already pins.
        NamedVector("A26", "build-manifest", "first-sight-approves"),
        NamedVector("A26", "build-manifest", "equal-digest-clears-error-and-pending"),
        NamedVector("A26", "build-manifest", "changed-digest-holds-pending"),
        NamedVector("A26", "build-manifest", "force-bypasses-staleness"),
        NamedVector("A26", "build-manifest", "removed-upstreams-stay"),
        NamedVector("A26", "build-manifest", "not-stale-is-skipped"),
        // A27 — the placard rules and the empty-description fallback.
        NamedVector("A27", "union-tools", "description-falls-back-to-name"),
        NamedVector("A27", "union-tools", "declared-placard"),
        NamedVector("A27", "union-tools", "entry-error-placard-with-tools"),
        NamedVector("A27", "union-tools", "empty-error-no-placard"),
        NamedVector("A27", "union-tools", "other-members-survive"),
        // A28 — all five lexical cases, including the two the clause says are NOT normalised.
        NamedVector("A28", "visible-to", "exact-match"),
        NamedVector("A28", "visible-to", "dotdot-not-normalised"),
        NamedVector("A28", "visible-to", "doubled-separator-not-normalised"),
        NamedVector("A28", "visible-to", "case-sensitive"),
        // A25 — the four entries that are CURRENT, which is the half a true-case test misses.
        NamedVector("A25", "is-stale", "current-missing-digest"),
        NamedVector("A25", "is-stale", "current-empty-tools"),
        NamedVector("A25", "is-stale", "current-with-pending"),
        NamedVector("A25", "is-stale", "current-empty-error"),
        // M29 — a server that is declared and not served. Named rather than merely present,
        // because a corpus that kept the count and dropped these four would still pass the floor
        // while proving nothing about the switch.
        //
        // The union cases are the three ways a disabled server could leak — a fully populated
        // manifest entry, a declared placard that normally keeps a server listed, and a caller
        // standing inside the server's own project — plus the negative control that says the
        // predicate is not simply refusing everything.
        NamedVector("M29", "union-tools", "disabled-withholds-populated-tools"),
        NamedVector("M29", "union-tools", "disabled-outranks-declared-placard"),
        NamedVector("M29", "union-tools", "disabled-inside-its-own-project"),
        NamedVector("M29", "union-tools", "disabled-false-still-serves"),
        // The digest must not move when the switch does, or re-enabling re-spawns the process the
        // user turned off to learn what the router already knew.
        NamedVector("M29", "upstream-hash", "excluded-disabled"),
        NamedVector("M29", "parse-server", "stdio-disabled"),
        NamedVector("M29", "parse-server", "http-disabled"),
        NamedVector("M29", "parse-server", "disabled-truthy-string-uncoerced")
    ]

    /// What a named vector must actually CONTAIN.
    ///
    /// Requiring an id proves a case with that name exists; it does not prove the case carries the
    /// input the clause names. `split-1` could hold anything and still satisfy every check above,
    /// which is the last way a corpus can keep its shape while losing its meaning.
    static let pinnedInputs: [PinnedInput] = [
        PinnedInput("split-tool-name", "split-1", "input", "a__b__c"), // N4, first separator
        PinnedInput("split-tool-name", "split-2", "input", "a____b"), // N4, tool is __b
        PinnedInput("visible-to", "trailing-slash-project", "cwd", "/a/b/c"), // N5
        PinnedInput("visible-to", "prefix-needs-separator", "cwd", "/a/bc"), // N5, must NOT match
        // M29 — the case is only worth naming if it still carries the uncoerced value. `parseServer`
        // copies `disabled` through as written, which is why `describe()` reports `!!u.disabled`
        // rather than reading the typed field; a case quietly rewritten to `true` would agree with
        // a port that coerced on the way in.
        PinnedInput("parse-server", "disabled-truthy-string-uncoerced", "name", "a")
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
    ///
    /// R1 left this at 224. R3 ports three more reference modules, and a port that added no vectors
    /// would be claiming a parity it never measured — so B76 requires this number to *rise*, not
    /// merely to hold. The 128 added here are the control API's routing predicate, `Number`,
    /// `localeCompare`, `basename`, and the two `?limit=` pipelines, each driven from the reference
    /// or from the engine whose semantics the Swift reimplements.
    /// R5 adds the six auth-page vectors, so the floor rises again to 358: the ratchet is the
    /// point — a floor left at 352 would let the auth corpus be deleted without failing.
    /// M29 adds nine — four `union-tools`, four `parse-server` and one `upstream-hash` — for a
    /// server that is declared and not served, so the floor rises to 367 for the same reason.
    static let executedFloor = 367

    /// B81. A bare total is satisfied by any unrelated vectors, so the auth corpus is asserted
    /// **by name** as well as by count — the substitute out-of-family gate found that a floor alone
    /// would pass with forty vectors that have nothing to do with auth.
    @Test("the auth vectors are registered, non-empty, and fully compared")
    func authVectorsAreCountedByName() async throws {
        let authFiles = VectorRegistry.files.filter { $0.file.hasPrefix("auth-") }
        #expect(!authFiles.isEmpty, "no auth vector file is registered")
        var authExecuted = 0
        for registered in authFiles {
            let cases = try ManifestVectors.cases(registered.file)
            #expect(!cases.isEmpty, "\(registered.file) is registered but empty")
            let compared = try await registered.compare(cases)
            #expect(compared == cases.count, "\(registered.file): \(compared) of \(cases.count)")
            authExecuted += compared
        }
        print("PARITY-VECTORS-AUTH: \(authExecuted)")
        #expect(authExecuted >= 6, "the auth corpus executed \(authExecuted) cases")
    }

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

    /// The clause-level sub-requirements. Separate from the N/D rows because these come from the
    /// acceptance criteria enumerating branches, and a test that iterates whatever the corpus holds
    /// passes just as happily on a corpus with the hard branches removed.
    @Test("every case an acceptance clause names by hand is present")
    func everyClauseNamedCaseIsPresent() throws {
        var byFile: [String: Set<String>] = [:]
        for registered in VectorRegistry.files {
            let cases = try ManifestVectors.cases(registered.file)
            byFile[registered.file] = Set(cases.compactMap { ManifestVectors.text($0.member("id")) })
        }
        for named in VectorRegistry.clauseVectors {
            #expect(
                byFile[named.file]?.contains(named.id) == true,
                "\(named.row) needs \(named.file)/\(named.id), which is not in the corpus"
            )
        }
    }

    /// A named vector must carry the input its clause names, not merely the name.
    ///
    /// Everything above constrains the corpus's *shape* — which ids exist, that none duplicates
    /// another, that each is compared. None of it constrains what an id contains, so `split-1`
    /// could hold `x__y` and every check would still pass while N4's first-separator rule went
    /// untested.
    @Test("every pinned vector carries the exact input its clause names")
    func pinnedVectorsCarryTheirInput() throws {
        for pin in VectorRegistry.pinnedInputs {
            let cases = try ManifestVectors.cases(pin.file)
            guard let match = cases.first(where: {
                ManifestVectors.text($0.member("id")) == pin.id
            }) else {
                Issue.record("\(pin.file)/\(pin.id) is not in the corpus")
                continue
            }
            #expect(
                ManifestVectors.text(match.member(pin.member)) == pin.text,
                "\(pin.file)/\(pin.id) must carry \(pin.member) == \(pin.text)"
            )
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
