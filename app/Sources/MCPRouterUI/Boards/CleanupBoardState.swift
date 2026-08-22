#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// The Cleanup board's two state types: what condition the board is in, and what one successful
    /// read of the router actually contained.
    ///
    /// **Lifted out of `CleanupBoardModel` when M12 gave `Reading` a timestamp** and the class body
    /// crossed SwiftLint's limit. They belong together and they belong away from the load-and-write
    /// logic: `LoadState` decides which of `DESIGN.md` §5's states the board is showing, and
    /// `Reading` is the thing every figure on the board and in both of its destructive dialogs is
    /// read out of. Somebody checking whether a number on screen is one the router actually reported
    /// is reading this file.
    extension CleanupBoardModel {
        public enum LoadState: Sendable {
            case loading
            case loaded(Reading)
            case stale(Reading, ControlAPIError)
            case failed(ControlAPIError)

            public var reading: Reading? {
                switch self {
                case let .loaded(reading), let .stale(reading, _): reading
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

        public struct Reading: Sendable {
            /// When this reading was taken, from the model's own clock.
            ///
            /// **Stamped where the reading is constructed** — the instant `servers()` returns, before
            /// `skills()` and `usageSummary()` are attempted. Those two can only land later, so the
            /// age computed from this is never *younger* than the truth. That direction is the
            /// deliberate one: a staleness disclosure that errs has to err old, because the failure
            /// this field exists to prevent is a figure reading as fresher than it is.
            ///
            /// It has no default. A `Reading` that filled in "now" would be a reading that lies about
            /// its own age the moment a fixture constructs one, which is the whole defect M12 was
            /// filed for, rebuilt in the test seam that is supposed to catch it.
            ///
            /// `LoadState.stale` keeps the previous `Reading` whole, so this stays the moment that
            /// reading was taken and ages on screen as the clock moves. Nothing restamps it.
            public var observedAt: Date
            public var servers: [MCPServer]
            public var skills: SkillsResponse?
            /// `UsageSummary.since` — the type `usageSummary()` returns. Not `UsageResponse.since`,
            /// which belongs to the call log, and not `ServersResponse.since`.
            public var since: String?
            /// How many calls the router has recorded across the window, or **nil when it did not
            /// say**.
            ///
            /// Optional rather than zero-defaulted, and the difference is load-bearing. This figure
            /// appears in the reset dialog's consequence, which is the disclosure for an
            /// irreversible act with no restore endpoint. A zero substituted for an unanswered
            /// `usageSummary()` makes that dialog read "0 calls are discarded" — a number the router
            /// never reported, in the one direction that makes an irreversible action look free.
            public var recordedCalls: Int?
        }
    }
#endif
