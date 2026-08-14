import Foundation
import RouterCore

/// `mcp-router auth <server>`, in its own file.
///
/// Split out of `MCPRouterCLI.swift` for the same reason `ImportVerb.swift` was — length, not
/// cohesion. It is the same type, extended.
///
/// This verb is also the one place the CLI drives a flow rather than printing an answer: it asks the
/// *running* router to begin an authorization, hands the user's browser the URL the router returned,
/// and then waits on disk for the tokens the router writes when the exchange completes. The CLI
/// never performs the exchange itself, which is why it polls rather than listening — the callback
/// belongs to the router's own listener, and a second listener here would race it for the port.
extension MCPRouterCLI {
    // MARK: - auth

    static func auth(_ arguments: [String]) async throws {
        guard arguments.count > 1, !arguments[1].hasPrefix("--") else {
            throw CLIError("usage: mcp-router auth <server>")
        }
        let name = arguments[1]
        let options = try Flags(arguments)
        let port = try options.number("port") ?? RouterHome.defaultPort
        let home = RouterHome()

        let url = try await Self.beginAuthorization(server: name, port: port, home: home)

        Out.print("opening your browser to authorize \"\(name)\"\n\(url)\n")
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [url]
        try? open.run()

        // Polled rather than held: the exchange completes inside the router.
        let store = FileAuthStore(authDir: home.authDir)
        for _ in 0 ..< 150 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if await store.hasTokens(JSString(name)) {
                Out.print("\n✓ \(name) is authorized\n")
                return
            }
        }
        Out.print("\ngave up waiting; run `mcp-router status` to check\n")
        exit(1)
    }

    /// Ask the running router to start an authorization, and return the URL it wants opened.
    ///
    /// The router's own `error` member is preferred over a generic sentence whenever it sent one:
    /// it knows why the server cannot authorize and the CLI does not.
    static func beginAuthorization(server name: String, port: Int, home: RouterHome) async throws -> String {
        let token = (try? ControlToken(
            path: (home.root as NSString).appendingPathComponent("control.token")
        ).load()) ?? ""

        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        guard let body = await Loopback.post(
            port: port,
            path: "/servers/\(encodedName)/auth",
            token: token
        ) else {
            throw CLIError(
                "no router answering on 127.0.0.1:\(port) (fetch failed) — start it first"
            )
        }
        guard case let .object(fields) = body,
              let url = fields.first(where: { $0.key == JSString("authorizationUrl") })?
              .value.asString
        else {
            let message = {
                guard case let .object(fields) = body,
                      let error = fields.first(where: { $0.key == JSString("error") })?.value.asString
                else { return "authorization could not start" }
                return error.string
            }()
            throw CLIError(message)
        }
        return url.string
    }
}
