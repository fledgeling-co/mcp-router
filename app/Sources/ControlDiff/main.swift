import Foundation
import RouterCore

/// Answers one control-API request through the **Swift** handler and prints what it produced, so a
/// script can put it next to what the **TypeScript** router produced for the same request.
///
/// This is the acceptance oracle R3 was missing. Every other check in this item compares the port
/// against something we wrote: the 23 recorded fixtures (bytes captured once, in March), the vector
/// corpus (generated from the reference, but consumed by assertions we authored), and the unit
/// suite (our belief about the contract). All three agree with the model by construction. This one
/// runs the actual reference, now, and diffs the bytes — which is the only check that catches the
/// reference moving under a port that still compiles.
///
/// It is an executable rather than a test because it needs a running daemon, and a unit suite that
/// needs a daemon is a unit suite that fails on a machine where one is not running.
///
/// Exit codes follow the house pattern: **2** is an environment that could not run the check —
/// a missing config, an unreadable manifest — and **1** is a request that could not be answered.
/// Collapsing them reports "the fixture directory is missing" as "the handler is broken".
@main
struct ControlDiff {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        var arguments = Array(CommandLine.arguments.dropFirst())

        guard arguments.count >= 2 else {
            fail(2, """
            usage: ControlDiff <METHOD> <ENCODED-PATH> [body]
              MCPR_CONFIG    servers.json the router is running (required)
              MCPR_MANIFEST  manifest.json path
              MCPR_USAGE     usage log path
              MCPR_STATS     usage stats path
              MCPR_TOKEN     the control token, when the request should be authorized
              MCPR_HEADERS   extra headers, "name: value" separated by newlines
            """)
        }

        let method = arguments.removeFirst()
        let target = arguments.removeFirst()
        let body = arguments.first

        var deps = dependencies(env: env)
        let split = Self.split(target)
        let request = ControlAPIRequest(
            method: method,
            encodedPath: split.path,
            query: split.query,
            headers: headers(env: env, hasBody: body != nil),
            body: body.map { Data($0.utf8) }
        )

        let handler = ControlHandler(token: env["MCPR_TOKEN"] ?? "")
        let response = await handler.handle(request, &deps)
        emit(response)
    }

    /// The same files the running router reads, so the two answers are functions of one state.
    static func dependencies(env: [String: String]) -> ControlDeps {
        guard let configPath = env["MCPR_CONFIG"] else { fail(2, "environment: MCPR_CONFIG is unset") }
        let fileSystem = RealFileSystem()
        guard fileSystem.fileExists(atPath: configPath) else {
            fail(2, "environment: no config at \(configPath)")
        }

        let manifestPath = env["MCPR_MANIFEST"] ?? "/nonexistent/manifest.json"
        let usagePath = env["MCPR_USAGE"] ?? "/nonexistent/usage.jsonl"
        let statsPath = env["MCPR_STATS"] ?? "/nonexistent/stats.json"

        let loaded: LoadedConfig
        do {
            loaded = try ConfigLoader.load(
                options: ConfigLoader.Options(configPath: configPath),
                home: RouterHome(root: (configPath as NSString).deletingLastPathComponent),
                fileSystem: fileSystem
            )
        } catch {
            fail(2, "environment: \(configPath) did not load: \(error)")
        }

        var upstreams: [(name: JSString, upstream: UpstreamConfig)] = []
        for upstream in loaded.config.upstreams {
            upstreams.append((JSString(upstream.name), upstream))
        }

        var config = loaded.config
        if let override = env["MCPR_PORT"], let port = Int(override) { config.port = port }

        return ControlDeps(
            config: config,
            upstreams: upstreams,
            // An idle pool with no pending authorizations. The differential script only issues
            // requests whose answer does not depend on live pool state, and asserts that by
            // running against a router whose upstreams have never been called.
            pool: IdlePool(),
            indexer: RefusingIndexer(),
            auth: NoAuthStore(),
            usage: UsageStore(logPath: usagePath, statsPath: statsPath, fileSystem: fileSystem),
            manifest: ManifestIO.load(path: manifestPath, fileSystem: fileSystem).manifest,
            fileSystem: fileSystem,
            tokenPath: env["MCPR_TOKEN_PATH"] ?? "/nonexistent/control.token",
            configPath: configPath
        )
    }

    static func headers(env: [String: String], hasBody: Bool) -> [(name: String, value: String)] {
        var headers: [(name: String, value: String)] = []
        if let token = env["MCPR_TOKEN"], !token.isEmpty {
            headers.append((name: "x-mcpr-token", value: token))
        }
        if hasBody {
            headers.append((name: "content-type", value: "application/json"))
        }
        for line in (env["MCPR_HEADERS"] ?? "").split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers.append((
                name: String(line[line.startIndex ..< colon]).trimmingCharacters(in: .whitespaces),
                value: String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            ))
        }
        return headers
    }

    static func emit(_ response: ControlAPIResponse) {
        guard response.handled else {
            // Not a control path. Distinct from a 404: the reference returns without touching the
            // response at all, and the script needs to see that as its own answer.
            FileHandle.standardOutput.write(Data("NOT-A-CONTROL-PATH\n".utf8))
            exit(0)
        }
        // Both through the same unbuffered handle. `print` is buffered and flushes at exit, so
        // mixing the two put the status AFTER the body and made every row look like a mismatch.
        FileHandle.standardOutput.write(Data("\(response.status)\n".utf8))
        switch response.body {
        case let .bytes(bytes):
            FileHandle.standardOutput.write(Data(bytes))
        case .stream:
            // `/usage/stream` is an open SSE connection, not a body. The differential compares
            // framing separately; printing a marker keeps it from looking like an empty 200.
            FileHandle.standardOutput.write(Data("EVENT-STREAM".utf8))
        }
    }

    /// Splits an encoded target into its path and its **ordered** query items. Foundation's
    /// `URLComponents` re-encodes and reorders, both of which are on the wire here (B15, B28).
    static func split(_ target: String) -> (path: String, query: [(name: String, value: String)]) {
        guard let mark = target.firstIndex(of: "?") else { return (target, []) }
        let path = String(target[target.startIndex ..< mark])
        let rest = String(target[target.index(after: mark)...])
        var items: [(name: String, value: String)] = []
        for pair in rest.split(separator: "&", omittingEmptySubsequences: false) where !pair.isEmpty {
            let text = String(pair)
            guard let equals = text.firstIndex(of: "=") else {
                items.append((name: Self.decode(text), value: ""))
                continue
            }
            items.append((
                name: Self.decode(String(text[text.startIndex ..< equals])),
                value: Self.decode(String(text[text.index(after: equals)...]))
            ))
        }
        return (path, items)
    }

    /// `URLSearchParams` decoding: `+` is a space, then percent decoding.
    static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? text
    }

    static func fail(_ code: Int32, _ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(code)
    }
}

private struct IdlePool: UpstreamPoolPort {
    func status() -> [LiveUpstream] {
        []
    }

    func pending() -> [PendingAuthRow] {
        []
    }

    func isLive(_: JSString) -> Bool {
        false
    }

    func warmUp() {}
    func clearPending(_: JSString) {}
}

private struct RefusingIndexer: UpstreamIndexerPort {
    func index(_: UpstreamConfig) async -> IndexOutcome {
        IndexOutcome(tools: 0, error: "indexing is not exercised by the differential")
    }
}

private struct NoAuthStore: AuthStore {
    func hasTokens(_: JSString) -> Bool {
        false
    }

    func authorizedAt(_: JSString) -> String? {
        nil
    }

    @discardableResult func clear(_: JSString) -> Bool {
        false
    }
}
