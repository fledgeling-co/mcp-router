import Foundation

/// What the Library surface is showing.
///
/// **No `success` case and no `partial` case.** The Library has no commit, so there is nothing to
/// succeed; and `GET /servers` returns one document, so there is no half of it to fail. Both are
/// recorded rather than given invented copy.
public enum LibrarySurfaceState: Sendable, Equatable {
    case populated([MCPServer])
    case empty
    /// The filter matched nothing. Distinct from `empty`, and it names the filter rather than the
    /// library — a user who has typed something wants to know their typing is why the list is bare.
    case emptyFiltered(query: String, total: Int)
    case loading
    case failed(DiscoverFailureReason)
    case offline

    public static func resolve(
        servers: Result<[MCPServer], ControlAPIError>?,
        filter: String
    ) -> LibrarySurfaceState {
        guard let servers else { return .loading }

        switch servers {
        case let .failure(error):
            guard let reason = DiscoverFailureReason.from(error) else { return .offline }
            return .failed(reason)

        case let .success(all):
            guard !all.isEmpty else { return .empty }
            let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .populated(all) }

            let matched = all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            return matched.isEmpty
                ? .emptyFiltered(query: trimmed, total: all.count)
                : .populated(matched)
        }
    }

    public var copyKey: LibraryCopy.Key? {
        switch self {
        case .populated, .loading: nil
        case .empty: .state(.empty)
        case .emptyFiltered: .state(.emptyFiltered)
        case .failed: .state(.failed)
        case .offline: .state(.offline)
        }
    }
}

/// One server's facts, as the row renders them.
///
/// **`neverStarted` exists because `idleSec == 0` is ambiguous.** The router computes
/// `state: live?.state ?? 'idle'` and `idleSec: live?.idleSec ?? 0`, so a server that has never
/// been started is byte-identical to one that went idle this instant. Rendering the first as
/// "idle" — or worse, "idle 0s" — states a freshness nobody observed. `MCPServer.neverUsed`
/// (`usage.calls == 0`) is what separates them, and it is the only reason `usage` is in this
/// surface's permitted field set at all.
public enum LibraryRowFact: Sendable, Equatable {
    case running
    case idle(seconds: Int)
    case neverStarted

    public static func resolve(for server: MCPServer) -> LibraryRowFact {
        if server.state == .running { return .running }
        if server.neverUsed { return .neverStarted }
        return .idle(seconds: server.idleSec)
    }

    public var copyKey: LibraryCopy.Key {
        switch self {
        case .running: .fact(.runningNow)
        case .idle: .fact(.idleFor)
        case .neverStarted: .fact(.neverStarted)
        }
    }

    /// `--live` is permitted on exactly one of these, and only because that is what the token
    /// means: a child process is running.
    public var isLive: Bool { self == .running }
}
