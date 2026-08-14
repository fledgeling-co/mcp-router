import Foundation

/// What the Triage surface is showing, as one value a test can construct.
///
/// Driving the surface from an enum rather than from a scatter of optionals is what makes
/// `DESIGN.md` §5 checkable: a test enumerates the cases, renders each, and a tenth state added
/// without copy fails to compile rather than shipping blank.
public enum TriageSurfaceState: Sendable, Equatable {
    /// Populated. Carries the buckets and whether the dismissal set could be read.
    case populated(TriageBuckets)
    /// The chosen bucket is empty while the surface is otherwise fine. One bucket empty and another
    /// populated is the common case, not an edge case.
    case empty(TriageBucket)
    case loading
    /// Results arrived, and something is missing. Reuses I2's classification rather than a second
    /// prefix match over the same free text.
    case partial(TriageBuckets, [WarningClass])
    case failed(DiscoverFailureReason)
    /// The router is not running on the paired Mac. Its own state, never a generic error
    /// (`SWIFT_PRACTICES.md` §3).
    case offline
    /// A9: the dismissal file exists and will not decode. **Distinct from every other state**,
    /// because a dismissal set silently read as empty re-offers everything the user turned down —
    /// the failure-mode-is-emptiness defect, applied to the set nobody thinks to check.
    case dismissalsUnreadable
    /// The queue file exists and will not decode. Distinct from `dismissalsUnreadable` because the
    /// two sets fail for different reasons and the user can act on a different one of them.
    case queueUnreadable

    /// Resolve the **load outcome** from what the surface actually has.
    ///
    /// It never returns `.empty`. Which bucket is empty is a fact about the bucket the user has
    /// chosen, and that changes without another load — so it is derived at the model
    /// (`TriageModel.displayState`) from `TriageBuckets.count(in:)`. Folding it in here would mean
    /// re-resolving on every segment tap with inputs the resolver would have to be handed twice.
    ///
    /// The order of the guards is the order of the claims: an unreadable dismissal set outranks a
    /// populated list, because a list rendered from a dismissal set that failed to load is a list
    /// showing things the user already rejected, and looking correct while doing it.
    public static func resolve(
        results: Result<RegistrySearchResponse, ControlAPIError>?,
        queuedIDs: Result<Set<String>, CapabilityQueueError>,
        dismissedIDs: Result<Set<String>, DismissalStoreError>
    ) -> TriageSurfaceState {
        guard case let .success(dismissed) = dismissedIDs else {
            return .dismissalsUnreadable
        }

        // The queue read is taken as a `Result` for the same reason the dismissal read is. An
        // earlier shape used `try?` here, which meant an unreadable queue degraded to "nothing is
        // queued" — returning every already-queued entry to Undecided, silently, while the Queue
        // tab one tap away reported the file correctly. Two surfaces disagreeing about one file,
        // with the honest one quieter.
        guard case let .success(queued) = queuedIDs else {
            return .queueUnreadable
        }

        guard let results else { return .loading }

        switch results {
        case let .failure(error):
            // `routerNotRunning` is its own surface, and `DiscoverFailureReason.from` returns nil
            // for exactly that case, which is how the two stay distinguishable.
            guard let reason = DiscoverFailureReason.from(error) else { return .offline }
            return .failed(reason)

        case let .success(response):
            let buckets = TriageBuckets.resolve(
                results: response.results,
                queuedIDs: queued,
                dismissedIDs: dismissed
            )
            let warnings = WarningClass.classify(response.warnings)
            if !warnings.isEmpty {
                return .partial(buckets, warnings)
            }
            return .populated(buckets)
        }
    }

    /// The copy key for a state that renders as a pane. Nil where the state renders rows instead.
    public var copyKey: TriageCopy.Key? {
        switch self {
        case .populated, .loading: nil
        case let .empty(bucket):
            switch bucket {
            case .undecided: .state(.emptyUndecided)
            case .queued: .state(.emptyQueued)
            case .dismissed: .state(.emptyDismissed)
            }
        case .partial: nil
        case .failed: .state(.failed)
        case .offline: .state(.offline)
        case .dismissalsUnreadable: .state(.dismissalsUnreadable)
        case .queueUnreadable: .state(.queueUnreadable)
        }
    }
}

/// What the commit bar is doing.
///
/// Three cases, and the distinction between the first two is the one that matters:
/// **`absent` is not `disabled`.** With nothing ticked and a Mac paired there is nothing to commit,
/// so there is no commit control at all. With no Mac paired the bar is present and dimmed *from
/// first appearance*, because the reason — there is nowhere to send this — is a fact about the
/// surface rather than about the selection, and a user who ticks four rows and only then learns
/// there is no destination has been allowed to waste the work.
public enum TriageCommitState: Sendable, Equatable {
    case absent
    case ready(count: Int)
    case neverPaired(count: Int)

    public static func resolve(selectionCount: Int, connection: ConnectionState) -> TriageCommitState {
        // `canQueue`, never `canSend`. Queueing writes to this phone's own storage and succeeds
        // with the Mac asleep; the only state that can refuse it is the one where there is no Mac
        // to queue *for*. I2 added the distinction precisely so this line could not be written the
        // obvious wrong way.
        guard connection.canQueue else { return .neverPaired(count: selectionCount) }
        return selectionCount == 0 ? .absent : .ready(count: selectionCount)
    }

    public var copyKey: TriageCopy.Key? {
        switch self {
        case .absent: nil
        case .ready: .commit(.ready)
        case .neverPaired: .commit(.neverPaired)
        }
    }

    public var count: Int {
        switch self {
        case .absent: 0
        case let .ready(count), let .neverPaired(count): count
        }
    }
}
