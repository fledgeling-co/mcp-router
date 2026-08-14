import Foundation
import MCPRouterKit

/// Talks to a **real** running router and reports what it decoded.
///
/// Everything else in this package is exercised against a stub, and a stub is something we wrote:
/// it proves the client agrees with our belief about the wire, which is precisely the thing that is
/// wrong when the wire moves. This makes one request the actual TypeScript router answered.
///
/// Exit codes are distinct on purpose, following the house pattern. **2** means the check could not
/// be run — no router listening, no token — and **1** means it ran and the answer was wrong.
/// Collapsing them reports "the daemon isn't up" as "the client is broken", and someone then goes
/// looking for a bug that is not there.
@main
struct ControlProbe {
    static func main() async {
        let base = ProcessInfo.processInfo.environment["MCP_ROUTER_URL"] ?? "http://127.0.0.1:8879"
        guard let url = URL(string: base) else {
            FileHandle.standardError.write(Data("environment: MCP_ROUTER_URL is not a URL: \(base)\n".utf8))
            exit(2)
        }

        let client = LiveControlAPIClient(
            baseURL: url,
            session: URLSession(configuration: .ephemeral),
            // The token comes from the router's own file, honouring MCP_ROUTER_HOME — which is how
            // the acceptance script points this at a throwaway router rather than the real one.
            store: InMemoryTokenStore(nil),
            tokenFile: RouterTokenFile()
        )

        do {
            let servers = try await client.servers()
            let usage = try await client.usage()

            // Decoding is the assertion. These fields exist on every response the router gives, so
            // reading them back proves the shapes matched rather than that a lenient decoder
            // shrugged.
            print("port=\(servers.port)")
            print("idleMs=\(servers.idleMs)")
            print("since=\(servers.since)")
            print("servers=\(servers.servers.count)")
            for server in servers.servers {
                print(
                    "  server name=\(server.name) transport=\(server.transport.rawValue) "
                        + "state=\(server.state.rawValue) tools=\(server.tools)"
                )
            }
            print("pendingAuth=\(servers.pendingAuth.map(\.server) ?? "none")")
            print("usageRecords=\(usage.records.count)")

            guard servers.port > 0 else {
                FileHandle.standardError.write(Data("assertion: the router reported no port\n".utf8))
                exit(1)
            }

            // The reads above are unauthenticated on this router — only mutating verbs require the
            // token — so proving the credential works at all needs a mutating call. It is opt-in
            // because it resets the usage counters, and this probe can be pointed at the router the
            // user actually depends on.
            if CommandLine.arguments.contains("--check-auth") {
                let reset = try await client.resetUsage()
                print("usageReset=\(reset.ok)")
            }

            print("OK")
            exit(0)
        } catch {
            switch error {
            case .routerNotRunning:
                FileHandle.standardError.write(Data("environment: no router is listening on \(base)\n".utf8))
                exit(2)
            case .unauthorized:
                FileHandle.standardError.write(Data("environment: the control token was rejected\n".utf8))
                exit(2)
            default:
                FileHandle.standardError.write(Data("assertion: \(error.userFacingDescription)\n".utf8))
                exit(1)
            }
        }
    }
}
