import Foundation
import Testing
@testable import MCPRouterKit

/// The held-version writes, on the wire and in the fixture.
///
/// The stub records whole packets, so a request's JSON body is visible to these tests as well as its
/// path and token. A refusal is asserted as `.server` with the router's own sentence, never as a
/// success, because a write the router refused and a write it made are the two things a user must
/// not be able to confuse.
@Suite("Extension writes — promote, undo and keep")
struct ExtensionWritesTests {
    private func client(_ stub: HTTPStub) -> LiveControlAPIClient {
        LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore("test-token"),
            tokenFile: RouterTokenFile(url: URL(fileURLWithPath: "/nonexistent/control.token"))
        )
    }

    private let trawl = "trawl@fledgeling-plugins"

    @Test("keep posts the held version to the plugin's keep route, with the token and a JSON body")
    func keepPostsTheVersion() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "POST", "/extensions/plugins/trawl%40fledgeling-plugins/keep",
            .json(200, #"{"kept":"trawl@fledgeling-plugins","kind":"plugins","pluginVersion":"2.3.0"}"#)
        )

        let ack = try await client(stub).keepHeldVersion(trawl, kind: .plugins, pluginVersion: "2.3.0")

        #expect(ack.pluginVersion == "2.3.0")
        let head = try #require(stub.requests.first)
        #expect(head.contains("Bearer test-token"), "a write must carry the control token")
        #expect(head.lowercased().contains("content-type: application/json"))
        #expect(head.contains(#""pluginVersion":"2.3.0""#))
    }

    @Test("a keep the router refuses is a refusal in the router's own words, never a success")
    func keepRefusalIsARefusal() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "POST", "/extensions/plugins/ghost%40market/keep",
            .json(400, #"{"error":"pluginVersion is required","reason":"invalidName"}"#)
        )

        await #expect(throws: ControlAPIError.server(status: 400, message: "pluginVersion is required")) {
            _ = try await client(stub).keepHeldVersion("ghost@market", kind: .plugins, pluginVersion: "")
        }
    }

    @Test("promote sends the version and the files, and reads back the restore reference it was given")
    func promoteSendsFilesAndReadsRestore() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "POST", "/extensions/plugins/trawl%40fledgeling-plugins/promote",
            .json(
                200,
                #"{"promoted":"trawl@fledgeling-plugins","kind":"plugins","pluginVersion":"2.3.0","#
                    + #""replaced":"2.2.0","restore":"1700","files":1,"bytes":40}"#
            )
        )
        let file = ExtensionFileBody(path: ".claude-plugin/plugin.json", text: #"{"name":"trawl"}"#)

        let ack = try await client(stub).promote(trawl, kind: .plugins, pluginVersion: "2.3.0", files: [file])

        #expect(ack.restore == "1700")
        #expect(ack.replaced == "2.2.0")
        let head = try #require(stub.requests.first)
        #expect(head.contains("plugin.json"), "the files must reach the router, not only the version")
        #expect(head.contains(#""pluginVersion":"2.3.0""#))
    }

    @Test("a promotion the router refuses is a refusal, and nothing is reported as promoted")
    func promoteRefusalIsARefusal() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "POST", "/extensions/plugins/trawl%40fledgeling-plugins/promote",
            .json(
                400,
                #"{"error":"plugin.json declares 2.2.0, not the 2.3.0 being promoted","#
                    + #""reason":"versionMismatch"}"#
            )
        )

        await #expect(
            throws: ControlAPIError.server(
                status: 400,
                message: "plugin.json declares 2.2.0, not the 2.3.0 being promoted"
            )
        ) {
            _ = try await client(stub).promote(
                trawl, kind: .plugins, pluginVersion: "2.3.0",
                files: [ExtensionFileBody(path: ".claude-plugin/plugin.json", text: "{}")]
            )
        }
    }

    @Test("undo sends the restore reference and reads back the version it put back")
    func undoSendsTheRestoreReference() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "POST", "/extensions/plugins/trawl%40fledgeling-plugins/undo-promote",
            .json(
                200,
                #"{"restored":"trawl@fledgeling-plugins","kind":"plugins","version":"2.2.0","#
                    + #""withdrawn":"2.3.0"}"#
            )
        )

        let ack = try await client(stub).undoPromotion(trawl, kind: .plugins, restore: "1700")

        #expect(ack.version == "2.2.0")
        #expect(ack.withdrawn == "2.3.0")
        let head = try #require(stub.requests.first)
        #expect(head.contains(#""restore":"1700""#))
    }

    @Test("an undo the router refuses because the installed version has moved is a refusal")
    func undoRefusalIsARefusal() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "POST", "/extensions/plugins/trawl%40fledgeling-plugins/undo-promote",
            .json(
                409,
                #"{"error":"trawl is at version 2.4.0, not the 2.3.0 this promotion installed","#
                    + #""reason":"installedChanged"}"#
            )
        )

        await #expect(
            throws: ControlAPIError.server(
                status: 409, message: "trawl is at version 2.4.0, not the 2.3.0 this promotion installed"
            )
        ) {
            _ = try await client(stub).undoPromotion(trawl, kind: .plugins, restore: "1700")
        }
    }

    @Test(
        "the fixture answers each write with the router's shape, and the error scenario refuses all of them"
    )
    func fixtureAnswersTheWrites() async throws {
        let populated = FixtureControlAPIClient(.populated)
        let kept = try await populated.keepHeldVersion(trawl, kind: .plugins, pluginVersion: "2.3.0")
        #expect(kept.kept == trawl)
        let promoted = try await populated.promote(
            trawl, kind: .plugins, pluginVersion: "2.3.0", files: [ExtensionFileBody(path: "x", text: "y")]
        )
        #expect(promoted.pluginVersion == "2.3.0")
        #expect(!promoted.restore.isEmpty)
        let undone = try await populated.undoPromotion(trawl, kind: .plugins, restore: promoted.restore)
        #expect(undone.restored == trawl)

        let failing = FixtureControlAPIClient(.error)
        let refusal = ControlAPIError.server(
            status: 422,
            message: "spawn /nonexistent/binary-that-cannot-start ENOENT",
            hint: "retry with ?force=1 to add it anyway"
        )
        await #expect(throws: refusal) { _ = try await failing.keepHeldVersion(
            trawl,
            kind: .plugins,
            pluginVersion: "2.3.0"
        ) }
        await #expect(throws: refusal) {
            _ = try await failing.promote(trawl, kind: .plugins, pluginVersion: "2.3.0", files: [])
        }
        await #expect(throws: refusal) { _ = try await failing.undoPromotion(
            trawl,
            kind: .plugins,
            restore: "1700"
        ) }
    }
}
