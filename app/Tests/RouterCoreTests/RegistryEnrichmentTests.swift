import Foundation
import Testing
@testable import RouterCore

/// GitHub enrichment and the degradation paths.
///
/// A separate file from `RegistryTests` only because the repo caps a file at 400 lines and a type
/// body at 250. The doubles are shared from `RegistryTests.swift`.
struct RegistryEnrichmentTests {
    private func json(_ text: String) -> HTTPFetchResult {
        HTTPFetchResult(status: 200, body: Data(text.utf8))
    }

    private func deps(
        _ http: StubHTTP, now: Double = 1_000_000, token: String? = nil, fs: MemoryFS = MemoryFS()
    ) -> RegistryDeps {
        RegistryDeps(
            http: http, fileSystem: fs, routerHome: "/home",
            officialBase: "https://official", smitheryBase: "https://smith",
            githubToken: token, nowMs: now
        )
    }

    // MARK: - B57, the GitHub budget

    @Test("enrichment spends at most ten requests, and the first 403 stops it with the no-token warning")
    func githubBudgetAndRateLimit() async throws {
        let http = StubHTTP()
        var servers: [String] = []
        for index in 0 ..< 12 {
            servers
                .append(
                    #"{"server":{"name":"io.example/s\#(index)","repository":{"url":"https://github.com/acme/r\#(index)"}}}"#
                )
        }
        http.routes = [
            (
                prefix: "https://official",
                result: .success(json(#"{"servers":[\#(servers.joined(separator: ","))]}"#))
            ),
            (prefix: "https://smith", result: .success(json(#"{"servers":[]}"#))),
            (prefix: "https://api.github.com", result: .success(HTTPFetchResult(status: 403, body: Data())))
        ]
        let out = try await Registry.search(query: "", limit: 30, deps: deps(http))
        let githubCalls = http.requested.filter { $0.hasPrefix("https://api.github.com") }
        // The first 403 sets rateLimited, so exactly one request is spent, not the whole budget.
        #expect(githubCalls.count == 1)
        #expect(out.warnings == [
            "GitHub allows 60 requests an hour without a token, so star counts are partial. "
                + "Set GITHUB_TOKEN to raise it."
        ])
    }

    @Test("a token present swaps the rate-limit warning for the shorter one")
    func githubRateLimitWithToken() async throws {
        let http = StubHTTP()
        http.routes = [
            (prefix: "https://official", result: .success(json(#"""
            {"servers":[{"server":{"name":"a/b","repository":{"url":"https://github.com/acme/r"}}}]}
            """#))),
            (prefix: "https://smith", result: .success(json(#"{"servers":[]}"#))),
            (prefix: "https://api.github.com", result: .success(HTTPFetchResult(status: 429, body: Data())))
        ]
        let out = try await Registry.search(query: "", limit: 30, deps: deps(http, token: "gh-token"))
        #expect(out.warnings == ["GitHub rate limit reached; star counts are partial."])
    }

    @Test("a cache entry inside 24h is served without a request, and one past it is refetched")
    func githubCacheTTL() async throws {
        let filesystem = MemoryFS()
        let now: Double = 100_000_000
        filesystem.files["/home/github-cache.json"] = Data(#"""
        {"acme/fresh":{"stars":11,"at":\#(JSNumber.string(now - 1000))},
         "acme/stale":{"stars":22,"at":\#(JSNumber.string(now - Registry.githubTTLMs - 1))}}
        """#.utf8)

        let http = StubHTTP()
        http.routes = [
            (prefix: "https://official", result: .success(json(#"""
            {"servers":[
              {"server":{"name":"a/fresh","repository":{"url":"https://github.com/acme/fresh"}}},
              {"server":{"name":"a/stale","repository":{"url":"https://github.com/acme/stale"}}}]}
            """#))),
            (prefix: "https://smith", result: .success(json(#"{"servers":[]}"#))),
            (prefix: "https://api.github.com", result: .success(json(#"{"stargazers_count":99}"#)))
        ]
        let out = try await Registry.search(query: "", limit: 30, deps: deps(http, now: now, fs: filesystem))
        let githubCalls = http.requested.filter { $0.hasPrefix("https://api.github.com") }
        #expect(githubCalls == ["https://api.github.com/repos/acme/stale"])

        let encoded = out.results.map { JSStringify.compact($0) }.joined()
        #expect(encoded.contains(#""stars":11"#))
        #expect(encoded.contains(#""stars":99"#))
    }

    // MARK: - B58, degradation

    @Test("an unreachable index is a warning with partial results, not a failure")
    func unreachableIndexDegrades() async throws {
        let http = StubHTTP()
        http.routes = [
            (prefix: "https://official", result: .failure(HTTPFetchError(message: "HTTP 500"))),
            (prefix: "https://smith", result: .success(json(#"""
            {"servers":[{"qualifiedName":"kept","displayName":"kept"}]}
            """#)))
        ]
        let out = try await Registry.search(query: "", limit: 30, deps: deps(http))
        #expect(out.warnings == ["official registry unreachable: HTTP 500"])
        #expect(out.officialCount == 0)
        #expect(out.mergedCount == 1)
    }

    @Test("both indexes down yields both warnings in source order and an empty result set")
    func bothIndexesDown() async throws {
        let http = StubHTTP()
        http.routes = [
            (prefix: "https://official", result: .failure(HTTPFetchError(message: "HTTP 502"))),
            (prefix: "https://smith", result: .failure(HTTPFetchError(message: "HTTP 503")))
        ]
        let out = try await Registry.search(query: "", limit: 30, deps: deps(http))
        #expect(out.warnings == [
            "official registry unreachable: HTTP 502",
            "Smithery unreachable: HTTP 503"
        ])
        #expect(out.results.isEmpty)
    }

    // MARK: - B59, the environment bases

    @Test("a registry base defaults only when absent — an empty string is used as given")
    func basesDefaultOnlyOnAbsence() {
        let http = StubHTTP()
        let absent = RegistryDeps(http: http, fileSystem: MemoryFS(), routerHome: "/h", nowMs: 0)
        #expect(absent.official == "https://registry.modelcontextprotocol.io")
        #expect(absent.smithery == "https://registry.smithery.ai")

        // `??` is nullish, so `""` survives rather than falling back (S2).
        let empty = RegistryDeps(
            http: http, fileSystem: MemoryFS(), routerHome: "/h",
            officialBase: "", smitheryBase: "", nowMs: 0
        )
        #expect(empty.official.isEmpty)
        #expect(empty.smithery.isEmpty)
    }

    // MARK: - Row decoding

    @Test("an official row with no name is skipped, and a trailing slash leaves an empty displayName")
    func officialRowEdges() async throws {
        let http = StubHTTP()
        http.routes = [
            (prefix: "https://official", result: .success(json(#"""
            {"servers":[{"server":{"name":"","description":"skipped"}},
                        {"server":{"name":"io.example/"}}]}
            """#))),
            (prefix: "https://smith", result: .success(json(#"{"servers":[]}"#)))
        ]
        let out = try await Registry.search(query: "", limit: 30, deps: deps(http))
        #expect(out.officialCount == 1)
        #expect(JSStringify.compact(out.results[0]).contains(#""displayName":"""#))
    }

    @Test("a Smithery row that is not deployed carries no install, and an empty displayName falls back")
    func smitheryRowEdges() async throws {
        let http = StubHTTP()
        http.routes = [
            (prefix: "https://official", result: .success(json(#"{"servers":[]}"#))),
            (prefix: "https://smith", result: .success(json(#"""
            {"servers":[{"qualifiedName":"acme/thing","displayName":"","remote":true,"isDeployed":false}]}
            """#)))
        ]
        let out = try await Registry.search(query: "", limit: 30, deps: deps(http))
        let encoded = JSStringify.compact(out.results[0])
        // `s.displayName || s.qualifiedName` is truthiness, so "" falls back to the qualified name.
        #expect(encoded.contains(#""displayName":"acme/thing""#))
        #expect(!encoded.contains("install"))
    }

    @Test("a pypi package installs with uvx, and an unknown registry type yields no install at all")
    func officialInstallShapes() async throws {
        let http = StubHTTP()
        http.routes = [
            (prefix: "https://official", result: .success(json(#"""
            {"servers":[
              {"server":{"name":"a/py","packages":[{"registryType":"pypi","identifier":"pkg"}]}},
              {"server":{"name":"a/other","packages":[{"registryType":"gem","identifier":"pkg"}]}}]}
            """#))),
            (prefix: "https://smith", result: .success(json(#"{"servers":[]}"#)))
        ]
        let out = try await Registry.search(query: "", limit: 30, deps: deps(http))
        let encoded = out.results.map { JSStringify.compact($0) }
        #expect(encoded.contains { $0.contains(#""command":"uvx","args":["pkg"]"#) })
        #expect(encoded.contains { !$0.contains("install") })
    }
}

/// URL resolution and cache-file stability — both found by auditing `RegistrySearch` against
/// `src/registry.ts` after the out-of-family critic lane failed twice and the pass fell back
/// in-family. Both are behaviours `new URL(path, base)` has and string concatenation does not.
struct RegistryURLTests {
    private func json(_ text: String) -> HTTPFetchResult {
        HTTPFetchResult(status: 200, body: Data(text.utf8))
    }

    @Test("an absolute path discards the base's own path, as new URL(path, base) does")
    func absolutePathDiscardsBasePath() async throws {
        let http = StubHTTP()
        http.routes = [(prefix: "https://", result: .success(json(#"{"servers":[]}"#)))]
        let deps = RegistryDeps(
            http: http, fileSystem: MemoryFS(), routerHome: "/home",
            officialBase: "https://host/ignored", smitheryBase: "https://host2/also-ignored",
            nowMs: 0
        )
        _ = try await Registry.search(query: "", limit: 30, deps: deps)
        // Node: new URL("/v0/servers", "https://host/ignored") -> https://host/v0/servers
        #expect(http.requested.contains { $0.hasPrefix("https://host/v0/servers?") })
        #expect(http.requested.contains { $0.hasPrefix("https://host2/servers?") })
        #expect(!http.requested.contains { $0.contains("ignored") })
    }

    @Test("an empty base is preserved and then fails as an Invalid URL, matching the reference's TypeError")
    func emptyBaseIsInvalidNotDefaulted() async throws {
        let http = StubHTTP()
        let deps = RegistryDeps(
            http: http, fileSystem: MemoryFS(), routerHome: "/home",
            officialBase: "", smitheryBase: "", nowMs: 0
        )
        let out = try await Registry.search(query: "", limit: 30, deps: deps)
        // `??` is nullish, so "" is used as given and `new URL` throws rather than defaulting.
        #expect(out.warnings == [
            "official registry unreachable: Invalid URL",
            "Smithery unreachable: Invalid URL"
        ])
        #expect(http.requested.isEmpty)
    }

    @Test("a refreshed cache entry keeps its slot, so the cache file does not reorder each run")
    func cacheKeepsKeySlot() async throws {
        let filesystem = MemoryFS()
        let now: Double = 100_000_000
        filesystem.files["/home/github-cache.json"] = Data(#"""
        {"acme/stale":{"stars":1,"at":0},"acme/other":{"stars":2,"at":\#(JSNumber.string(now))}}
        """#.utf8)
        let http = StubHTTP()
        http.routes = [
            (prefix: "https://official", result: .success(json(#"""
            {"servers":[{"server":{"name":"a/s","repository":{"url":"https://github.com/acme/stale"}}}]}
            """#))),
            (prefix: "https://smith", result: .success(json(#"{"servers":[]}"#))),
            (prefix: "https://api.github.com", result: .success(json(#"{"stargazers_count":50}"#)))
        ]
        let deps = RegistryDeps(
            http: http, fileSystem: filesystem, routerHome: "/home",
            officialBase: "https://official", smitheryBase: "https://smith", nowMs: now
        )
        _ = try await Registry.search(query: "", limit: 30, deps: deps)
        let written = String(bytes: filesystem.files["/home/github-cache.json"] ?? Data(), encoding: .utf8) ??
            ""
        // The refreshed key stays first; re-appending would have moved it behind "acme/other".
        #expect(written.hasPrefix(#"{"acme/stale":"#))
        #expect(written.contains(#""stars":50"#))
    }
}
