#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The Insights board's state, and its one read of the router.
    ///
    /// The same four load shapes as every other board here. What is specific to this one is that
    /// **an answer with no history is a success, not an empty state of the load** — the router
    /// answered, it simply has nothing in the window — so `hasHistory` is read off the response
    /// rather than inferred from the absence of one.
    @MainActor
    @Observable
    public final class InsightsBoardModel {
        public enum LoadState: Sendable {
            case loading
            case loaded(InsightsResponse)
            case stale(InsightsResponse, ControlAPIError)
            case failed(ControlAPIError)

            public var response: InsightsResponse? {
                switch self {
                case let .loaded(response), let .stale(response, _): response
                case .loading, .failed: nil
                }
            }

            public var error: ControlAPIError? {
                switch self {
                case let .stale(_, error), let .failed(error): error
                case .loading, .loaded: nil
                }
            }
        }

        @ObservationIgnored public let client: any ControlAPIClient
        public private(set) var state: LoadState = .loading

        public init(client: any ControlAPIClient) {
            self.client = client
        }

        public func load() async {
            do {
                let response = try await client.insights()
                guard !Task.isCancelled else { return }
                state = .loaded(response)
            } catch {
                guard !Task.isCancelled else { return }
                if let previous = state.response {
                    state = .stale(previous, error)
                } else {
                    state = .failed(error)
                }
            }
        }

        /// Whether the window holds anything worth plotting. Read from the router's own horizon.
        public var hasHistory: Bool { state.response?.hasHistory ?? false }

        /// Bars in descending order, with the rows that carry **no** count last.
        ///
        /// A row with no count is not a small row — it is a row with nothing to compare — so it
        /// sorts out of the ranking rather than to the bottom of it, and the caption under the
        /// chart says which is which.
        public var harnessBars: [HarnessCallCount] {
            let rows = state.response?.callsByHarness ?? []
            let counted = rows.filter { $0.calls != nil }
                .sorted { ($0.calls ?? 0) > ($1.calls ?? 0) }
            return counted + rows.filter { $0.calls == nil }
        }

        /// The largest bar, which every other bar is drawn as a share of.
        ///
        /// One, not zero, when nothing has been called: a chart of zeros divided by zero is not a
        /// chart, and every bar drawing at zero width is the correct picture of that window.
        public var harnessScale: Int {
            max(1, harnessBars.compactMap(\.calls).max() ?? 0)
        }
    }
#endif
