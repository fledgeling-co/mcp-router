import Foundation

/// One row of the Servers board, resolved from a server without a host.
///
/// Split out of `ServerPresentation.swift` because that file outgrew the 400-line limit. The cut is
/// at the seam the MARK already drew: everything left there answers "what does this server say and
/// offer", and this answers "what does one row of the table hold".
/// One row of the board, fully resolved.
///
/// Identity is the server's **name**, never its index. This product's list reorders constantly as
/// servers start and stop, and index identity bleeds state between rows when it does
/// (`SWIFT_PRACTICES.md` §4).
public struct ServerRowModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let subtitle: ServerSubtitle
    /// What the Signal Path's jack and this row's plug both draw. **The same value in both**, so
    /// the band and the table cannot disagree about one server — which is the whole of the brief's
    /// *"one selection, three representations"* applied to state rather than to selection.
    public let jack: JackState
    /// The jack's word, in full and contracted. Carried on the row model rather than derived in the
    /// band, so the two surfaces read one computation of one server's condition.
    public let condition: JackCondition
    public let transport: String
    /// How many tools this server is serving, or `nil` when it is serving none by the user's own
    /// decision and the figure is therefore withheld rather than reported as zero.
    ///
    /// The design of record draws this cell as an em-dash on the disabled row (`2069`) while the
    /// row two above it — an unauthorised server with no working tools at all — reads `2`. So the
    /// em-dash is not a zero, and it cannot be: the router still knows the count, because disabling
    /// leaves the manifest row intact. A number would claim a served capability and a `0` would
    /// claim the server has no tools. An absent value claims neither, and that is the only honest
    /// reading of the three.
    public let tools: Int?
    /// How many tools the router has cached for this server, whether or not it is serving them.
    ///
    /// **A different question from `tools` above, which is why it is a different field.** `tools`
    /// answers *what is this server serving*, and is withheld when the answer is "nothing, because
    /// you switched it off". This answers *what does the router hold for it*, and disabling does not
    /// change that by design — the manifest row, the digest and the approved surface all survive.
    ///
    /// The board's footer reads this one, because its sentence is `… tools indexed`. That word was
    /// chosen deliberately over an earlier `tools in every session's tool list`, which scoping had
    /// already made false; dropping a disabled server's tools out of an *indexed* count would make
    /// it false again in the other direction.
    public let indexedTools: Int
    /// Lifetime calls from the usage log — **not** `callsServed`, which is the current child
    /// process's own counter and resets to zero every time the reaper closes it. A column that
    /// dropped to zero whenever a server went idle would read as "this has never been used".
    public let calls: Int
    public let errors: Int
    public let lastUsed: Date?
    public let action: ServerRowAction?

    public init(server: MCPServer, idleMs: Int?, pendingAuth: PendingAuth?) {
        id = server.name
        name = server.name
        subtitle = ServerSubtitle.forServer(server, idleMs: idleMs)
        jack = JackState.forServer(server)
        condition = JackCondition.forServer(server, idleMs: idleMs)
        transport = server.transport.rawValue
        tools = server.disabled ? nil : server.tools
        indexedTools = server.tools
        calls = server.usage.calls
        errors = server.usage.errors
        lastUsed = server.usage.lastUsed?.asControlAPIDate
        action = ServerRowAction.forServer(server, pendingAuth: pendingAuth)
    }
}
