#if os(macOS)
    import MCPRouterKit

    /// Every sentence the inspector says about whether a server is being served.
    ///
    /// A file of its own, and functions rather than literals at the call sites, for the reason
    /// M29's gap-fix found the hard way: a static that returns the right string proves nothing if
    /// the view stopped calling it, and there is no accessor for a SwiftUI label on this host. So
    /// the binding has to be asserted about the *source*, and the source has to have one place to
    /// read. `HeldChangeSheet.disableLabel` and `.disableReason` are the same shape one surface
    /// over.
    ///
    /// **The word is `disabled`, never `pause`.** M37's brief says *pause*; the state already has
    /// four shipped spellings of *disable* — the wire field, the row's `disabled by you`, the
    /// held-change sheet's `Disable <server>` and the tool-call refusal — and `DESIGN.md` §6 asks
    /// for one name per state taken from one source. `pause` is genuinely better at sounding
    /// temporary, and at not colliding with what this UI calls a dimmed control; `by you` already
    /// does the second job, and a fifth spelling is what the rule exists to prevent.
    extension ServerInspector {
        // MARK: - The switch

        /// Verb-first and naming the action (§6), in the same grammar as `Keep warm` beside it.
        static let disableToggleTitle = "Disable this server"

        /// The one quiet secondary sentence under the switch, which differs by direction.
        ///
        /// Both halves say what is *kept*, because that is the whole difference between this
        /// control and `Remove this server…` two sections below, and an operator deciding between
        /// them is deciding exactly that.
        static func disableToggleHelp(disabled: Bool) -> String {
            disabled
                ? """
                Its tools are withheld from every session. Its configuration, credentials and \
                approved tool list are kept.
                """
                : """
                Stop serving its tools. Its configuration, credentials and approved tool list are \
                kept, so switching it back on costs nothing.
                """
        }

        // MARK: - The three claims this control makes ordinary

        /// The header's second line.
        ///
        /// Withheld rather than zeroed on a disabled server, which is `ServerRowModel.tools`'
        /// ruling reaching the pane that row opens: the router still knows the count, so a number
        /// would claim a served capability and a `0` would claim the server has none.
        static func headerDetail(_ server: MCPServer) -> String {
            server.disabled
                ? "\(server.transport.rawValue) · tools withheld"
                : "\(server.transport.rawValue) · \(server.tools) tools"
        }

        /// The project-scope toggle's help, which states the precedence rather than a fact.
        ///
        /// `ToolUnion.isServed` tests `disabled` first and `visibleTo` second, and its own comment
        /// says that order is the message. Before this, the unscoped branch read *Every session
        /// sees its N tools* — which is simply false while the server is switched off, and was
        /// reachable then only through the held-change sheet. The switch above makes it ordinary.
        static func projectScopeHelp(_ server: MCPServer) -> String {
            if server.disabled {
                return "No session sees its tools while it is disabled, whatever this is set to."
            }
            return server.projects.isEmpty
                ? "Every session sees its \(server.tools) tools."
                : "Sessions outside these directories do not see its tools."
        }

        /// What the tool list says when none of what it lists is reaching anyone.
        ///
        /// The list itself stays: it is the one place an operator can read what a server declares
        /// before switching it back on, and withholding it would lose the inspection that spec-M29
        /// D4 keeps available at the router for the same reason.
        static func toolsNotServedNote(_ server: MCPServer) -> String? {
            server.disabled
                ? "None of these is being served while this server is disabled."
                : nil
        }
    }
#endif
