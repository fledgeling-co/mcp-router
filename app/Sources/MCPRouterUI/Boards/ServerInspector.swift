#if os(macOS)
    import AppKit
    import MCPRouterKit
    import SwiftUI

    /// One server, in full.
    ///
    /// The brief asks this to carry the full config, the per-project scoping list, the tool
    /// inventory and the route into the held-description diff. The division that matters runs
    /// through the middle of it: **Configuration is read-only and Behaviour is not**, and that is
    /// not a styling choice. `ServerPatch` — the only shape this app may PATCH — structurally cannot
    /// carry `command`, `args` or `env`, because a control API that can rewrite a command line can
    /// run anything on the machine. Showing the command line while offering no way to edit it is
    /// that guarantee made visible rather than merely enforced.
    struct ServerInspector: View {
        let server: MCPServer
        @Bindable var board: ServersBoardModel
        let canWrite: Bool
        /// Passed in rather than held on the model, for the same reason the servers are: the board
        /// keeps no copy of what the router said.
        let pendingAuth: PendingAuth?

        var isWriting: Bool { board.writesInFlight.contains(server.name) }

        /// Why the Behaviour controls are dimmed, or nil when they are live. §3.4 requires a
        /// disabled control to dim in place with a discoverable reason and forbids hiding it.
        var disabledReason: String? {
            if isWriting { return ServersBoardModel.applyingReason }
            if !canWrite { return ServersBoardModel.cannotWriteReason }
            return nil
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: ServersBoardMetrics.sectionGap) {
                    header
                    banners
                    rightNow
                    use
                    configuration
                    behaviour
                    tools
                    danger
                }
                .padding(ServersBoardMetrics.panePadding)
            }
            .frame(width: ServersBoardMetrics.inspectorWidth)
            .background(ColorToken.panel.color)
            .accessibilityLabel("\(server.name) details")
        }

        // MARK: - Header

        private var header: some View {
            HStack(alignment: .top, spacing: ServersBoardMetrics.gap) {
                Breaker(state: BreakerState.forServer(server))
                VStack(alignment: .leading, spacing: 0) {
                    // The full name, wrapping rather than truncating: §5's Overflow rule sends the
                    // long value here precisely so it can be read somewhere.
                    Text(server.name)
                        .typeRole(.title3)
                        .foregroundStyle(ColorToken.t1.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(server.transport.rawValue) · \(server.tools) tools")
                        .typeRole(.callout, monospaced: true)
                        .foregroundStyle(ColorToken.t3.color)
                }
                Spacer(minLength: 0)
                Button("Close") { board.selection = nil }
                    .buttonStyle(StandardButtonStyle(scale: .small))
            }
        }

        // MARK: - Banners

        @ViewBuilder
        private var banners: some View {
            if let placard = server.placard {
                Banner(icon: .warn, tint: .fail) {
                    VStack(alignment: .leading, spacing: ServersBoardMetrics.gap) {
                        Text(
                            """
                            Tripped. \(placard.reason). It will not re-arm on its own — that is \
                            deliberate, because a server that fails and silently retries hides the \
                            failure.
                            """
                        )
                        if let substitute = placard.substitute {
                            Text("\(substitute) is standing in meanwhile.")
                        }
                        if let until = placard.until {
                            Text("Held until \(until).")
                        }
                        Button(ServerRowAction.reset(.clearPlacard).label) {
                            Task { await board.reset(server) }
                        }
                        .buttonStyle(StandardButtonStyle(scale: .small))
                        .disabled(disabledReason != nil)
                        .accessibilityHint(disabledReason ?? "")
                    }
                }
            }
            if let pending = server.pendingChange {
                let noun = pending.count == 1 ? "tool description" : "tool descriptions"
                Banner(icon: .shield, tint: .attention) {
                    VStack(alignment: .leading, spacing: ServersBoardMetrics.gap) {
                        Text(
                            """
                            \(pending.count) \(noun) held. The approved text is still what your \
                            sessions see.
                            """
                        )
                        Button("Review the change") {
                            board.sheet = .heldChange(server: server.name)
                            Task { await board.loadHeldChanges(server.name) }
                        }
                        .buttonStyle(StandardButtonStyle(scale: .small))
                    }
                }
            }
            if server.auth.supported, !server.auth.authorized {
                Banner(icon: .shield, tint: .attention) {
                    VStack(alignment: .leading, spacing: ServersBoardMetrics.gap) {
                        Text(
                            """
                            This server hasn't been authorised yet. Its tools are declared, and \
                            calls to them are refused until you sign in.
                            """
                        )
                        if let action = ServerRowAction.forServer(server, pendingAuth: pendingAuth) {
                            if case .reopenAuthorizationPage = action {
                                Text("A browser page is already open for this.")
                                    .typeRole(.callout)
                                    .foregroundStyle(ColorToken.t3.color)
                            }
                            Button(action.label) {
                                Task { await board.perform(action, on: server) }
                            }
                            .buttonStyle(StandardButtonStyle(scale: .small))
                            // `disabledReason`, not `isWriting`. This read `.disabled(isWriting)`
                            // and so stayed live on a stale load — a POST offered beside a Keep-warm
                            // toggle dimming for that same condition, one section above. The reason
                            // machinery already existed here; this control was the one that skipped
                            // it.
                            .disabled(disabledReason != nil)
                            .help(disabledReason ?? "")
                            .accessibilityHint(disabledReason ?? "")
                        }
                    }
                }
            }
            if let error = board.rowErrors[server.name] {
                // The error sits next to the thing that failed (§5), carries the router's own hint
                // where it sent one, and is never swallowed to keep the panel tidy.
                Banner(icon: .bang, tint: .fail) {
                    Text("\(error.headline). \(error.advice)")
                }
            }
        }

        // MARK: - Sections

        private var rightNow: some View {
            section("Right now") {
                row("State", server.state.rawValue)
                row("In flight", "\(server.inFlight)")
                // `callsServed` is the **current child process's** counter and resets every time the
                // reaper closes it, which is a different number from the lifetime total below. Two
                // numbers under one label would be the surface lying quietly, so they are labelled
                // apart.
                row("Calls by this process", "\(server.callsServed)")
                row("Idle for", "\(server.idleSec)s")
            }
        }

        private var use: some View {
            section("Use") {
                row("Calls", "\(server.usage.calls)")
                row("Failed", "\(server.usage.errors)")
                row("First seen", relative(server.usage.firstSeen))
                row("Last used", relative(server.usage.lastUsed))
            }
        }

        // MARK: - Bits

        func row(_ label: String, _ value: String, tint: ColorToken = .t2) -> some View {
            HStack(alignment: .top) {
                Text(label)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
                Spacer(minLength: ServersBoardMetrics.gap)
                Text(value)
                    .typeRole(.callout, monospaced: true)
                    .foregroundStyle(tint.color)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        /// A timestamp as the column shows it, or the word for its absence.
        ///
        /// "Never" rather than a blank or a zero date: `DESIGN.md` §6 asks for one name per state,
        /// and the board's last-used column already uses that word.
        func relative(_ timestamp: String?) -> String {
            guard let date = timestamp?.asControlAPIDate else { return "Never" }
            return shortAgo(date)
        }

        /// What the Signed in row says under it, which depends on whether the router gave a usable
        /// timestamp — not merely on whether it gave one.
        ///
        /// **The bug this replaces rendered `Authorised Never.`** The call site was
        /// `authorizedAt.map { "Authorised \(relative($0))." }`, and `relative` answers `Never` when
        /// a string will not parse as a date. `Never` is the right word at the three call sites that
        /// pass an **optional** — `Indexed`, `First seen`, `Last used` all mean it literally — but
        /// here the value is already non-nil, so `Never` could only ever mean "the router sent
        /// something I could not read", which is not a fact about the user's credentials.
        ///
        /// So an unparseable timestamp falls back to the same sentence an absent one does. The
        /// server *is* authorised — that is `auth.authorized`, observed, and the branch this is
        /// inside — and only the *when* is unknown. Exactly the discipline applied to the reap
        /// horizon: drop the figure, keep the fact, invent nothing.
        ///
        /// `static` and taking the raw string so it is testable without a view host.
        static func signedInDetail(_ authorizedAt: String?) -> String {
            guard let date = authorizedAt?.asControlAPIDate else {
                return "Credentials are stored for this server."
            }
            return "Authorised \(shortAgo(date))."
        }

        func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: ServersBoardMetrics.gap) {
                // §3.2: section headers are sentence case, system font, secondary colour. Tracked
                // uppercase is the loudest web tell, and the fix is to remove it rather than re-track.
                Text(title)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                content()
            }
        }
    }

#endif
