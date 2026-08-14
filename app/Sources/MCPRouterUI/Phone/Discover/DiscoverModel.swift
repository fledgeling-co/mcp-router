import Foundation
import MCPRouterKit
import Observation

/// Discover's own state, and its one read of the router.
///
/// **It formats nothing.** Every string this model hands a view came from `DiscoverCopy` or
/// `DiscoverPresentation`, which is what makes A1 and A7 assertions over an enumerable set rather
/// than hopes about a view hierarchy. A model that built "2,984 sessions" itself would be a second
/// place numbers are made, and the honesty scan would be checking one of two.
@MainActor
@Observable
public final class DiscoverModel {
    /// The endpoint's cap. `/registry/search` takes `q` and `limit` and nothing else — no sort, no
    /// window, no offset — and caps `limit` at 60. 30 is F3's own default and is what the
    /// truncation disclosure (A8) is measured against.
    public static let searchLimit = 30

    @ObservationIgnored public let client: any ControlAPIClient
    @ObservationIgnored public let queue: any CapabilityQueueWriter

    /// The paired Mac's name, for the copy that names one. Nil renders as "your Mac".
    public var macName: String?
    /// Whether anything this phone sends will arrive. Supplied by the shell, which owns pairing.
    public var connection: ConnectionState

    public var query: String = ""
    public var window: RecencyWindow = .anyTime

    public private(set) var state: DiscoverListState = .loading
    public private(set) var entries: [RegistryEntry] = []
    /// Which entries are already in the local queue, which is what the commit's queued states key
    /// on. Loaded lazily per entry rather than by reading the whole queue on open: I3 owns the
    /// reader, and this feature should not grow a dependency on its storage format.
    public private(set) var queuedIDs: Set<String> = []
    /// A queue write that was refused, surfaced rather than swallowed.
    public private(set) var queueFailure: CapabilityQueueError?

    public init(
        client: any ControlAPIClient,
        queue: any CapabilityQueueWriter,
        connection: ConnectionState = .reachable,
        macName: String? = nil
    ) {
        self.client = client
        self.queue = queue
        self.connection = connection
        self.macName = macName
    }

    // MARK: - Searching

    /// Whether the user has narrowed the list.
    ///
    /// A10: an empty query shows the bands; a non-empty query shows one flat ranked list. Bands
    /// order the whole page and stop meaning anything once the user has narrowed it.
    public var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func search() async {
        state = .loading
        do {
            let response = try await client.searchRegistry(
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                limit: Self.searchLimit
            )
            entries = response.results
            state = Self.resolveState(
                response: response,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            entries = []
            // A27: `routerNotRunning` is its own state, tested for **before** any generic error
            // path. The phone reaches the registry through the paired Mac's router, so "not
            // running" is a different instruction from "something failed" — and rendering it as a
            // generic error banner is exactly what `SWIFT_PRACTICES.md` §3 forbids.
            if let reason = DiscoverFailureReason.from(error) {
                state = .failed(reason)
            } else {
                state = .offline
            }
        }
    }

    /// The one place a response becomes a surface state.
    ///
    /// Static and pure so the mapping is testable without a model, a client or a main actor.
    static func resolveState(
        response: RegistrySearchResponse,
        query: String
    ) -> DiscoverListState {
        let warnings = WarningClass.classify(response.warnings)
        if response.results.isEmpty {
            // A degraded search that returned nothing says *why* it returned nothing. Reporting
            // "neither index listed anything" when one of them never answered would be a false
            // statement about the registries.
            if !warnings.isEmpty { return .partial(warnings) }
            return query.isEmpty ? .emptyNoQuery : .emptyQuery(query)
        }
        return warnings.isEmpty ? .populated : .partial(warnings)
    }

    public func clearSearch() async {
        query = ""
        await search()
    }

    public func resetWindow() {
        window = .anyTime
    }

    // MARK: - Bands

    public func members(of band: DiscoverBand) -> [RegistryEntry] {
        DiscoverBands.members(of: band, in: entries, window: window)
    }

    public func isBandEmpty(_ band: DiscoverBand) -> Bool {
        DiscoverBands.isBandEmptyWithinResults(band, in: entries, window: window)
    }

    /// The truncation disclosure, when the results exactly fill the limit (A8).
    public var truncationText: String? {
        DiscoverPresentation.truncationText(shown: entries.count, limit: Self.searchLimit)
    }

    // MARK: - The commit

    /// The commit's state for one entry.
    ///
    /// Delegates to `CommitState.resolve`, which reads `ConnectionState.canQueue` rather than
    /// `canSend`. A19 exists because the obvious implementation reads `canSend` and silently ships
    /// I1's disable-when-unreachable behaviour while looking correct.
    public func commitState(for entry: RegistryEntry) -> CommitState {
        CommitState.resolve(
            connection: connection,
            hasInstallDescriptor: entry.install != nil,
            isAlreadyQueued: queuedIDs.contains(entry.id),
            isAlreadyDeclared: entry.installed == true
        )
    }

    /// Load whether this entry is already queued, so Detail opens in the right commit state.
    public func refreshQueuedState(for entry: RegistryEntry) async {
        do {
            if try await queue.contains(entry.id) {
                queuedIDs.insert(entry.id)
            } else {
                queuedIDs.remove(entry.id)
            }
        } catch let error as CapabilityQueueError {
            queueFailure = error
        } catch {
            queueFailure = .unreadable(error.localizedDescription)
        }
    }

    /// Queue one capability for review on the Mac.
    ///
    /// **This is the only write in the feature**, and it is local. There is no PATCH anywhere in
    /// I2, no install action, and nothing that could be read as installing — the phone queues for
    /// review on the Mac and never installs (`DESIGN.md` §9).
    ///
    /// A refused write leaves `queuedIDs` untouched and records the failure. I1's
    /// `PairingStorageFailureTests` is the precedent: there a `try?` made a refused Keychain write
    /// render as paired, and the same shape here would render an item as queued that is not.
    @discardableResult
    public func enqueue(_ entry: RegistryEntry) async -> Bool {
        queueFailure = nil
        do {
            try await queue.enqueue(QueuedCapability(entry: entry))
            queuedIDs.insert(entry.id)
            return true
        } catch let error as CapabilityQueueError {
            queueFailure = error
            return false
        } catch {
            queueFailure = .writeFailed(error.localizedDescription)
            return false
        }
    }

    // MARK: - Copy

    /// Resolve an entry's copy against this model's substitutions.
    public func copy(
        _ key: DiscoverCopy.Key,
        extra: [DiscoverCopy.Token: String] = [:]
    ) -> DiscoverCopy.Entry {
        var values: [DiscoverCopy.Token: String] = [.mac: macName ?? "your Mac"]
        values.merge(extra) { _, new in new }
        return DiscoverCopy.entry(key).resolved(values)
    }
}
