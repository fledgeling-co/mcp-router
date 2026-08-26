//
//  What the harness can render, and the drawn state to render it in.
//
//  Split out of `main.swift` when that file passed 400 lines. These three enums are the harness's
//  vocabulary rather than its behaviour: every other file in this target names a surface, a state
//  or an appearance, and none of them changes what one *is*.
//
#if MEASURE && os(macOS)

    import MCPRouterKit
    import MCPRouterUI
    import SwiftUI

    /// A surface this tool knows how to render.
    enum Surface: String, CaseIterable {
        case servers
        case settings
        case readme
        /// The menu-bar popover (M20).
        /// Hosts in NSHostingView under .prohibited to measure without activating.
        case popover
        case harnesses
        case insights
    }

    /// The drawn state to render it in.
    enum State: String, CaseIterable {
        case ideal
        case empty
        case loading
        case error

        /// The scenario that produces this drawn state on this surface.
        func fixture(for surface: Surface) -> FixtureControlAPIClient.Scenario {
            switch (surface, self) {
            case (.settings, .empty): .offline
            // The Harnesses board's error frame in the mock is a configuration that would not
            // parse — which is a PARTIAL read, not a failed one: the other five harnesses were
            // read normally and are still drawn above the failure. `.offline` here would render
            // the router-not-running pane and report it as a measurement of the mock's frame.
            case (.harnesses, .error): .partial
            case (_, .ideal): .populated
            case (_, .empty): .empty
            case (_, .loading): .loading
            case (_, .error): .offline
            }
        }

        /// The inbox this state renders the popover against (nil for non-popover).
        func inbox(for surface: Surface) -> (any InboxService)? {
            guard surface == .popover else { return nil }
            switch self {
            case .ideal: return FixtureInboxService(.paired)
            case .empty: return FixtureInboxService(.pairedEmpty)
            case .loading: return FixtureInboxService(.loading)
            case .error: return FixtureInboxService(.failed)
            }
        }

        /// Whether to poll before rendering.
        ///
        /// `loading` deliberately does not: its fixture is a request that never returns, so awaiting
        /// it would hang the tool rather than render the placeholder. The board reads a nil tracker
        /// state as loading, which is the state this frame is for.
        var polls: Bool { self != .loading }
    }

    /// The appearance to resolve every dynamic colour in. Named rather than compared as a string so
    /// an unreadable value is refused by the same path every other argument is.
    enum Appearance: String, CaseIterable {
        case light
        case dark
    }

#endif
