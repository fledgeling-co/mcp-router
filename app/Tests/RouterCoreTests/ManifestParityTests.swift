import Foundation
import Testing
@testable import RouterCore

/// Reads a vector file with the item's **own** parser rather than `JSONDecoder`.
///
/// That is not a stylistic choice. Half of what these vectors record is object member order — a
/// tool's schema, a cached entry's fields — and `JSONDecoder` discards it. Decoding the corpus with
/// a type that cannot represent the property under test would make every ordering assertion pass
/// for free.
enum ManifestVectors {
    static func cases(_ name: String) throws -> [JSONValue] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Vectors")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        else {
            Issue.record("vector file \(name).json is missing — the corpus cannot shrink silently")
            throw Vectors.VectorError.missing(name)
        }
        let root = try JSONParser.parse(Data(contentsOf: url))
        guard let list = root.member("cases")?.asArray else {
            throw Vectors.VectorError.missing("\(name).cases")
        }
        return list
    }

    static func text(_ value: JSONValue?) -> String? {
        value?.asString?.string
    }

    static func tools(_ value: JSONValue?) -> [CachedTool] {
        (value?.asArray ?? []).compactMap { CachedTool($0) }
    }

    /// Rebuilds an `UpstreamConfig` from the projected shape the generator writes.
    ///
    /// `raw` is the whole object, because ``UpstreamHash`` hashes the reference's own expressions
    /// over the parsed config rather than a normalised view of it.
    static func upstream(_ value: JSONValue) -> UpstreamConfig {
        let transport = ServerTransport(rawValue: text(value.member("transport")) ?? "stdio") ?? .stdio
        var placard: Placard?
        if let declared = value.member("placard"), declared.isObject {
            placard = Placard(
                reason: text(declared.member("reason")) ?? "",
                substitute: text(declared.member("substitute")),
                until: text(declared.member("until"))
            )
        }
        return UpstreamConfig(
            name: text(value.member("name")) ?? "",
            transport: transport,
            raw: value,
            idleMs: value.member("idleMs")?.asNumber.map(Int.init),
            startupTimeoutMs: value.member("startupTimeoutMs")?.asNumber.map(Int.init),
            projects: value.member("projects")?.asArray.map { $0.compactMap { text($0) } },
            warm: value.member("warm")?.asBool,
            placard: placard,
            command: text(value.member("command")),
            args: value.member("args")?.asArray?.compactMap { text($0) } ?? [],
            env: value.member("env")?.objectEntries ?? [],
            cwd: text(value.member("cwd")),
            url: text(value.member("url")),
            headers: value.member("headers")?.objectEntries ?? [],
            oauth: value.member("oauth")?.asBool
        )
    }

    /// Builds a manifest from a `servers` object, the shape every manifest vector carries.
    static func manifest(servers: JSONValue?) -> Manifest {
        Manifest(members: [
            JSONMember(key: "version", value: .number(1)),
            JSONMember(key: "servers", value: servers ?? .object([]))
        ])
    }

    static func expectSameBytes(_ actual: String, _ expected: String, _ label: String) {
        #expect(
            Array(actual.utf8) == Array(expected.utf8),
            "\(label): produced \(actual.debugDescription), expected \(expected.debugDescription)"
        )
    }
}

@Suite("Tool-surface digest parity with src/manifest.ts")
struct ToolsDigestParityTests {
    @Test("every digest matches the reference over the whole corpus")
    func digestsMatch() throws {
        let cases = try ManifestVectors.cases("tools-digest")
        #expect(!cases.isEmpty)
        for testCase in cases {
            let id = ManifestVectors.text(testCase.member("id")) ?? "?"
            let tools = ManifestVectors.tools(testCase.member("tools"))
            let expected = ManifestVectors.text(testCase.member("digest")) ?? ""
            #expect(ToolsDigest.digest(of: tools) == expected, "digest/\(id)")
        }
    }

    /// N6. Two tools sharing a name keep arrival order, so reversing them is a different surface.
    /// An implementation using Swift's `sorted(by:)` without carrying the index would pass this
    /// only by luck, and differently on a different array size.
    @Test("two tools with the same name hash differently when their order is reversed")
    func stableSortIsObservable() throws {
        let cases = try ManifestVectors.cases("tools-digest")
        let forward = try #require(cases
            .first { ManifestVectors.text($0.member("id")) == "duplicate-names-ab" })
        let reversed = try #require(cases
            .first { ManifestVectors.text($0.member("id")) == "duplicate-names-ba" })
        let a = ToolsDigest.digest(of: ManifestVectors.tools(forward.member("tools")))
        let b = ToolsDigest.digest(of: ManifestVectors.tools(reversed.member("tools")))
        #expect(a != b, "a stable sort keeps equal names in arrival order, so these must differ")
        #expect(a == ManifestVectors.text(forward.member("digest")))
        #expect(b == ManifestVectors.text(reversed.member("digest")))
    }

    /// N7. Canonicalising the schema on the way in would make these agree, and would silently
    /// change the digest of every server whose schema is not already sorted.
    @Test("reordering schema members changes the digest")
    func schemaMemberOrderIsObservable() throws {
        let cases = try ManifestVectors.cases("tools-digest")
        let za = try #require(cases.first { ManifestVectors.text($0.member("id")) == "schema-order-za" })
        let az = try #require(cases.first { ManifestVectors.text($0.member("id")) == "schema-order-az" })
        let a = ToolsDigest.digest(of: ManifestVectors.tools(za.member("tools")))
        let b = ToolsDigest.digest(of: ManifestVectors.tools(az.member("tools")))
        #expect(a != b, "schema member order is part of the hashed material")
    }

    /// Sorting is by name only, so the same set in a different order is the same surface.
    @Test("the same tools in a different order hash alike when their names differ")
    func sortIsByNameOnly() throws {
        let cases = try ManifestVectors.cases("tools-digest")
        let ab = try #require(cases.first { ManifestVectors.text($0.member("id")) == "sorted-by-name-ab" })
        let ba = try #require(cases.first { ManifestVectors.text($0.member("id")) == "sorted-by-name-ba" })
        #expect(
            ToolsDigest.digest(of: ManifestVectors.tools(ab.member("tools")))
                == ToolsDigest.digest(of: ManifestVectors.tools(ba.member("tools")))
        )
    }

    @Test("members outside the material do not change the digest")
    func onlyNameDescriptionAndSchemaAreHashed() throws {
        let cases = try ManifestVectors.cases("tools-digest")
        let plain = try #require(cases.first { ManifestVectors.text($0.member("id")) == "single" })
        let decorated = try #require(
            cases.first { ManifestVectors.text($0.member("id")) == "other-members-ignored" }
        )
        #expect(
            ToolsDigest.digest(of: ManifestVectors.tools(plain.member("tools")))
                == ToolsDigest.digest(of: ManifestVectors.tools(decorated.member("tools"))),
            "a changed title or annotation is not a changed tool surface"
        )
    }

    @Test("the input array is not mutated")
    func inputIsNotMutated() {
        let tools = [
            CachedTool(members: [JSONMember(key: "name", value: .string("z"))]),
            CachedTool(members: [JSONMember(key: "name", value: .string("a"))])
        ]
        _ = ToolsDigest.digest(of: tools)
        #expect(tools.first?.name == JSString("z"), "the reference copies before sorting")
    }
}

@Suite("Tool diff parity with src/manifest.ts")
struct DiffToolsParityTests {
    /// The reference's object literal order, key omission included: `JSON.stringify` drops a key
    /// whose value is `undefined`, so an absent description and an absent `invisible` both vanish.
    private func projection(_ change: ToolChange) -> JSONValue {
        var members: [JSONMember] = [JSONMember(key: "kind", value: .string(JSString(change.kind.rawValue)))]
        if let name = change.name { members.append(JSONMember(key: "name", value: name)) }
        switch change.kind {
        case .added:
            if let after = change.after { members.append(JSONMember(key: "after", value: shape(after))) }
        case .changed:
            if let before = change.before { members.append(JSONMember(key: "before", value: shape(before))) }
            if let after = change.after { members.append(JSONMember(key: "after", value: shape(after))) }
        case .removed:
            if let before = change.before { members.append(JSONMember(key: "before", value: shape(before))) }
        }
        if let invisible = change.invisible {
            members.append(
                JSONMember(key: "invisible", value: .array(invisible.map { .string(JSString($0)) }))
            )
        }
        return .object(members)
    }

    private func shape(_ value: ToolShape) -> JSONValue {
        var members: [JSONMember] = []
        if let description = value.description {
            members.append(JSONMember(key: "description", value: description))
        }
        if let schema = value.schema {
            members.append(JSONMember(key: "schema", value: .string(JSString(schema))))
        }
        return .object(members)
    }

    @Test("every diff matches the reference's, structure and ordering included")
    func diffsMatch() throws {
        let cases = try ManifestVectors.cases("diff-tools")
        #expect(!cases.isEmpty)
        for testCase in cases {
            let id = ManifestVectors.text(testCase.member("id")) ?? "?"
            let changes = DiffTools.diff(
                before: ManifestVectors.tools(testCase.member("before")),
                after: ManifestVectors.tools(testCase.member("after"))
            )
            let produced = JSStringify.compact(.array(changes.map(projection)))
            ManifestVectors.expectSameBytes(
                produced,
                ManifestVectors.text(testCase.member("diff")) ?? "",
                "diff/\(id)"
            )
        }
    }

    /// A22 and N11 together. The detector must be neither narrower nor wider than the reference's:
    /// a zero-width space is reported and `U+2066` is not, because it falls in the gap the
    /// reference's ranges leave. Widening it would make R4 read a real improvement as a regression.
    @Test("a zero-width space is reported and U+2066 is not")
    func invisibleSetMatchesExactly() {
        #expect(DiffTools.invisibleIn(.string(JSString("safe\u{200B}text"))) == ["U+200B"])
        #expect(
            DiffTools.invisibleIn(.string(JSString("safe\u{2066}text"))) == nil,
            "U+2066 sits between the 2060-2064 and 206A-206F ranges and is not detected"
        )
        #expect(DiffTools.invisibleIn(.string(JSString("plain"))) == nil)
        #expect(DiffTools.invisibleIn(nil) == nil)
    }

    @Test("invisible codepoints are deduplicated by first occurrence")
    func invisibleDedupeKeepsFirstOccurrence() {
        let text = JSString("\u{200B}\u{FEFF}\u{200B}\u{00AD}")
        #expect(DiffTools.invisibleIn(.string(text)) == ["U+200B", "U+FEFF", "U+00AD"])
    }
}

@Suite("Tool union and visibility parity with src/manifest.ts")
struct ToolUnionParityTests {
    @Test("project visibility is lexical, case-sensitive and never normalised")
    func visibilityMatches() throws {
        let cases = try ManifestVectors.cases("visible-to")
        #expect(!cases.isEmpty)
        for testCase in cases {
            let id = ManifestVectors.text(testCase.member("id")) ?? "?"
            let upstream = try #require(testCase.member("upstream").map(ManifestVectors.upstream))
            let cwd = ManifestVectors.text(testCase.member("cwd"))
            let expected = testCase.member("visible")?.asBool ?? false
            #expect(ToolUnion.visibleTo(upstream, cwd: cwd) == expected, "visibleTo/\(id)")
        }
    }

    @Test("a namespaced tool name splits at the first separator")
    func splitMatches() throws {
        let cases = try ManifestVectors.cases("split-tool-name")
        #expect(!cases.isEmpty)
        for testCase in cases {
            let id = ManifestVectors.text(testCase.member("id")) ?? "?"
            let input = ManifestVectors.text(testCase.member("input")) ?? ""
            let split = ToolUnion.splitToolName(input)
            #expect(split?.server == ManifestVectors.text(testCase.member("server")), "server/\(id) \(input)")
            #expect(split?.tool == ManifestVectors.text(testCase.member("tool")), "tool/\(id) \(input)")
        }
    }

    @Test("staleness matches, including the four entries that are current")
    func stalenessMatches() throws {
        let cases = try ManifestVectors.cases("is-stale")
        #expect(!cases.isEmpty)
        var currentIDs: Set<String> = []
        for testCase in cases {
            let id = ManifestVectors.text(testCase.member("id")) ?? "?"
            let upstream = try #require(testCase.member("upstream").map(ManifestVectors.upstream))
            let manifest = ManifestVectors.manifest(servers: testCase.member("servers"))
            let expected = testCase.member("stale")?.asBool ?? false
            if !expected { currentIDs.insert(id) }
            #expect(ToolUnion.isStale(manifest, upstream) == expected, "isStale/\(id)")
        }
        // Counting to four accepts ANY four false fixtures, so a corpus that dropped the pending
        // case and gained an easier one would still pass. Naming them is what makes this an
        // assertion about the four cases the clause is actually about.
        #expect(
            currentIDs == [
                "current-missing-digest",
                "current-empty-tools",
                "current-with-pending",
                "current-empty-error"
            ],
            "a missing digest, empty tools, a pending surface and an empty error are all CURRENT"
        )
    }

    /// N8's consequence, asserted against the reference rather than reasoned about: a server whose
    /// indexing failed contributes nothing, so the placard the code builds for it is never seen.
    @Test("the served union matches the reference, unreachable placard included")
    func unionMatches() throws {
        let cases = try ManifestVectors.cases("union-tools")
        #expect(!cases.isEmpty)
        for testCase in cases {
            let id = ManifestVectors.text(testCase.member("id")) ?? "?"
            let manifest = ManifestVectors.manifest(servers: testCase.member("servers"))
            let upstreams = (testCase.member("upstreams")?.asArray ?? []).map(ManifestVectors.upstream)
            let union = ToolUnion.unionTools(
                manifest: manifest,
                upstreams: upstreams,
                cwd: ManifestVectors.text(testCase.member("cwd"))
            )
            ManifestVectors.expectSameBytes(
                JSStringify.compact(.array(union.map(\.value))),
                ManifestVectors.text(testCase.member("union")) ?? "",
                "union/\(id)"
            )
        }
    }

    @Test("a failed server's placard is unreachable, and one with tools still shows it")
    func placardReachability() throws {
        let cases = try ManifestVectors.cases("union-tools")
        let failed = try #require(
            cases.first { ManifestVectors.text($0.member("id")) == "unreachable-placard-after-failure" }
        )
        let withTools = try #require(
            cases.first { ManifestVectors.text($0.member("id")) == "entry-error-placard-with-tools" }
        )
        #expect(ManifestVectors.text(failed.member("union")) == "[]", "the reference serves nothing here")
        #expect(
            ManifestVectors.text(withTools.member("union"))?.contains("INOPERATIVE") == true,
            "the placard is reachable only while the tools survive, which the failure path destroys"
        )
    }
}
