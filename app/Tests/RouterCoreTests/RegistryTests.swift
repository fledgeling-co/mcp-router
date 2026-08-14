import Foundation
import Testing
@testable import RouterCore

/// A recorded HTTP responder. Every registry test drives this, so nothing here reaches the network.
final class StubHTTP: HTTPFetching, @unchecked Sendable {
    /// url-prefix → response. First matching prefix wins.
    ///
    /// Written once during setup and only read afterwards, so it needs no lock.
    var routes: [(prefix: String, result: Result<HTTPFetchResult, Error>)] = []

    /// Every URL asked for, in no guaranteed order.
    ///
    /// **This was a plain `var` appended to from `get`, and `Registry.search` queries the official
    /// and smithery registries CONCURRENTLY** — so two tasks appended to one array with no
    /// synchronisation, under an `@unchecked Sendable` that promised exactly the safety the class
    /// did not have. A lost append presents as *"that URL was never requested"*, which is why
    /// `absolutePathDiscardsBasePath` failed about one run in five and passed every time it was
    /// re-run alone. It was registered as flaky (`D-p`) before it was understood; it is a data
    /// race, not a timing window, and no amount of waiting would have fixed it.
    /// `withLock` rather than `lock()`/`unlock()`: the latter pair is unavailable from an async
    /// context in Swift 6, and `get` is `async`. The scoped form holds the lock across a
    /// synchronous closure only, which is what makes it safe to call from one.
    private let lock = NSLock()
    private var recorded: [String] = []

    var requested: [String] {
        lock.withLock { recorded }
    }

    func get(
        url: String,
        headers _: [(name: String, value: String)],
        timeoutMs _: Int
    ) async throws -> HTTPFetchResult {
        lock.withLock { recorded.append(url) }
        for route in routes where url.hasPrefix(route.prefix) {
            return try route.result.get()
        }
        throw HTTPFetchError(message: "no stub for \(url)")
    }
}

/// An in-memory filesystem so the GitHub cache never touches disk.
final class MemoryFS: FileSystem, @unchecked Sendable {
    var files: [String: Data] = [:]

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil
    }

    func readFile(atPath path: String) throws -> Data {
        guard let data = files[path] else { throw HTTPFetchError(message: "ENOENT") }
        return data
    }

    func writeFile(_ data: Data, atPath path: String) throws {
        files[path] = data
    }

    func appendFile(_ data: Data, atPath path: String) throws {
        files[path, default: Data()].append(data)
    }

    func createDirectory(atPath _: String) throws {}
    func moveItem(atPath source: String, toPath destination: String) throws {
        files[destination] = files[source]
        files[source] = nil
    }

    func copyItem(atPath source: String, toPath destination: String) throws {
        files[destination] = files[source]
    }

    func removeItem(atPath path: String) throws {
        files[path] = nil
    }

    func contentsOfDirectory(atPath _: String) throws -> [String] {
        []
    }

    func attributes(atPath _: String) throws -> FileStamp {
        FileStamp(
            modified: Date(timeIntervalSince1970: 0),
            size: 0
        )
    }
}

/// The registry port, against `src/registry.ts`.
///
/// The expectations here are the reference's behaviour read off the TypeScript, and the
/// `localeCompare` suite is differential against Node's own output rather than against a belief
/// about ICU.
struct RegistryTests {
    private func json(_ text: String) -> HTTPFetchResult {
        HTTPFetchResult(status: 200, body: Data(text.utf8))
    }

    private func deps(
        _ http: StubHTTP,
        now: Double = 1_000_000,
        token: String? = nil,
        fs: MemoryFS = MemoryFS()
    ) -> RegistryDeps {
        RegistryDeps(
            http: http, fileSystem: fs, routerHome: "/home",
            officialBase: "https://official", smitheryBase: "https://smith",
            githubToken: token, nowMs: now
        )
    }

    private func emptyIndexes(_ http: StubHTTP) {
        http.routes = [
            (prefix: "https://official", result: .success(json(#"{"servers":[]}"#))),
            (prefix: "https://smith", result: .success(json(#"{"servers":[]}"#)))
        ]
    }

    // MARK: - repoKey (B55)

    @Test("repoKey lowercases, stops at the first . ? # /, and yields nothing for a non-GitHub URL")
    func repoKeyShapes() {
        func key(_ url: String) -> String? {
            Registry.repoKey(.string(JSString(url)))?.string
        }
        #expect(key("https://github.com/Owner/Repo") == "owner/repo")
        #expect(key("https://GitHub.com/Owner/Repo.git") == "owner/repo")
        #expect(key("git@github.com:Owner/Repo.git") == "owner/repo")
        #expect(key("https://github.com/Owner/Repo?tab=readme") == "owner/repo")
        #expect(key("https://github.com/Owner/Repo#anchor") == "owner/repo")
        #expect(key("https://gitlab.com/owner/repo") == nil)
        // `if (!url)` is ToBoolean, so an empty string produces no key rather than an empty one.
        #expect(key("") == nil)
        #expect(Registry.repoKey(nil) == nil)
    }

    // MARK: - B54, the limit coercion

    @Test("limit follows Math.min(Number(x ?? 30) || 30, 60) — 0 and NaN become 30, a negative passes")
    func limitCoercion() {
        func coerce(_ raw: String?) -> Double {
            let value = raw.map(JSToNumber.number) ?? 30
            return min((value == 0 || value.isNaN) ? 30 : value, 60)
        }
        #expect(coerce(nil) == 30)
        #expect(coerce("0") == 30)
        #expect(coerce("abc") == 30)
        #expect(coerce("500") == 60)
        #expect(coerce("-5") == -5)
    }

    @Test("slice(0, limit) counts a negative limit back from the end rather than returning nothing")
    func negativeLimitSlices() {
        var rows: [JSObjectDraft] = []
        for index in 0 ..< 8 {
            var row = JSObjectDraft()
            row.set("id", .string(JSString("\(index)")))
            rows.append(row)
        }
        #expect(Registry.jsSlice(rows, limit: -5).count == 3)
        #expect(Registry.jsSlice(rows, limit: 3).count == 3)
        #expect(Registry.jsSlice(rows, limit: -99).isEmpty)
    }

    // MARK: - B55, dedupe and merge

    @Test(
        "a merged row keeps the official key order, takes Smithery's numbers, and keeps the official install"
    )
    func mergeKeepsOfficialShape() async throws {
        let http = StubHTTP()
        http.routes = [
            (prefix: "https://official", result: .success(json(#"""
            {"servers":[{"server":{"name":"io.example/thing","description":"official copy",
              "repository":{"url":"https://github.com/Acme/Thing"},"version":"1.2.3",
              "packages":[{"registryType":"npm","identifier":"thing","version":"9"}]},
              "_meta":{"z":{"updatedAt":"2024-05-05"}}}]}
            """#))),
            (prefix: "https://smith", result: .success(json(#"""
            {"servers":[{"qualifiedName":"thing","displayName":"Thing","description":"smithery copy",
              "homepage":"https://github.com/acme/thing","useCount":42,"verified":true,
              "iconUrl":"https://icon","remote":true,"isDeployed":true}]}
            """#)))
        ]
        let out = try await Registry.search(query: "", limit: 30, deps: deps(http))
        #expect(out.officialCount == 1)
        #expect(out.smitheryCount == 1)
        #expect(out.mergedCount == 1)

        let encoded = JSStringify.compact(out.results[0])
        // The official row's order survives, and Smithery's three numbers append after `install`.
        let expected = [
            #"{"id":"io.example/thing","name":"io.example/thing","#,
            #""displayName":"thing","description":"official copy","source":"both","#,
            #""repository":"https://github.com/Acme/Thing","version":"1.2.3","#,
            #""updatedAt":"2024-05-05","#,
            #""install":{"type":"stdio","command":"npx","args":["-y","thing@9"]},"#,
            #""useCount":42,"verified":true,"iconUrl":"https://icon"}"#
        ].joined()
        #expect(encoded == expected)
    }

    @Test("a repository URL with no GitHub key dedupes on the normalised display name instead")
    func dedupeFallsBackToDisplayName() async throws {
        let http = StubHTTP()
        http.routes = [
            (prefix: "https://official", result: .success(json(#"""
            {"servers":[{"server":{"name":"io.example/My-Thing","description":"",
              "repository":{"url":"https://gitlab.com/acme/thing"}}}]}
            """#))),
            (prefix: "https://smith", result: .success(json(#"""
            {"servers":[{"qualifiedName":"other","displayName":"mything","useCount":7}]}
            """#)))
        ]
        let out = try await Registry.search(query: "", limit: 30, deps: deps(http))
        // "My-Thing" lowercases then drops the hyphen, matching "mything".
        #expect(out.mergedCount == 1)
        #expect(JSStringify.compact(out.results[0]).contains(#""source":"both""#))
    }

    // MARK: - B56, stable ranking

    @Test("ranking is useCount then stars then updatedAt, and a three-way tie keeps arrival order")
    func rankingIsStable() {
        func row(
            _ id: String,
            useCount: Double?,
            stars: Double? = nil,
            updatedAt: String? = nil
        ) -> JSObjectDraft {
            var draft = JSObjectDraft()
            draft.set("id", .string(JSString(id)))
            if let useCount { draft.set("useCount", .number(useCount)) }
            if let stars { draft.set("stars", .number(stars)) }
            if let updatedAt { draft.set("updatedAt", .string(JSString(updatedAt))) }
            return draft
        }
        let tied = Registry.rank([row("a", useCount: 5), row("b", useCount: 5), row("c", useCount: 5)])
        #expect(tied.map { $0.get("id")?.asString?.string } == ["a", "b", "c"])

        let ordered = Registry.rank([
            row("low", useCount: 1), row("high", useCount: 9),
            row("stars", useCount: 1, stars: 100), row("none", useCount: nil)
        ])
        #expect(ordered.map { $0.get("id")?.asString?.string } == ["high", "stars", "low", "none"])
    }
}
