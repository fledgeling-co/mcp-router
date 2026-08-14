#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// What the board is currently showing. One case per designed state.
    ///
    /// An enum rather than a set of booleans, so the view's `switch` cannot compile while ignoring
    /// one — the same reason `SurfaceState` is an enum.
    public enum ActivityCondition: Equatable, Sendable {
        case loading
        case empty
        case populated
        case filteredToNothing(total: Int)
        /// The history is showing and the live half is not arriving.
        case partial(FeedTrouble)
        /// The feed is delivering and the history is not — the mirror of `partial`.
        case historyUnavailable(ControlAPIError)
        case offline(ControlAPIError)
        case unauthorized(ControlAPIError)
        case error(ControlAPIError)

        /// Three ways the feed can be absent, and three different things to say.
        ///
        /// `reconnecting` is information and earns no button — the retry is already running.
        /// `dropped` and `neverConnected` both mean the ladder is spent, and they are separate cases
        /// because one implies a gap in a feed that was working and the other does not.
        public enum FeedTrouble: Equatable, Sendable {
            case reconnecting
            case dropped
            case neverConnected
        }
    }
#endif
