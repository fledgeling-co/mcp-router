import Foundation

/// The one HTTP GET the registry search makes, against a real network.
///
/// `HTTPFetching` was declared by R1 so the registry pipeline could be tested without a network,
/// and until P3 **every conformance to it lived in a test target**. The daemon built its
/// ``ControlDeps`` without a `registry:`, so `ControlHandler.registrySearch` took its `guard` and
/// answered `502 registry search is unavailable: no HTTP client is configured` — measured on the
/// wire, where the reference answers 200. The whole merge, dedupe, coercion and ranking pipeline
/// was implemented, unit-tested, and unreachable in the process that ships.
///
/// Deliberately thin. It performs the request and reports what came back; it does **not** decide
/// what a status means. `Registry.getJSON` applies the reference's own rule —
/// `if (!r.ok) throw new Error(\`HTTP ${r.status}\`)` — and a second opinion here would be a
/// second place for the two routers to disagree.
public struct RegistryHTTPClient: HTTPFetching {
    /// EPHEMERAL, not `URLSession.shared`, and the difference is a divergence rather than hygiene.
    ///
    /// `URLSession.shared` carries the process-wide `URLCache`, cookie storage and credential
    /// store. node's `fetch` has no HTTP cache at all, so a registry response that arrived with
    /// `Cache-Control: max-age=…` would be re-served from disk by the Swift daemon and re-fetched
    /// by the reference — the two would answer differently from the same upstream, and a parity
    /// lane pointed at a pinned fixture is exactly the place that would never show it. The cache
    /// also outlives the query: a search run twice would return the first answer.
    private static let session = URLSession(configuration: .ephemeral)

    public init() {}

    public func get(
        url: String,
        headers: [(name: String, value: String)],
        timeoutMs: Int
    ) async throws -> HTTPFetchResult {
        // `new URL(...)` throws on a malformed target and the reference reports it as the search
        // failing rather than the router failing. Same message, same shape.
        guard let target = URL(string: url) else {
            throw HTTPFetchError(message: "Invalid URL")
        }
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        request.timeoutInterval = Double(timeoutMs) / 1000
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        let body: Data
        let response: URLResponse
        do {
            (body, response) = try await Self.session.data(for: request)
        } catch {
            // The message is USER-VISIBLE: `searchRegistries` interpolates it into
            // `official registry unreachable: ${err.message}`, which the Discover board renders.
            //
            // Measured on 2026-08-15 rather than assumed. `URLSession` throws an `NSError` whose
            // `localizedDescription`, let alone its `description`, is a paragraph — the first cut
            // of this client put a full `NSURLErrorDomain` dump including the failing URL and an
            // internal task id into that warning. node's `fetch` throws these, and only these:
            //     connection refused → TypeError  "fetch failed"
            //     DNS failure        → TypeError  "fetch failed"
            //     AbortController    → AbortError "This operation was aborted"
            // so those are the two messages, and reproducing them is parity rather than
            // decoration — this is the same route whose 502 nobody could see.
            //
            // NOT the same thing as node's deadline, and said here rather than implied:
            // `timeoutInterval` is URLSession's idle timeout between packets, where the reference
            // aborts 12s after the request began. A server that dribbles bytes forever is aborted
            // by one and not the other. `D-p3-e`.
            //
            // AND THE MAPPING IS COARSER THAN THE TABLE ABOVE READS. Only `.timedOut` produces the
            // abort wording; every other `URLError` — `.cancelled`, `.serverCertificateUntrusted`,
            // a TLS failure, too many redirects — becomes "fetch failed". For refused connections
            // and DNS that is exactly right, and those are the two the lane compares. For the rest
            // it is a guess that node would have said the same thing, and it is written down as a
            // guess: `.cancelled` in particular is what an `AbortController` looks like from
            // URLSession's side, and it is NOT mapped to "This operation was aborted" here.
            if (error as? URLError)?.code == .timedOut {
                throw HTTPFetchError(message: "This operation was aborted")
            }
            throw HTTPFetchError(message: "fetch failed")
        }
        guard let http = response as? HTTPURLResponse else {
            // Not reachable over http/https, and not force-unwrapped for that reason: a crash in
            // the daemon is a worse answer to an unexpected response than a failed search is.
            throw HTTPFetchError(message: "the response was not HTTP")
        }
        return HTTPFetchResult(status: http.statusCode, body: body)
    }
}
