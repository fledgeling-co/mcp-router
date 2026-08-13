import Foundation
import os

/// Everything the app knows about the router, it learns over loopback HTTP.
///
/// This is deliberate rather than incidental: the app never reads the router's
/// `servers.json`, never parses its manifest, and never shells out to the CLI. One
/// consequence is that the daemon could be rewritten in another language tomorrow and
/// nothing in this app would change. The other is that there is exactly one writer to
/// the router's config — the router — so the app cannot race the launchd watcher that
/// adopts new servers out of `~/.claude.json`.
actor RouterClient {
    enum Failure: LocalizedError {
        case noToken(String)
        case notRunning
        case http(Int, String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .noToken(let path):
                return "No control token at \(path). Is mcp-router installed?"
            case .notRunning:
                return "mcp-router isn't answering."
            case .http(let code, let body):
                return body.isEmpty ? "Router returned HTTP \(code)." : body
            case .decode(let what):
                return "Couldn't read the router's reply (\(what))."
            }
        }
    }

    static let defaultPort = 8879

    /// Where the router keeps its state. Overridable because the router itself honours
    /// `MCP_ROUTER_HOME`, and an app that can only ever find one install is an app you
    /// cannot point at a second one.
    static var home: String {
        if let h = ProcessInfo.processInfo.environment["MCP_ROUTER_HOME"], !h.isEmpty { return h }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".claude/mcp-router")
    }

    static var defaultPortFromEnvironment: Int {
        if let p = ProcessInfo.processInfo.environment["MCP_ROUTER_PORT"], let n = Int(p) { return n }
        let stored = UserDefaults.standard.integer(forKey: "routerPort")
        return stored > 0 ? stored : defaultPort
    }

    private let session: URLSession
    private var port: Int
    private var cachedToken: String?

    init(port: Int? = nil) {
        self.port = port ?? RouterClient.defaultPortFromEnvironment
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        // The SSE stream must not be cut at the request timeout; it is idle by design
        // between tool calls, and the router sends a comment heartbeat every 25s.
        cfg.timeoutIntervalForResource = .infinity
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    func setPort(_ p: Int) { port = p; cachedToken = nil }
    var currentPort: Int { port }

    static var tokenPath: String {
        (home as NSString).appendingPathComponent("control.token")
    }

    private func token() throws -> String {
        if let cachedToken { return cachedToken }
        let path = Self.tokenPath
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw Failure.noToken(path)
        }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw Failure.noToken(path) }
        cachedToken = t
        return t
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) throws -> URLRequest {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        r.httpMethod = method
        r.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        if let body {
            r.httpBody = body
            // The router rejects anything that isn't application/json, and that check is
            // load-bearing rather than pedantic: a text/plain POST is a CORS "simple
            // request", so any page in any browser could reach a loopback control API
            // without a preflight. Requiring JSON forces the preflight the token then fails.
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    private func send<T: Decodable>(_ req: URLRequest, as: T.Type) async throws -> T {
        let (data, resp) = try await run(req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((resp as? HTTPURLResponse)?.statusCode ?? 0, Self.message(from: data))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Failure.decode("\(T.self): \(error)") }
    }

    @discardableResult
    private func sendVoid(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await run(req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((resp as? HTTPURLResponse)?.statusCode ?? 0, Self.message(from: data))
        }
        return data
    }

    private func run(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: req) }
        catch let e as URLError where e.code == .cannotConnectToHost || e.code == .networkConnectionLost {
            throw Failure.notRunning
        }
    }

    /// The router puts a human sentence in `{"error": "..."}`; show that rather than a code.
    private static func message(from data: Data) -> String {
        if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = o["error"] as? String { return e }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Reads

    func servers() async throws -> ServersResponse {
        try await send(request("GET", "/servers"), as: ServersResponse.self)
    }

    func usage(limit: Int = 200, server: String? = nil, project: String? = nil) async throws -> UsageResponse {
        var q = "/usage?limit=\(limit)"
        if let server { q += "&server=\(server.urlEncoded)" }
        if let project { q += "&cwd=\(project.urlEncoded)" }
        return try await send(request("GET", q), as: UsageResponse.self)
    }

    func summary() async throws -> SummaryResponse {
        try await send(request("GET", "/usage/summary"), as: SummaryResponse.self)
    }

    func changes(_ server: String) async throws -> ChangesResponse {
        try await send(request("GET", "/servers/\(server.urlEncoded)/changes"), as: ChangesResponse.self)
    }

    func search(_ query: String, limit: Int = 30) async throws -> RegistryResponse {
        // The registry call reaches two public indexes and can take a while on a cold
        // cache; it gets its own longer budget rather than raising it for every call.
        var req = try request("GET", "/registry/search?q=\(query.urlEncoded)&limit=\(limit)")
        req.timeoutInterval = 45
        return try await send(req, as: RegistryResponse.self)
    }

    // MARK: - Writes

    func install(name: String, spec: InstallSpec, force: Bool = false) async throws {
        struct Payload: Encodable { let name: String; let config: InstallSpec }
        let enc = JSONEncoder()
        // The router treats an absent key and a null key differently; omit rather than null.
        enc.outputFormatting = []
        let body = try enc.encode(Payload(name: name, config: spec))
        try await sendVoid(request("POST", "/servers\(force ? "?force=1" : "")", body: body))
    }

    func remove(_ name: String) async throws {
        try await sendVoid(request("DELETE", "/servers/\(name.urlEncoded)"))
    }

    func reindex(_ name: String) async throws {
        try await sendVoid(request("POST", "/servers/\(name.urlEncoded)/reindex"))
    }

    func approveChanges(_ name: String) async throws {
        try await sendVoid(request("POST", "/servers/\(name.urlEncoded)/approve"))
    }

    func beginAuth(_ name: String) async throws -> AuthStart {
        try await send(request("POST", "/servers/\(name.urlEncoded)/auth"), as: AuthStart.self)
    }

    func clearAuth(_ name: String) async throws {
        try await sendVoid(request("DELETE", "/servers/\(name.urlEncoded)/auth"))
    }

    /// Only the four fields the router lets the app change. Command, args and env are
    /// deliberately not among them: a control API that can rewrite a command line is a
    /// control API that can run anything, and installing already covers that case.
    func patch(_ name: String, projects: [String]? = nil, warm: Bool? = nil,
               idleMs: Int? = nil, placard: Placard?? = nil) async throws {
        var o: [String: Any] = [:]
        if let projects { o["projects"] = projects }
        if let warm { o["warm"] = warm }
        if let idleMs { o["idleMs"] = idleMs }
        if let placard { o["placard"] = placard.map { ["reason": $0.reason, "substitute": $0.substitute as Any, "until": $0.until as Any] } ?? NSNull() }
        guard !o.isEmpty else { return }
        try await sendVoid(request("PATCH", "/servers/\(name.urlEncoded)", body: try JSONSerialization.data(withJSONObject: o)))
    }

    func resetUsage(server: String? = nil) async throws {
        let body = server.map { try? JSONSerialization.data(withJSONObject: ["server": $0]) } ?? nil
        try await sendVoid(request("POST", "/usage/reset", body: body ?? Data("{}".utf8)))
    }

    // MARK: - Live stream

    /// One long-lived SSE connection carrying every tool call as it completes.
    ///
    /// Polling would work and would be wrong: the interesting events are bursts a few
    /// hundred milliseconds apart during a session, and a poll interval short enough to
    /// catch them is a poll interval that never lets the machine idle.
    func stream() -> AsyncThrowingStream<CallRecord, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = try request("GET", "/usage/stream")
                    req.timeoutInterval = .infinity
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, resp) = try await session.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                        throw Failure.http((resp as? HTTPURLResponse)?.statusCode ?? 0, "")
                    }
                    let dec = JSONDecoder()
                    for try await line in bytes.lines {
                        // ": heartbeat" comments and blank separators are the stream
                        // proving it is alive; they carry no record.
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let d = json.data(using: .utf8),
                              let rec = try? dec.decode(CallRecord.self, from: d) else { continue }
                        continuation.yield(rec)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?&="))) ?? self
    }
}
