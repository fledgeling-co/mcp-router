import Foundation
import Testing
@testable import RouterCore

/// M29, oracle line 3 — the refusal a disabled server's caller gets, and the one it does not.
///
/// The claim under test is not "the call is refused" but *which sentence the refusal carries*.
/// `Upstream "x" is not available in this project` is a true statement about a scoped server and a
/// false one about a globally disabled server, and a caller who reads it goes and changes a
/// `projects` list that was never what stopped them. So the two branches are asserted against each
/// other, and the case where both are true is asserted to answer *disabled* — that ordering is
/// spec D6 and it is the only part of this that a single-branch test would miss.
@Suite("M29 — what a disabled server tells its caller")
struct MCPEndpointDisabledCallTests {
    private static func endpoint(
        upstreams: [UpstreamConfig],
        cwd: String?
    ) -> MCPEndpoint {
        let clock = ManualClock(milliseconds: 1_770_000_000_000)
        let config = RouterConfig(
            port: 8971, host: "127.0.0.1", idleMs: 300_000, startupTimeoutMs: 60000,
            upstreams: upstreams, manifestPath: "/router/manifest.json",
            logPath: "/router/r.log", usagePath: "/router/none/usage.jsonl",
            statsPath: "/router/none/stats.json", authDir: "/router/auth"
        )
        let pool = UpstreamPool(
            upstreams: upstreams,
            defaultIdleMilliseconds: 60000,
            defaultStartupTimeoutMilliseconds: 1000,
            transporting: FakeTransport(),
            clock: TestClock(),
            log: nil
        )
        return MCPEndpoint(
            deps: MCPEndpoint.Deps(
                config: config,
                upstreams: upstreams,
                manifest: ManifestStore(
                    path: "/router/manifest.json",
                    fileSystem: MemoryFileSystem(),
                    clock: clock
                ),
                pool: pool,
                usage: UsageStore(
                    logPath: "/router/none/usage.jsonl",
                    statsPath: "/router/none/stats.json",
                    clock: clock
                ),
                log: nil,
                clock: clock
            ),
            instructions: nil,
            identify: { _ in CallerIdentity(pid: nil, cwd: cwd, client: nil) }
        )
    }

    /// The text of a `tools/call` answer, or nil if it was not a tool error.
    private static func refusalText(_ result: JSONValue) -> String? {
        guard result.member("isError")?.isTruthy == true,
              let first = result.member("content")?.asArray?.first
        else { return nil }
        return first.member("text")?.asString?.string
    }

    private static func call(_ endpoint: MCPEndpoint, tool: String) async -> String? {
        let params = JSONValue.object([
            JSONMember(key: JSString("name"), value: .string(JSString(tool))),
            JSONMember(key: JSString("arguments"), value: .object([]))
        ])
        let result = await endpoint.callTool(params)
        return refusalText(result)
    }

    @Test("a disabled server's tools are refused, and the refusal says disabled")
    func aDisabledServerRefusesByName() async {
        let endpoint = Self.endpoint(
            upstreams: [stdioUpstream("off", disabled: true)],
            cwd: "/here"
        )
        let text = await Self.call(endpoint, tool: "off__one")
        #expect(
            text == #"Upstream "off" is disabled. Enable it in MCP Router to use its tools."#,
            "a disabled server answered: \(text ?? "no refusal at all")"
        )
    }

    /// The negative control, and the reason the disabled branch cannot simply be folded into the
    /// scoping one: a scoped server still gets its own sentence, unchanged by this feature.
    @Test("a scoped-out server still names the project, not the switch")
    func aScopedServerKeepsItsOwnSentence() async {
        var scoped = stdioUpstream("elsewhere")
        scoped.projects = ["/other"]
        let endpoint = Self.endpoint(upstreams: [scoped], cwd: "/here")
        let text = await Self.call(endpoint, tool: "elsewhere__one")
        #expect(
            text == #"Upstream "elsewhere" is not available in this project (/here)."#,
            "a scoped server answered: \(text ?? "no refusal at all")"
        )
    }

    /// Spec D6's ordering. Both conditions hold, and only one of the two sentences sends the reader
    /// somewhere that would actually change the outcome.
    @Test("a server that is both disabled and out of scope is refused as disabled")
    func disabledIsAskedFirst() async {
        var both = stdioUpstream("both", disabled: true)
        both.projects = ["/other"]
        let endpoint = Self.endpoint(upstreams: [both], cwd: "/here")
        let text = await Self.call(endpoint, tool: "both__one")
        #expect(
            text == #"Upstream "both" is disabled. Enable it in MCP Router to use its tools."#,
            "the project was named for a server the project was not what stopped: \(text ?? "none")"
        )
    }

    /// Without this the three above pass on an endpoint that refuses everything. A server that is
    /// neither disabled nor scoped out gets past the refusal gate — it fails later, at the
    /// transport, which is a different sentence and the point.
    @Test("a served server is not turned away by either refusal")
    func aServedServerReachesTheUpstream() async {
        let endpoint = Self.endpoint(upstreams: [stdioUpstream("on")], cwd: "/here")
        let text = await Self.call(endpoint, tool: "on__one")
        #expect(text?.contains("is disabled") != true, "a live server was refused as disabled: \(text ?? "")")
        #expect(
            text?.contains("not available in this project") != true,
            "a live server was refused as out of scope: \(text ?? "")"
        )
    }
}
