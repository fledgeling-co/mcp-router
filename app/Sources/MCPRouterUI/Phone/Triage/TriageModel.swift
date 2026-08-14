import Foundation
import MCPRouterKit
import Observation

/// Triage's own state: the three buckets, the selection, and the one undoable act.
///
/// **It formats nothing and it decides nothing about layout.** Every string comes from `TriageCopy`
/// and every state from `TriageSurfaceState`, which is what makes the criteria assertions over an
/// enumerable set rather than hopes about a view hierarchy.
@MainActor
@Observable
public final class TriageModel {
    /// The endpoint's cap, matched to Discover's so the two surfaces read the same page. A distinct
    /// limit here would give Triage a different Undecided set from the list Discover shows, which
    /// is the kind of divergence nobody notices until the counts disagree.
    public static let searchLimit = 30

    @ObservationIgnored public let client: any ControlAPIClient
    @ObservationIgnored public let queue: any CapabilityQueueWriter & CapabilityQueueReader
    @ObservationIgnored public let dismissals: any DismissalStore

    public var macName: String?
    public var connection: ConnectionState

    public var bucket: TriageBucket = .undecided
    public internal(set) var state: TriageSurfaceState = .loading
    public internal(set) var buckets = TriageBuckets(undecided: [], queued: [], dismissed: [])

    /// The selection. **Starts empty and is cleared on every bucket change**, which is the first of
    /// the two prototype bugs inverted: on a screen whose job is deliberate selection, a pre-ticked
    /// default makes "send all of these to my laptop" the act you get by doing nothing.
    public internal(set) var selected: Set<String> = []

    /// Which rows are expanded. A set rather than a single id: the surface's whole premise is
    /// comparison across rows, and a disclosure that closes the last one when you open the next
    /// forbids exactly that.
    public internal(set) var expanded: Set<String> = []

    /// The last reversible act, or nil. One slot, not a stack: `DESIGN.md` §9 asks for undo over
    /// confirm, and a phone surface offering an undo history is offering a feature nobody asked for
    /// on the screen where clarity matters most.
    public internal(set) var undo: TriageUndo?

    /// A write that was refused, surfaced rather than swallowed (A14).
    public internal(set) var writeFailure: TriageWriteFailure?

    public init(
        client: any ControlAPIClient,
        queue: any CapabilityQueueWriter & CapabilityQueueReader,
        dismissals: any DismissalStore,
        connection: ConnectionState = .reachable,
        macName: String? = nil
    ) {
        self.client = client
        self.queue = queue
        self.dismissals = dismissals
        self.connection = connection
        self.macName = macName
    }

    // MARK: - Loading

    /// One read of the registry, one of the queue, one of the dismissal set.
    ///
    /// The dismissal read's failure is carried rather than absorbed: `resolve` puts
    /// `.dismissalsUnreadable` ahead of every populated state, because a list rendered from a
    /// dismissal set that failed to load is a list showing things the user already rejected, and
    /// looking correct while doing it.
    public func load() async {
        state = .loading

        let dismissedIDs: Result<Set<String>, DismissalStoreError>
        do {
            dismissedIDs = try await .success(Set(dismissals.all().map(\.id)))
        } catch let error as DismissalStoreError {
            dismissedIDs = .failure(error)
        } catch {
            dismissedIDs = .failure(.unreadable(error.localizedDescription))
        }

        // Taken as a `Result`, exactly as the dismissal read above is.
        //
        // An earlier shape was `if let items = try? await queue.all()`, reasoning that an
        // unreadable queue was "the Queue surface's error to report, not this one's". That is
        // wrong, and A9 says why in its own words: `Undecided = results − queued − dismissed`, so a
        // queue that will not decode returns every already-queued entry to Undecided and offers it
        // for queueing again. The Queue tab reports the same file correctly one tap away, so the
        // two surfaces disagree and the honest one is the quieter.
        let queuedIDs: Result<Set<String>, CapabilityQueueError>
        do {
            queuedIDs = try await .success(Set(queue.all().map(\.id)))
        } catch let error as CapabilityQueueError {
            queuedIDs = .failure(error)
        } catch {
            queuedIDs = .failure(.unreadable(error.localizedDescription))
        }

        let results: Result<RegistrySearchResponse, ControlAPIError>
        do {
            results = try await .success(client.searchRegistry(query: "", limit: Self.searchLimit))
        } catch let error as ControlAPIError {
            results = .failure(error)
        } catch {
            results = .failure(.transport(detail: error.localizedDescription))
        }

        if case let .success(dismissed) = dismissedIDs,
           case let .success(queued) = queuedIDs,
           case let .success(response) = results
        {
            buckets = TriageBuckets.resolve(
                results: response.results,
                queuedIDs: queued,
                dismissedIDs: dismissed
            )
        }

        state = TriageSurfaceState.resolve(
            results: results,
            queuedIDs: queuedIDs,
            dismissedIDs: dismissedIDs
        )
    }

    // MARK: - Selection

    public func toggleSelection(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    public func toggleExpansion(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Only entries with an install descriptor are selectable: with no descriptor there is nothing
    /// for the Mac to review, so there is nothing to send.
    public var selectableIDs: [String] {
        buckets.undecided.filter { $0.install != nil }.map(\.id)
    }

    public var isAllSelected: Bool {
        !selectableIDs.isEmpty && selected.count == selectableIDs.count
    }

    public func selectAllOrClear() {
        if isAllSelected { selected.removeAll() } else { selected = Set(selectableIDs) }
    }

    public func select(bucket newBucket: TriageBucket) {
        bucket = newBucket
        // Cleared on every bucket change. A selection carried across a bucket switch is a selection
        // the user cannot see, attached to a commit bar that says a number they cannot account for.
        selected.removeAll()
        undo = nil
    }

    /// What the surface actually draws.
    ///
    /// **Bucket emptiness is derived here rather than baked into `state`**, because it is a fact
    /// about the *chosen* bucket and the chosen bucket changes without another load. An earlier
    /// draft re-ran the resolver on a bucket switch by rebuilding a synthetic `RegistrySearchResponse`
    /// from the three bucket arrays — which is a fabricated input standing in for a real one, and
    /// exactly the kind of thing that later reads as a genuine response.
    public var displayState: TriageSurfaceState {
        // **`.partial` gets the same treatment as `.populated`.** An earlier guard matched only
        // `.populated`, so with the official registry down and everything Smithery returned already
        // queued, Undecided rendered the segments, the warning and the hint — and nothing below
        // them. A blank list under a warning reads as the warning having eaten the results.
        switch state {
        case .populated, .partial:
            buckets.count(in: bucket) == 0 ? .empty(bucket) : state
        default:
            state
        }
    }

    public var commitState: TriageCommitState {
        TriageCommitState.resolve(selectionCount: selected.count, connection: connection)
    }
}
