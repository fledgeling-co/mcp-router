import Foundation

/// `GET /registry/search`.
///
/// Split from the dispatcher for the same reason the usage endpoints are: file length. The
/// coercions and the envelope are the reference's.
extension ControlHandler {
    func registrySearch(_ request: ControlAPIRequest, _ deps: ControlDeps) async -> ControlAPIResponse {
        guard let registryDeps = deps.registry else {
            // The network client is R2's to supply. Answering 502 with the reference's own error
            // shape keeps the surface honest rather than inventing an empty result set, which would
            // read to the app as "the registries returned nothing".
            return .error(502, "registry search is unavailable: no HTTP client is configured")
        }

        // `Math.min(Number(x ?? 30) || 30, 60)` — `||` is ToBoolean, so both `0` and `NaN` become
        // 30, and a negative value passes straight through (N6, B54). The rule lives in
        // `Registry.coerceLimit` so the parity corpus drives the same code this call does.
        let limit = Registry.coerceLimit(request.first(named: "limit"))
        let query = request.first(named: "q") ?? ""

        let outcome: RegistrySearchResult
        do {
            outcome = try await Registry.search(query: query, limit: limit, deps: registryDeps)
        } catch {
            // Only a throw escaping the merge is a 502; an unreachable index is a warning with
            // partial results, which `Registry.search` has already folded in (B58).
            return .error(502, (error as? HTTPFetchError)?.message ?? "\(error)")
        }

        // `installed` is keyed on **displayName**, not on id or name — the reference compares
        // against the live upstream map's keys (B53).
        let installedNames = deps.upstreams.map(\.name)
        let results: [JSONValue] = outcome.results.map { row in
            guard var members = row.asObjectMembers else { return row }
            let display = members.first { $0.key == JSString("displayName") }?.value.asString
            let installed = display.map { installedNames.contains($0) } ?? false
            members.append(JSONMember(key: "installed", value: .bool(installed)))
            return .object(members)
        }

        // `{...out, results}` — `results` keeps slot 0, so the envelope stays results, sources,
        // warnings.
        return .json(200, .object([
            JSONMember(key: "results", value: .array(results)),
            JSONMember(key: "sources", value: .object([
                JSONMember(key: "official", value: .number(Double(outcome.officialCount))),
                JSONMember(key: "smithery", value: .number(Double(outcome.smitheryCount))),
                JSONMember(key: "merged", value: .number(Double(outcome.mergedCount)))
            ])),
            JSONMember(key: "warnings", value: .array(outcome.warnings.map { .string(JSString($0)) }))
        ]))
    }
}
