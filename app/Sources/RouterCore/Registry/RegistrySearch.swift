import Foundation

/// One HTTP GET. A protocol so no test in this item touches the network.
public protocol HTTPFetching: Sendable {
    func get(url: String, headers: [(name: String, value: String)], timeoutMs: Int) async throws
        -> HTTPFetchResult
}

public struct HTTPFetchResult: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Carries the message the reference's warnings interpolate: `new Error(\`HTTP ${r.status}\`)`.
public struct HTTPFetchError: Error {
    public let message: String
    public init(message: String) {
        self.message = message
    }
}

/// Everything `searchRegistries` needs, injected so the whole pipeline is testable.
public struct RegistryDeps: Sendable {
    public var http: HTTPFetching
    public var fileSystem: FileSystem
    public var routerHome: String
    /// `process.env.MCP_ROUTER_REGISTRY ?? …` — **nullish**, so an empty value survives (B59).
    public var officialBase: String?
    public var smitheryBase: String?
    public var githubToken: String?
    public var nowMs: Double

    public init(
        http: HTTPFetching,
        fileSystem: FileSystem,
        routerHome: String,
        officialBase: String? = nil,
        smitheryBase: String? = nil,
        githubToken: String? = nil,
        nowMs: Double
    ) {
        self.http = http
        self.fileSystem = fileSystem
        self.routerHome = routerHome
        self.officialBase = officialBase
        self.smitheryBase = smitheryBase
        self.githubToken = githubToken
        self.nowMs = nowMs
    }

    var official: String { officialBase ?? "https://registry.modelcontextprotocol.io" }
    var smithery: String { smitheryBase ?? "https://registry.smithery.ai" }
}

public struct RegistrySearchResult: Sendable {
    public let results: [JSONValue]
    public let officialCount: Int
    public let smitheryCount: Int
    public let mergedCount: Int
    public let warnings: [String]
}

public extension Registry {
    static let githubTTLMs: Double = 24 * 60 * 60000
    static let githubBudget = 10

    /// `searchRegistries(q, limit)` — fetch both, dedupe, enrich, rank, slice.
    static func search(
        query: String,
        limit: Double,
        deps: RegistryDeps
    ) async throws -> RegistrySearchResult {
        var warnings: [String] = []

        // Both requests are issued before either is awaited, as `Promise.all` does. The warnings are
        // then collected in **source order** rather than completion order: the reference's order is
        // whichever index rejects first in wall-clock time, which is not a contract a port can
        // reproduce, and official-then-smithery is the order it produces whenever both fail.
        async let officialFetch = fetchOfficial(query: query, limit: limit, deps: deps)
        async let smitheryFetch = fetchSmithery(query: query, limit: limit, deps: deps)

        var official: [JSObjectDraft] = []
        var smithery: [JSObjectDraft] = []
        do { official = try await officialFetch } catch {
            warnings.append("official registry unreachable: \(message(of: error))")
        }
        do { smithery = try await smitheryFetch } catch {
            warnings.append("Smithery unreachable: \(message(of: error))")
        }

        var merged = merge(official: official, smithery: smithery)
        await warnings.append(contentsOf: enrichWithStars(&merged, deps: deps))
        let ranked = rank(merged)

        return RegistrySearchResult(
            results: jsSlice(ranked, limit: limit).map(\.jsonValue),
            officialCount: official.count,
            smitheryCount: smithery.count,
            // `merged` is the deduped count **before** the slice — `results.slice` returns a new
            // array and leaves `results.length` alone.
            mergedCount: ranked.count,
            warnings: warnings
        )
    }

    /// `Math.min(Number(x ?? 30) || 30, 60)` — the `?limit=` rule, as one named thing.
    ///
    /// Named rather than inlined at the call site so a differential vector can drive the rule
    /// itself. Three coercions are stacked here and each is a way a reasonable port answers a
    /// different result set: `||` is ToBoolean, so both `0` and `NaN` collapse to 30 rather than
    /// returning nothing; `min` caps at 60; and a negative value survives all of it and reaches
    /// `slice`, where it counts back from the end and *drops* rows instead of taking them (N6, B54).
    internal static func coerceLimit(_ raw: String?) -> Double {
        let value = raw.map(JSToNumber.number) ?? 30
        let truthy = (value == 0 || value.isNaN) ? 30 : value
        return min(truthy, 60)
    }

    /// `array.slice(0, limit)` with ECMAScript's index coercion: a negative limit counts back from
    /// the end, so `?limit=-5` drops the last five rather than returning nothing (N6).
    internal static func jsSlice(_ rows: [JSObjectDraft], limit: Double) -> [JSObjectDraft] {
        let count = Double(rows.count)
        let relative = limit.isNaN ? 0 : limit.rounded(.towardZero)
        let end = relative < 0 ? max(count + relative, 0) : min(relative, count)
        guard end > 0 else { return [] }
        return Array(rows.prefix(Int(end)))
    }

    /// `new URL(absolutePath, base)` — an **absolute** path discards the base's own path, so a
    /// base of `https://h/x` yields `https://h/v0/servers`, not `https://h/x/v0/servers`. An
    /// unparseable base (including `""`, which B59 preserves rather than defaulting) throws the
    /// same `TypeError` the reference does, and the message reaches the warning verbatim.
    private static func resolve(base: String, absolutePath: String, query: [String]) throws -> String {
        guard let scheme = base.range(of: "://"), !base.hasPrefix("://") else {
            throw HTTPFetchError(message: "Invalid URL")
        }
        let afterScheme = base[scheme.upperBound...]
        let authority = afterScheme.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !authority.isEmpty else { throw HTTPFetchError(message: "Invalid URL") }
        let origin = base[base.startIndex ..< scheme.upperBound] + authority
        let suffix = query.isEmpty ? "" : "?" + query.joined(separator: "&")
        return origin + absolutePath + suffix
    }

    private static func message(of error: Error) -> String {
        (error as? HTTPFetchError)?.message ?? "\(error)"
    }

    // MARK: - The two indexes

    private static func getJSON(_ url: String, deps: RegistryDeps) async throws -> JSONValue {
        let response = try await deps.http.get(
            url: url, headers: [(name: "accept", value: "application/json")], timeoutMs: 12000
        )
        // `if (!r.ok) throw new Error(\`HTTP ${r.status}\`)` — ok is 200-299.
        guard (200 ... 299).contains(response.status) else {
            throw HTTPFetchError(message: "HTTP \(response.status)")
        }
        return try JSONParser.parse(String(bytes: response.body, encoding: .utf8) ?? "")
    }

    private static func fetchOfficial(
        query: String,
        limit: Double,
        deps: RegistryDeps
    ) async throws -> [JSObjectDraft] {
        var parameters: [String] = []
        // `if (q) u.searchParams.set('search', q)` — ToBoolean, so an empty query sets nothing.
        if !query.isEmpty { parameters.append("search=\(percentEncode(query))") }
        parameters.append("limit=\(JSNumber.string(limit))")
        let url = try resolve(base: deps.official, absolutePath: "/v0/servers", query: parameters)

        let body = try await getJSON(url, deps: deps)
        let servers = body.asObjectMembers?.first { $0.key == JSString("servers") }?.value.asArray ?? []
        return servers.compactMap(officialRow)
    }

    private static func fetchSmithery(
        query: String,
        limit: Double,
        deps: RegistryDeps
    ) async throws -> [JSObjectDraft] {
        var parameters: [String] = []
        if !query.isEmpty { parameters.append("q=\(percentEncode(query))") }
        parameters.append("pageSize=\(JSNumber.string(limit))")
        let url = try resolve(base: deps.smithery, absolutePath: "/servers", query: parameters)

        let body = try await getJSON(url, deps: deps)
        let servers = body.asObjectMembers?.first { $0.key == JSString("servers") }?.value.asArray ?? []
        return servers.compactMap(smitheryRow)
    }

    private static func percentEncode(_ text: String) -> String {
        // `URLSearchParams` encodes space as `+` and leaves these unreserved.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    // MARK: - GitHub enrichment

    /// Stars from a day-old cache, at most `budget` fetches, stopping on the first 403/429.
    ///
    /// The four fields are assigned with `Object.assign` whether or not GitHub returned them, so the
    /// keys are created — and land **after** every key the row already had.
    internal static func enrichWithStars(
        _ rows: inout [JSObjectDraft],
        deps: RegistryDeps
    ) async -> [String] {
        var warnings: [String] = []
        var cache = readGitHubCache(deps: deps)
        var spent = 0
        var rateLimited = false

        for index in rows.indices {
            guard let key = repoKey(rows[index].get("repository")) else { continue }

            let hit = cache.first { $0.key == key }?.value.asObjectMembers
            let cachedAt = hit?.first { $0.key == JSString("at") }?.value.asNumber
            if let hit, let cachedAt, deps.nowMs - cachedAt < githubTTLMs {
                apply(hit, to: &rows[index])
                continue
            }
            if rateLimited || spent >= githubBudget { continue }
            spent += 1

            var headers = [(name: "accept", value: "application/vnd.github+json")]
            if let token = deps.githubToken, !token.isEmpty {
                headers.append((name: "authorization", value: "Bearer \(token)"))
            }
            guard let response = try? await deps.http.get(
                url: "https://api.github.com/repos/\(key.string)", headers: headers, timeoutMs: 12000
            ) else {
                continue // one repo failing to resolve is not a failed search
            }
            if response.status == 403 || response.status == 429 {
                rateLimited = true
                warnings.append(
                    (deps.githubToken?.isEmpty == false)
                        ? "GitHub rate limit reached; star counts are partial."
                        : "GitHub allows 60 requests an hour without a token, so star counts are partial. "
                        + "Set GITHUB_TOKEN to raise it."
                )
                continue
            }
            guard (200 ... 299).contains(response.status),
                  let parsed = try? JSONParser.parse(String(bytes: response.body, encoding: .utf8) ?? ""),
                  let members = parsed.asObjectMembers else { continue }

            func field(_ name: String) -> JSONValue? {
                members.first { $0.key == JSString(name) }?.value
            }

            var record = JSObjectDraft()
            record.set("stars", field("stargazers_count"))
            record.set("forks", field("forks_count"))
            record.set("pushedAt", field("pushed_at"))
            record.set("archived", field("archived"))
            record.set("at", .number(deps.nowMs))
            // `cache[key] = rec` overwrites **in place**; removing and re-appending would move
            // the key to the end and rewrite the cache file in a different order each run.
            if let at = cache.firstIndex(where: { $0.key == key }) {
                cache[at] = JSONMember(key: key, value: record.jsonValue)
            } else {
                cache.append(JSONMember(key: key, value: record.jsonValue))
            }
            apply(record.jsonValue.asObjectMembers ?? [], to: &rows[index])
        }

        writeGitHubCache(cache, deps: deps)
        return warnings
    }

    private static func apply(_ record: [JSONMember], to row: inout JSObjectDraft) {
        func field(_ name: String) -> JSONValue? {
            record.first { $0.key == JSString(name) }?.value
        }
        row.assign([
            ("stars", field("stars")), ("forks", field("forks")),
            ("pushedAt", field("pushedAt")), ("archived", field("archived"))
        ])
    }

    private static func githubCachePath(_ deps: RegistryDeps) -> String {
        "\(deps.routerHome)/github-cache.json"
    }

    private static func readGitHubCache(deps: RegistryDeps) -> [JSONMember] {
        guard let data = try? deps.fileSystem.readFile(atPath: githubCachePath(deps)),
              let parsed = try? JSONParser.parse(String(bytes: data, encoding: .utf8) ?? ""),
              let members = parsed.asObjectMembers else { return [] }
        return members
    }

    private static func writeGitHubCache(_ cache: [JSONMember], deps: RegistryDeps) {
        // The cache is an optimisation; failing to write it is not an error.
        try? deps.fileSystem.createDirectory(atPath: deps.routerHome)
        let bytes = Data(JSStringify.compact(.object(cache)).utf8)
        try? deps.fileSystem.writeFile(bytes, atPath: githubCachePath(deps))
    }
}
