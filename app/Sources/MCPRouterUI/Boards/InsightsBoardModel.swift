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
        /// A run or a settings change is in flight. Held so the control can dim itself rather than
        /// queue a second full corpus read behind the first.
        public internal(set) var analysing = false
        /// What the last analyst write refused with, or nil. Separate from ``LoadState``'s error
        /// because a failed *write* leaves the last good *reading* on screen.
        public internal(set) var analystError: ControlAPIError?

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

/// The analyst half of the board's state — F7.
///
/// In an extension rather than in the type above so the class body stays inside this repository's
/// length cap, and on a real seam: everything above is one read of the router, and everything here
/// is a **write followed by a re-read**.
public extension InsightsBoardModel {
    /// Whether the router on the other end has an analyst at all.
    ///
    /// This is what `Analyse now` is enabled by, and it is a fact the router stated rather than a
    /// build-time constant: `analyst` is null for the TypeScript reference and for any router that
    /// predates F7, and an object — with every reading absent — for one that has an analyst and has
    /// never run it.
    var analyst: AnalystRun? { state.response?.analyst }

    var canAnalyse: Bool { analyst != nil && !analysing }

    /// Run it, then draw what `GET /insights` says afterwards.
    ///
    /// **The board is never repainted from the write's own reply.** `runAnalyst()` posts and then
    /// re-reads, so what lands here came back down the read path — which is the difference between
    /// a control that changed something and a control that reported it did.
    func analyseNow() async {
        guard analyst != nil, !analysing else { return }
        analysing = true
        analystError = nil
        defer { analysing = false }
        do {
            state = try await .loaded(client.runAnalyst())
        } catch {
            record(error)
        }
    }

    /// Change one setting. The two the caller leaves nil are left alone by the router, which is
    /// what stops a menu press on `Runs` from also re-asserting a model the user did not touch.
    func choose(primary: String? = nil, fallback: String? = nil, cadence: String? = nil) async {
        guard analyst != nil, !analysing else { return }
        analysing = true
        analystError = nil
        defer { analysing = false }
        do {
            state = try await .loaded(client.setAnalyst(
                primary: primary, fallback: fallback, cadence: cadence
            ))
        } catch {
            record(error)
        }
    }

    /// The previous reading stays on screen and the failure is carried beside it: a board that
    /// blanked itself because a *write* failed would lose the counts the write never touched.
    private func record(_ error: ControlAPIError) {
        analystError = error
        if let previous = state.response { state = .stale(previous, error) }
    }
}
