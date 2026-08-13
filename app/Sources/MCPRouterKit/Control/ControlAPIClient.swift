import Foundation

/// Everything that can go wrong talking to the router.
///
/// `routerNotRunning` is a distinct case rather than one more transport failure, because the
/// design treats it as a first-class state with its own surface: the router is loopback, so
/// "unreachable" does not mean the network is down or the service is degraded — it means the
/// daemon is not running on this machine, and the honest response is to say so and offer to start
/// it. A client that folds this into a generic connection error cannot render that state, and the
/// user gets "something went wrong" for a condition with one obvious fix.
public enum ControlAPIError: Error, Equatable, Sendable {
    /// Nothing is listening on the loopback control port.
    case routerNotRunning

    /// The control token was missing, wrong, or has been rotated.
    case unauthorized

    /// The router answered, but not with something this version understands.
    case malformedResponse(detail: String)

    /// The router answered with an error status and a message.
    case server(status: Int, message: String)

    /// The request did not complete.
    case transport(detail: String)

    /// Copy that states what happened and what to do about it, next to the thing that failed.
    /// Never blames the user and never emotes.
    public var userFacingDescription: String {
        switch self {
        case .routerNotRunning:
            "The router isn't running. Start it to see your servers."
        case .unauthorized:
            "This app isn't authorised to talk to the router. Re-pair it to continue."
        case let .malformedResponse(detail):
            "The router sent a response this version doesn't understand (\(detail))."
        case let .server(status, message):
            "The router couldn't complete that (\(status)): \(message)"
        case let .transport(detail):
            "Couldn't reach the router: \(detail)"
        }
    }
}

/// What the app is allowed to ask the router for.
///
/// A protocol with no implementation in this item: the live transport, the control token and its
/// Keychain storage, the streaming call log and the recorded-fixture double all belong to the
/// control-client item. Declaring the contract here is what lets both apps and the router's tests
/// compile against one definition while that work happens.
///
/// Note what is absent: there is no `update(server:command:)` or anything like it. The only
/// mutation shape is `ServerPatch`, which cannot carry a command line.
public protocol ControlAPIClient: Sendable {
    /// Every declared server and the router's own state.
    func servers() async throws(ControlAPIError) -> ServersResponse

    /// The recent call log.
    func usage() async throws(ControlAPIError) -> UsageResponse

    /// Change the settings a control API is permitted to change.
    func patch(server name: String, _ patch: ServerPatch) async throws(ControlAPIError) -> MCPServer
}
