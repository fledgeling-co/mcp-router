#if os(macOS)
    import AppKit
    import Foundation
    import MCPRouterKit
    import Observation

    /// The Harnesses board's state, and its one read of the router.
    ///
    /// The four load shapes are `SkillsBoardModel`'s, for the reason recorded there: a board that
    /// has rows and then loses the router must neither throw the rows away nor hide the failure.
    /// It matters more here than anywhere else in the app, because these counts are read from files
    /// on a clock and **a stale reading is worse than no reading** — so `stale` keeps the last
    /// answer *and* the live error, and the row's own `readAt` says how old the answer is.
    @MainActor
    @Observable
    public final class HarnessesBoardModel {
        public enum LoadState: Sendable {
            case loading
            case loaded(HarnessesResponse)
            /// The last good reading, under a live failure.
            case stale(HarnessesResponse, ControlAPIError)
            case failed(ControlAPIError)

            public var response: HarnessesResponse? {
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

        /// The one sheet this board opens, and the one explanation it shows in place.
        ///
        /// `explainShim` is a case rather than a sheet with a fix in it, because there is no fix on
        /// this side: the transport belongs to the harness and this app does not write harness
        /// files. An explanation and a remedy are different affordances and collapsing them would
        /// offer an action that cannot work.
        public enum Sheet: Equatable, Sendable, Identifiable {
            case reconcile(harness: String)
            case explainShim(harness: String)

            public var id: String {
                switch self {
                case let .reconcile(harness): "reconcile:\(harness)"
                case let .explainShim(harness): "shim:\(harness)"
                }
            }
        }

        @ObservationIgnored public let client: any ControlAPIClient
        /// Reveals a path the **router** supplied. Not a second channel: nothing is read from disk
        /// and nothing is spoken to but the control API, which is the same argument
        /// `ServersBoardModel.forApp` records for `NSWorkspace.open`.
        @ObservationIgnored public let reveal: @MainActor (String) -> Void

        public private(set) var state: LoadState = .loading
        public var selection: String?
        public var sheet: Sheet?

        public init(
            client: any ControlAPIClient,
            reveal: @escaping @MainActor (String) -> Void = { _ in }
        ) {
            self.client = client
            self.reveal = reveal
        }

        /// One read. Called from `.task`, so it is cancelled with the view rather than outliving it.
        public func load() async {
            do {
                let response = try await client.harnesses()
                guard !Task.isCancelled else { return }
                state = .loaded(response)
            } catch {
                // A cancelled `.task` — the view went away — is not a router failure.
                guard !Task.isCancelled else { return }
                if let previous = state.response {
                    state = .stale(previous, error)
                } else {
                    state = .failed(error)
                }
            }
        }

        public var rows: [DetectedHarness] { state.response?.harnesses ?? [] }

        /// The finding above the list, when there is one.
        public var finding: String? { HarnessBoardCopy.finding(rows) }

        /// The rows whose configuration could not be read.
        ///
        /// Separated because an unreadable row is not a reading: every count on it is 0 and its
        /// state says `not-wired`, which is byte-identical to a clean unwired harness. Rendering
        /// them together would put six rows on the board of which one is a lie.
        public var unreadable: [DetectedHarness] { rows.filter { $0.unreadable != nil } }
        public var readable: [DetectedHarness] { rows.filter { $0.unreadable == nil } }

        public func selected() -> DetectedHarness? {
            guard let selection else { return nil }
            return rows.first { $0.id == selection }
        }

        /// `Esc` dismisses the sheet first, then clears the selection — never both at once.
        public func escape() {
            if sheet != nil {
                sheet = nil
            } else {
                selection = nil
            }
        }

        /// The model the running app uses, with the one system-facing closure it needs.
        public static func forApp(client: any ControlAPIClient) -> HarnessesBoardModel {
            HarnessesBoardModel(client: client, reveal: { path in
                // `selectFile` takes the path as a **string**, so nothing here builds a file URL
                // or asks the file manager anything — both of which A36 forbids under `Boards/`,
                // because reading a file is one of the ways past the control API. The spellings
                // are not written out because the gate that enforces them is a raw source grep,
                // and a comment quoting one is indistinguishable from a call.
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            })
        }
    }
#endif
