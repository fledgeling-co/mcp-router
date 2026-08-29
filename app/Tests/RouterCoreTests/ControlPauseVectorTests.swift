import Foundation
import Testing
@testable import RouterCore

/// The wire request the Mac's *Disable this server* toggle sends, driven through the real handler.
///
/// M37 adds a control, not a capability: `PATCH /servers/:name {"disabled": …}` already existed and
/// ``ControlDisableWriteTests`` already proves the handler honours it. What that file cannot say is
/// that the **app's own request** is the one it honours, because `MCPRouterUI` and `RouterCore`
/// share no target — `Package.swift` keeps the app out of the router's dependency graph on purpose,
/// so that reading `servers.json` directly would have to be added rather than reached for.
///
/// So the two halves share the request instead of a process. `Pins/pause-action.json` holds the
/// method, the path template and the two bodies; `ServersPauseAffordanceTests` asserts the control
/// produces those bytes, and this drives them. Neither half can drift alone, because the file they
/// would have to disagree with is the same file.
///
/// **`Pins/`, not `Vectors/`, and the distinction is a gate's rather than a preference.**
/// `Vectors/` is the parity corpus, and `planning/pin-class-gate.py` refuses any file in it that
/// is not produced by a generator region importing a named export of the TypeScript reference —
/// because a parity vector exists to catch two implementations diverging, and one that re-types
/// its reference cannot see the reference move. This file pins a request the **app** composes.
/// There is no production export to import and no second implementation, so it is not a parity
/// vector and does not belong in that population. It was written into `Vectors/` first and the
/// gate refused it. The completeness property `VectorRegistry` gives that corpus — every case
/// driven, and the consumer reporting its own execution count — is kept here instead, by
/// ``everyPinnedCaseIsDriven``.
///
/// **The read-back is deliberately not the response body**, for the reason
/// ``ControlDisableWriteTests`` gives: `patch` answers with `Describe.row` of its own reloaded
/// upstream, so asserting on the response asks the handler whether it thinks it wrote. Every
/// assertion below re-reads the user's `servers.json` off the filesystem, re-parses it through
/// ``ServerParser``, and asks ``ToolUnion/isServed(_:cwd:)`` — the predicate that decides what a
/// session is actually served.
@Suite("M37 — the app's request, honoured by the router")
struct ControlPauseVectorTests {
    // MARK: - Fixtures

    /// `on` is the control in every case: a handler that wrote to the whole file, or to the wrong
    /// entry, passes every assertion about `off` on its own.
    static let bothLive = #"""
    {"mcpServers":{
      "off":{"command":"/bin/echo","args":["a"]},
      "on":{"command":"/bin/echo","args":["b"]}
    }}
    """#

    static let offAlreadyDisabled = #"""
    {"mcpServers":{
      "off":{"command":"/bin/echo","args":["a"],"disabled":true},
      "on":{"command":"/bin/echo","args":["b"]}
    }}
    """#

    static func config(named name: String) -> String? {
        switch name {
        case "bothLive": bothLive
        case "offAlreadyDisabled": offAlreadyDisabled
        default: nil
        }
    }

    // MARK: - Harness

    static func upstreams(
        from json: String
    ) throws -> [(name: JSString, upstream: UpstreamConfig)] {
        let parsed = try JSONParser.parse(json)
        let entries = parsed.member("mcpServers")?.asObjectMembers ?? []
        var out: [(name: JSString, upstream: UpstreamConfig)] = []
        for entry in entries {
            guard case let .upstream(upstream) = ServerParser.parse(
                name: entry.key.string, raw: entry.value
            ) else { continue }
            out.append((entry.key, upstream))
        }
        return out
    }

    /// Whether a session would be served this server, decided from the config text alone.
    ///
    /// Re-parsed rather than read from `deps.upstreams`: the handler reloads that map itself, so
    /// reading it would ask the handler to confirm its own write. This asks the file.
    static func isServed(_ name: String, in configText: String) throws -> Bool {
        let parsed = try Self.upstreams(from: configText)
        let upstream = try #require(
            parsed.first { $0.name.string == name }?.upstream,
            "\(name) is not in the config at all, so the serving question is not being asked"
        )
        return ToolUnion.isServed(upstream, cwd: nil)
    }

    /// One request through the real handler against a real `servers.json` in a temporary directory.
    ///
    /// Returns the status and the file as re-read from disk — never the handler's own view of what
    /// it wrote.
    static func send(
        method: String, path: String, body: String, startingFrom config: String
    ) async throws -> (status: Int, onDisk: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-vector-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let filePath = directory.appendingPathComponent("servers.json").path
        try Data(config.utf8).write(to: URL(fileURLWithPath: filePath))

        var deps = try PortIdentityTests.deps(upstreams: Self.upstreams(from: config))
        deps.configPath = filePath
        let response = await ControlHandler(token: "t").handle(
            ControlAPIRequest(
                method: method,
                encodedPath: path,
                headers: [
                    (name: "x-mcpr-token", value: "t"),
                    (name: "content-type", value: "application/json")
                ],
                body: Data(body.utf8)
            ), &deps
        )
        return try (response.status, String(contentsOfFile: filePath, encoding: .utf8))
    }

    /// One vector case, driven and read back four ways. Shared with the registry consumer in
    /// `VectorRegistryControlFiles.swift`, so the corpus attestation and this suite cannot make
    /// different claims about the same row.
    @discardableResult
    static func drive(_ testCase: JSONValue) async throws -> String {
        let id = ManifestVectors.text(testCase.member("id")) ?? "?"
        let configName = ManifestVectors.text(testCase.member("config")) ?? ""
        let seed = try #require(Self.config(named: configName), "\(id): no fixture named \(configName)")
        let servedAfter = testCase.member("servedAfter")?.asBool ?? false
        let memberAfter = ManifestVectors.text(testCase.member("memberAfter")) ?? ""

        // The seed must not already be in the state being asserted, or every expectation below
        // restates the fixture instead of measuring the handler.
        #expect(
            try Self.isServed("off", in: seed) != servedAfter,
            "\(id): the fixture already holds the outcome, so this case measures nothing"
        )

        let result = try await Self.send(
            method: ManifestVectors.text(testCase.member("method")) ?? "",
            path: (ManifestVectors.text(testCase.member("path")) ?? "")
                .replacingOccurrences(of: "{name}", with: "off"),
            body: ManifestVectors.text(testCase.member("body")) ?? "",
            startingFrom: seed
        )

        #expect(
            result.status == Int(testCase.member("status")?.asNumber ?? -1),
            "\(id): the app's own request was answered \(result.status)"
        )
        #expect(
            try Self.isServed("off", in: result.onDisk) == servedAfter,
            "\(id): the vector says servedAfter=\(servedAfter): \(result.onDisk)"
        )
        #expect(
            result.onDisk.contains("disabled") == (memberAfter == "present"),
            "\(id): the member did not end up \(memberAfter): \(result.onDisk)"
        )
        // The control. Every expectation above is also passed by a handler that switched off the
        // whole file, so the untouched sibling is what makes them about *this server*.
        #expect(
            try Self.isServed("on", in: result.onDisk),
            "\(id): the write reached a server it was not addressed to: \(result.onDisk)"
        )
        return id
    }

    /// The pinned corpus, out of the test bundle's `Pins` directory.
    static func pinnedCases() throws -> [JSONValue] {
        guard let url = Bundle.module.url(
            forResource: "pause-action", withExtension: "json", subdirectory: "Pins"
        ) else {
            Issue.record("Pins/pause-action.json is missing — the corpus cannot shrink silently")
            throw Vectors.VectorError.missing("pause-action")
        }
        let root = try JSONParser.parse(Data(contentsOf: url))
        guard let list = root.member("cases")?.asArray else {
            throw Vectors.VectorError.missing("pause-action.cases")
        }
        return list
    }

    // MARK: - The vector says something before anything is measured against it

    /// A corpus whose two directions agreed would leave every case passing while comparing
    /// nothing — this repository's own rule about a check that could not run, applied to the file
    /// the check reads.
    @Test("the pinned request is a request, and its two directions disagree")
    func theVectorIsWellFormed() throws {
        let cases = try Self.pinnedCases()
        #expect(cases.count == 2)
        #expect(cases.allSatisfy { ManifestVectors.text($0.member("method")) == "PATCH" })
        #expect(cases.allSatisfy { ManifestVectors.text($0.member("path"))?.contains("{name}") == true })
        #expect(Set(cases.map { $0.member("servedAfter")?.asBool ?? false }) == [true, false])
        #expect(Set(cases.compactMap { ManifestVectors.text($0.member("body")) }).count == 2)
    }

    // MARK: - The strike, read back through the filesystem

    @Test("the disable request stops the server being served, as read back off the config")
    func disablingStopsItBeingServed() async throws {
        let cases = try Self.pinnedCases()
        let disable = try #require(
            cases.first { ManifestVectors.text($0.member("id")) == "disable" },
            "the corpus no longer carries the disable direction"
        )
        #expect(try await Self.drive(disable) == "disable")
    }

    @Test("the enable request restores serving and leaves no member behind")
    func enablingRestoresServing() async throws {
        let cases = try Self.pinnedCases()
        let enable = try #require(
            cases.first { ManifestVectors.text($0.member("id")) == "enable" },
            "the corpus no longer carries the enable direction"
        )
        #expect(try await Self.drive(enable) == "enable")
    }

    /// The completeness property, kept where `VectorRegistry`'s attestation used to hold it.
    ///
    /// A case added to the pin with nothing driving it is a case nobody reads, and it would sit
    /// there looking like coverage. This drives every case the file holds and compares the count
    /// it actually executed against the count in the file — the consumer reporting its own
    /// execution rather than the file reporting its own size.
    @Test("every case in the pin is driven, and the count comes from the driving")
    func everyPinnedCaseIsDriven() async throws {
        let cases = try Self.pinnedCases()
        var driven: [String] = []
        for testCase in cases {
            try await driven.append(Self.drive(testCase))
        }
        #expect(driven.count == cases.count, "\(driven.count) of \(cases.count) cases were driven")
        #expect(Set(driven).count == driven.count, "two cases in the pin carry the same id")
        #expect(driven.count >= 2, "the pin holds fewer than both directions")
    }
}
