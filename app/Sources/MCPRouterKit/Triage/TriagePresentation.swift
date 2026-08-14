import Foundation

/// Every string the three surfaces render that is not a fixed sentence from a copy manifest.
///
/// **It is here rather than in the views for the reason M4 learned the hard way**: a decision made
/// inside a view body can only be proven by rendering it, and a decision made in a type like this
/// can be proven by calling it. The views end up as a `switch` with no logic, which is what let M4's
/// guards be proven at all when no accessibility grant was available.
///
/// Nothing here invents a figure. Every number that reaches a string came from a named `MCPServer`
/// field or is the size of a locally-held set.
public enum TriagePresentation {
    // MARK: - Triage rows

    /// The row's second line: who published it, and which index it came from.
    ///
    /// No licence, no eval count and no install count — `RegistryEntry` carries none of the three,
    /// and the prototype's triage rows carry all three.
    public static func provenance(for entry: RegistryEntry) -> String {
        let index = switch entry.source {
        case .official: "official registry"
        case .smithery: "Smithery"
        case .both: "both indexes"
        }
        // `name` is the qualified name; its owner segment is the publisher where there is one.
        let owner = entry.name.split(separator: "/").dropLast().last.map(String.init)
        guard let owner, !owner.isEmpty else { return index }
        return "\(owner) · \(index)"
    }

    /// The row's capability line, clauses joined.
    public static func summaryText(_ summary: CapabilitySummary.Resolved) -> String {
        summary.text { clause in
            let entry = TriageCopy.entry(.clause(clauseKey(clause)))
            guard clause == .remote, let host = summary.host else { return entry.body }
            return entry.resolved([.host: host]).body
        }
    }

    private static func clauseKey(_ clause: CapabilitySummary.Clause) -> TriageCopy.ClauseKey {
        switch clause {
        case .runsLocally: .runsLocally
        case .remote: .remote
        case .remoteUnknownHost: .remoteUnknownHost
        case .credential: .credential
        case .credentialSmithery: .credentialSmithery
        case .archived: .archived
        case .noInstall: .noInstall
        }
    }

    // MARK: - Queue rows

    /// When this phone queued an item.
    ///
    /// The stamp is the **only** temporal fact the Queue may state, because it is the only one the
    /// phone observed: it wrote the row, so it knows when. Anything about what the Mac has done
    /// with it since would need a transport, and there is none.
    public static func queuedStamp(_ date: Date, now: Date = Date(), locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        if Calendar.current.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = nil
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "today, \(formatter.string(from: date))"
        }
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Library rows

    /// One server's facts, joined. Every element is a named `MCPServer` field.
    public static func libraryFacts(for server: MCPServer, now: Date = Date()) -> [String] {
        var facts = [server.transport.rawValue]
        facts.append(
            LibraryCopy.entry(.fact(.toolCount))
                .resolved([.count: String(server.tools)]).body
        )

        let fact = LibraryRowFact.resolve(for: server)
        switch fact {
        case .running, .neverStarted:
            facts.append(LibraryCopy.entry(fact.copyKey).body)
        case let .idle(seconds):
            // `shortAgo` is the merged formatter every other surface uses for an elapsed span, fed
            // the instant the server went idle. Writing a second duration formatter here would give
            // the phone a vocabulary the Mac does not share, which `DESIGN.md` §6's one-name-per-
            // state rule forbids.
            let since = now.addingTimeInterval(-Double(seconds))
            facts.append(
                LibraryCopy.entry(fact.copyKey)
                    .resolved([.count: shortAgo(since, from: now)]).body
            )
        }
        return facts
    }
}
