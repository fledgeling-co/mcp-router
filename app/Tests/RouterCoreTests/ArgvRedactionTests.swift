import Foundation
import Testing
@testable import RouterCore

/// A scrubber with no literal needles, for fixtures that carry no secret the router must find. The
/// argv rules still apply to every argument; only the needle pass is empty.
extension SecretRedactor {
    static let withoutNeedles = SecretRedactor(needles: SecretNeedles(needles: [], unscrubbable: []))
}

/// DEF-070. `GET /servers` is not token-gated, so these run it the way the defect was measured: an
/// unauthenticated request, through ``ControlHandler`` and the same `Describe.row` every server
/// row is built from.
struct ArgvRedactionTests {
    static let controlToken = "ctl_9f8e7d6c5b4a3210"

    /// Each server's secret is in a different place a credential reaches an argv: a flag, a flag
    /// with a separate value, a URL password, a URL token in the user position, and a literal
    /// copied from another server's env. The control token is the last.
    static let config = """
    {"mcpServers":{
      "tokenised":{"command":"npx","args":["serve","--token=abcdef123456","--port=8080"]},
      "spaced":{"command":"npx","args":["--api-key","sk-live-0123456789"]},
      "dsn":{"command":"psql-mcp","args":["postgres://alice:s3cr3tpass@db.internal:5432/app"]},
      "git":{"command":"git-mcp","args":["https://ghp_0123456789abcdef@github.com/acme/x.git"]},
      "holder":{"command":"node","args":["server.js"],"env":{"GITHUB_TOKEN":"ghp_fedcba9876543210"}},
      "echoes":{"command":"node","args":["--header=ghp_fedcba9876543210"]},
      "listens":{"command":"node","args":["--listen","ctl_9f8e7d6c5b4a3210"]}
    }}
    """

    static let secrets = [
        "abcdef123456", "sk-live-0123456789", "s3cr3tpass", "ghp_0123456789abcdef",
        "ghp_fedcba9876543210", controlToken
    ]

    static func deps() throws -> ControlDeps {
        let parsed = try JSONParser.parse(config)
        var upstreams: [(name: JSString, upstream: UpstreamConfig)] = []
        for entry in parsed.member("mcpServers")?.asObjectMembers ?? [] {
            guard case let .upstream(upstream) = ServerParser.parse(
                name: entry.key.string, raw: entry.value
            ) else { continue }
            upstreams.append((entry.key, upstream))
        }
        return try PortIdentityTests.deps(upstreams: upstreams)
    }

    @Test("an unauthenticated GET /servers publishes no secret that was in an argv")
    func listRedactsEverySecret() async throws {
        var deps = try Self.deps()
        let response = await ControlHandler(token: Self.controlToken).handle(
            ControlAPIRequest(method: "GET", encodedPath: "/servers"), &deps
        )
        let body = ControlFixtureTests.body(response)
        #expect(response.status == 200)
        for secret in Self.secrets {
            #expect(!body.contains(secret), "GET /servers published a secret-bearing argv value")
        }
        #expect(body.contains("--token=<redacted>"))
        #expect(body.contains("alice:<redacted>@db.internal"))
        #expect(body.contains("--header=<redacted:holder.env.GITHUB_TOKEN>"))
        #expect(body.contains("--listen\",\"<redacted:control.token>\""))
    }

    @Test("a non-secret argument and the command are published unchanged")
    func listKeepsWhatIsNotSecret() async throws {
        var deps = try Self.deps()
        let response = await ControlHandler(token: Self.controlToken).handle(
            ControlAPIRequest(method: "GET", encodedPath: "/servers"), &deps
        )
        let body = ControlFixtureTests.body(response)
        #expect(body.contains("\"args\":[\"serve\",\"--token=<redacted>\",\"--port=8080\"]"))
        #expect(body.contains("\"command\":\"npx\""))
    }

    @Test("GET /servers/:name redacts the same row the list does")
    func singleRowRedactsTheSameWay() async throws {
        var deps = try Self.deps()
        let response = await ControlHandler(token: Self.controlToken).handle(
            ControlAPIRequest(method: "GET", encodedPath: "/servers/spaced"), &deps
        )
        let body = ControlFixtureTests.body(response)
        #expect(response.status == 200)
        #expect(!body.contains("sk-live-0123456789"))
        #expect(body.contains("\"--api-key\",\"<redacted>\""))
    }
}
