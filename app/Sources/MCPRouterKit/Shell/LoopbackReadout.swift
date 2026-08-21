import Foundation

/// The one place the loopback address the app talks to is spelled.
///
/// Two surfaces render it — Settings' `Endpoint` row and the sidebar's foot — and they must not be
/// able to disagree. Composed rather than duplicated: a second surface writing its own
/// `"127.0.0.1:\(port)"` is a second place for the host to be wrong, and a hard-coded port is the
/// honesty rule broken outward. `design/mocks/prototype.html` draws the foot as a literal
/// `127.0.0.1:8879`; the fixture router answers on 8971, so the literal is visibly wrong the moment
/// anything moves.
public enum LoopbackAddress {
    /// The router is loopback by construction — the Mac app talks to it over one loopback control
    /// API and nothing else, which is the standing constraint that lets the router be swapped
    /// underneath. The host is therefore a property of the product rather than an observation.
    public static let host = "127.0.0.1"

    /// `127.0.0.1:8971` — the compact form the sidebar's foot draws.
    public static func hostPort(_ port: Int) -> String {
        "\(host):\(port)"
    }

    /// `http://127.0.0.1:8971/mcp` — the form a client is pointed at, which is what Settings shows.
    public static func controlEndpoint(_ port: Int) -> String {
        "http://\(hostPort(port))/mcp"
    }
}

/// What the sidebar's foot line draws, decided here so the view holds no logic and a test can
/// drive every case.
///
/// **The foot says where the app is pointed. It does not say how the router is.** That split is the
/// whole design and it was settled against two out-of-family reviews (M27): the readout directly
/// above already renders the router's condition in `ControlAPIError`'s own words, and `DESIGN.md` §6
/// allows one wording per state taken from one source. A second line under it saying "answering" or
/// "not answering" would be that state spelled twice — and spelled wrongly for `.unauthorized`,
/// where the router answers 401 and the poll still fails.
public enum LoopbackFoot: Equatable, Sendable {
    /// No poll has answered yet, so there is no address to show. The foot holds its place as a
    /// skeleton at the line's own height, so the sidebar does not move when the first poll lands
    /// (`DESIGN.md` §5).
    case awaitingFirstAnswer

    /// The router answered here. Retained across a failed refresh for the same reason
    /// `TrackerState.port` is: a refresh that did not complete is not evidence the router moved.
    case address(String)

    /// Nothing has ever answered and no address was ever observed, so the foot draws nothing at
    /// all. The readout above is already carrying this state in the product's one approved wording.
    case absent

    /// The reading for one tracker state. `nil` is before the first publication, which is the same
    /// condition as `.loading`.
    public static func reading(for state: ServerStateTracker.TrackerState?) -> LoopbackFoot {
        guard let state else { return .awaitingFirstAnswer }
        if let port = state.port { return .address(LoopbackAddress.hostPort(port)) }
        return switch state.load {
        case .loading: .awaitingFirstAnswer
        // A poll that answered always carried a port, so these two arms are unreachable through
        // `ServersResponse`. They are written as `.absent` rather than as a fatal error because the
        // honest answer to "which address" with nothing observed is "none", in every case.
        case .loaded, .stale, .failed: .absent
        }
    }

    /// The address, when there is one.
    public var address: String? {
        guard case let .address(value) = self else { return nil }
        return value
    }
}

/// The foot's copy, held as data for the reason `ReadoutCopy` is: a clause about a string is only
/// checkable where the string is.
public enum LoopbackFootCopy {
    /// What a screen reader is told. A noun naming what the number is, then the number — the same
    /// rule A35 applies to the badges, and deliberately **no status word**: "answering" and "not
    /// answering" are a second name for a state `ControlAPIError` already owns.
    public static func accessibilityLabel(address: String) -> String {
        "Router endpoint, \(address)"
    }
}
