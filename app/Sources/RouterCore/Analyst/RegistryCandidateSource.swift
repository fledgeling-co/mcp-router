import Foundation

/// Candidates from the same registry the Discover board searches.
///
/// **The router names the capabilities; the model only chooses between them.** That is the whole
/// reason this is a separate step rather than a sentence in the prompt: a model asked to name a
/// package names one whether or not it exists, and a recommendation the user can press *Install* on
/// has to be an entry that resolves.
///
/// One search per signal, capped, and the results merged in first-seen order. Capped because a
/// machine with twelve distinct signals would otherwise issue twelve network searches for one
/// button press, and because a prompt listing a hundred candidates is a prompt that recommends the
/// first thing it reads.
public struct RegistryCandidateSource: AnalystCandidateSource {
    public static let searchesPerRun = 4
    public static let resultsPerSearch: Double = 5
    public static let candidateCap = 20

    let deps: RegistryDeps

    public init(deps: RegistryDeps) {
        self.deps = deps
    }

    public func candidates(for signals: [String]) async -> [AnalystCandidate]? {
        var found: [AnalystCandidate] = []
        var seen: Set<String> = []
        var reached = false
        for signal in signals.prefix(Self.searchesPerRun) {
            guard let outcome = try? await Registry.search(
                query: query(from: signal), limit: Self.resultsPerSearch, deps: deps
            ) else { continue }
            reached = true
            for row in outcome.results {
                guard let candidate = Self.candidate(row), !seen.contains(candidate.id) else {
                    continue
                }
                seen.insert(candidate.id)
                found.append(candidate)
            }
        }
        // `nil` rather than `[]` when no search completed: a registry that could not be reached and
        // a registry that holds nothing for these signals are the same list and different facts,
        // and only the first is `candidatesUnavailable`.
        guard reached else { return nil }
        return Array(found.prefix(Self.candidateCap))
    }

    /// The signal reduced to a search term. A command signal is `docker logs` and the useful query
    /// is `docker`; a missing-tool signal is already the term.
    func query(from signal: String) -> String {
        signal.split(separator: " ").first.map(String.init) ?? signal
    }

    static func candidate(_ row: JSONValue) -> AnalystCandidate? {
        let id = row.member("name")?.asString?.string ?? row.member("id")?.asString?.string
        guard let id, !id.isEmpty else { return nil }
        let display = row.member("displayName")?.asString?.string ?? id
        let summary = row.member("description")?.asString?.string
            ?? row.member("summary")?.asString?.string
            ?? "no description in the registry"
        return AnalystCandidate(id: id, name: display, summary: summary)
    }
}
