#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Routes the board's one open sheet to the view that draws it.
    struct ServerSheetHost: View {
        @Bindable var shell: ShellModel
        @Bindable var board: ServersBoardModel
        let sheet: RouterSheet.Servers

        private var servers: [MCPServer] { shell.trackerState?.servers ?? [] }

        var body: some View {
            switch sheet {
            case .addServer:
                AddServerSheet(board: board)
            case let .heldChange(name):
                HeldChangeSheet(board: board, serverName: name)
            case let .removeServer(name):
                if let server = servers.first(where: { $0.name == name }) {
                    RemoveServerDialog(board: board, server: server)
                } else {
                    // The server went away while the dialog was open — a poll can do that. Saying so
                    // is better than a dialog offering to remove something that is already gone.
                    SheetFrame(title: "\(name) is no longer declared") {
                        Text("It was removed while this was open, so there is nothing left to do.")
                            .typeRole(.body)
                            .foregroundStyle(ColorToken.t2.color)
                    } actions: {
                        Button("Close") { board.sheet = nil }
                            .buttonStyle(ProminentButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Add

    /// `⌘N`.
    ///
    /// The lede is the honest part and is kept from the prototype deliberately: most people never
    /// need this sheet, because the router adopts what is already in their config. Telling them so
    /// costs one sentence and saves them a workflow they did not need.
    struct AddServerSheet: View {
        @Bindable var board: ServersBoardModel
        @State private var fragment = ""
        @State private var name = ""

        var body: some View {
            SheetFrame(title: "Add an MCP server") {
                VStack(alignment: .leading, spacing: ServersBoardMetrics.gap) {
                    Text(
                        """
                        You don't normally need this. Add it to your agent's config exactly as you \
                        always have and the router adopts it within a second — indexing it first, \
                        so a typo'd command stays visible where you typed it.
                        """
                    )
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)

                    LabelledField(label: "Name", text: $name, placeholder: "my-server")
                    LabelledField(
                        label: "Command", text: $fragment,
                        placeholder: "npx -y @me/my-mcp"
                    )

                    Text(
                        """
                        It is spawned once to enumerate its tools, then stopped. Nothing is written \
                        to your config until that succeeds.
                        """
                    )
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)

                    if let failure = board.addFailure {
                        // The router's own hint is what turns a dead end into a next step, so it is
                        // shown rather than reduced to a status code.
                        Banner(icon: .bang, tint: .fail) {
                            Text("\(failure.headline). \(failure.advice)")
                        }
                    }
                }
            } actions: {
                // Cancel leads; the prominent action is trailing (§3.4).
                Button("Cancel") { board.sheet = nil }
                    .buttonStyle(StandardButtonStyle())
                if board.addCanForce {
                    Button("Add it anyway") { Task { await submit(force: true) } }
                        .buttonStyle(StandardButtonStyle())
                }
                Button("Index and add") { Task { await submit(force: false) } }
                    .buttonStyle(ProminentButtonStyle())
                    .disabled(addReason != nil)
                    .help(addReason ?? "")
                    .accessibilityHint(addReason ?? "")
            }
        }

        /// Why `Index and add` is dimmed, or `nil` when it is live.
        ///
        /// §3.4: a dimmed control owes a reason. It dimmed with nothing said, so the only way to
        /// learn what was missing was to guess which of the two fields mattered.
        private var addReason: String? {
            switch (name.isEmpty, fragment.isEmpty) {
            case (true, true): "Give the server a name and a command."
            case (true, false): "Give the server a name."
            case (false, true): "Give the server a command to run."
            case (false, false): nil
            }
        }

        /// Splits the typed command on whitespace into the executable and its argument array.
        ///
        /// An argument array, never a shell string: `SWIFT_PRACTICES.md` §6 requires subprocess
        /// arguments to be passed as an array, and the router spawns exactly what is sent here.
        private func submit(force: Bool) async {
            let parts = fragment.split(separator: " ").map(String.init)
            guard let command = parts.first else { return }
            await board.add(
                NewServer(name: name, command: command, args: Array(parts.dropFirst())),
                force: force
            )
        }
    }

    // MARK: - The held tool description

    /// The quarantine surface, and the reason the router indexes before it serves.
    struct HeldChangeSheet: View {
        @Bindable var board: ServersBoardModel
        let serverName: String

        /// Why `Accept the new text` is dimmed, or `nil` when it is live.
        ///
        /// Loading, failed and empty are three different situations and the old
        /// `.disabled(board.heldChanges?.changes.isEmpty ?? true)` said none of them — so during the
        /// sheet's own load the user saw a dead prominent button and no explanation at all.
        private var acceptReason: String? {
            if board.isLoadingHeldChanges { return "Reading the held descriptions…" }
            if board.heldChangesError != nil { return "The held descriptions could not be read." }
            if board.heldChanges?.changes.isEmpty ?? true { return "There is nothing held to accept." }
            return nil
        }

        var body: some View {
            SheetFrame(title: "\(serverName) rewrote a tool description") {
                VStack(alignment: .leading, spacing: ServersBoardMetrics.gap) {
                    Text("The approved text is still what your sessions see. Nothing changed for them.")
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)

                    // A second request, which fails on its own and says so rather than showing an
                    // empty diff that reads as "nothing changed".
                    if board.isLoadingHeldChanges {
                        Text("Reading what changed…")
                            .typeRole(.callout)
                            .foregroundStyle(ColorToken.t3.color)
                    } else if let error = board.heldChangesError {
                        Banner(icon: .bang, tint: .fail) {
                            Text("\(error.headline). \(error.advice)")
                        }
                    } else if let changes = board.heldChanges {
                        if changes.changes.isEmpty {
                            Text("The router is no longer holding a change for this server.")
                                .typeRole(.body)
                                .foregroundStyle(ColorToken.t2.color)
                        }
                        ForEach(changes.changes) { change in
                            ToolChangeCard(change: change)
                        }
                    }
                }
            } actions: {
                Button("Remove \(serverName)", role: .destructive) {
                    board.request(.removeInstalledCapability, subject: serverName)
                }
                .buttonStyle(StandardButtonStyle())

                // Cancel leads, and its label says what it actually does: closing this sheet sends
                // no request, because the router is already serving the approved text and the change
                // simply stays held. A label implying a write would be describing an action that
                // does not happen.
                Button("Keep serving the old text") { board.sheet = nil }
                    .buttonStyle(StandardButtonStyle())

                Button("Accept the new text") {
                    Task { await board.approveHeldChange(serverName) }
                }
                .buttonStyle(ProminentButtonStyle())
                .disabled(acceptReason != nil)
                .help(acceptReason ?? "")
                .accessibilityHint(acceptReason ?? "")
            }
        }
    }

    // MARK: - Remove

    /// A named-consequence dialog, and a deliberate departure from `DESIGN.md` §8's "undoable, never
    /// confirmed".
    ///
    /// The measurement behind it: `DELETE /servers/:name` calls `editConfigFile` and **removes the
    /// entry from the user's config file**, then clears its stored credentials. This app can read
    /// `envKeys` and `headerKeys` — the key *names* — and never the values, because the control API
    /// does not send them, and the control API is the only channel this app is permitted to use. So
    /// an undo built on `add(NewServer)` would restore a server with its secrets missing: a row that
    /// looks recovered and does not work.
    ///
    /// §9's own escape clause is what licenses this: "Friction scales to blast radius only for
    /// genuinely destructive acts, and then as a named-consequence dialog that is never the default
    /// button." Deleting an entry from a user's config file, including values this app cannot read
    /// back, is that act — and the consequence is named rather than gestured at.
    struct RemoveServerDialog: View {
        @Bindable var board: ServersBoardModel
        let server: MCPServer
        @State private var keepHistory = true

        var body: some View {
            SheetFrame(title: "Remove \(server.name)?") {
                VStack(alignment: .leading, spacing: ServersBoardMetrics.gap) {
                    Text(
                        """
                        This deletes its entry from the config file it is declared in. \
                        \(ServersBoardModel.removeToolsConsequence(
                            tools: server.tools,
                            isScoped: !server.projects.isEmpty
                        ))
                        """
                    )
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)

                    Banner(icon: .warn, tint: .attention) {
                        Text(
                            ServersBoardModel.removeConsequence(
                                envKeys: server.envKeys,
                                headerKeys: server.headerKeys
                            )
                        )
                    }

                    Toggle("Keep its call history", isOn: $keepHistory)
                        .toggleStyle(.checkbox)
                    Text(
                        keepHistory
                            ? "Its calls stay in Activity, so the record of what it did survives."
                            : "Its recorded calls are forgotten along with it."
                    )
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } actions: {
                // Cancel leads and takes Escape; the destructive action takes no key at all (§3.4).
                //
                // **This is `RemoveServerSheet`'s row, and it is here because the two must not
                // disagree.** M18's whole reason for touching the shortcuts on that sheet was that
                // this dialog and that sheet gave two answers to "what does a key do here"; fixing
                // only the sheet would have left the pair disagreeing in the other direction.
                // Escape had no path on this dialog before — one of the sheets the M18 verdict
                // lists as having none — and Return dismissed it. Now Escape dismisses and nothing
                // is the default, which is the reasoning `Boards/CleanupSheets.swift` carries in
                // full. (That verdict's list is nine of fifteen rather than the eight of fourteen
                // it states; `SheetShortcutGuardTests` carries the correction and the population.)
                //
                // Cancel is drawn plain for the same reason, and that half predates M18: `589ab2e`
                // filled it in M3. §3.4 puts the accent fill on a *trailing* affirmative and Cancel
                // leads, so on a confirmation whose only affirmative act is destructive nothing
                // takes the fill. `SheetShortcutGuardTests.noCancelControlIsAccentFilled` holds it.
                Button("Cancel") { board.sheet = nil }
                    .buttonStyle(StandardButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button("Remove", role: .destructive) {
                    Task { await board.remove(server.name, keepHistory: keepHistory) }
                }
                .buttonStyle(StandardButtonStyle())
            }
        }
    }

    // MARK: - Shared sheet furniture

    struct SheetFrame<Body: View, Actions: View>: View {
        let title: String
        @ViewBuilder let content: Body
        @ViewBuilder let actions: Actions

        var body: some View {
            VStack(alignment: .leading, spacing: ServersBoardMetrics.sectionGap) {
                Text(title)
                    .typeRole(.title2)
                    .foregroundStyle(ColorToken.t1.color)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView { content.frame(maxWidth: .infinity, alignment: .leading) }
                HStack(spacing: ServersBoardMetrics.gap) {
                    Spacer(minLength: 0)
                    actions
                }
            }
            .padding(ServersBoardMetrics.panePadding)
            .frame(
                width: ServersBoardMetrics.sheetWidth,
                // A ceiling rather than a fixed height, so a one-line dialog is not a tall empty box
                // and a long diff still scrolls inside its own frame.
                height: ServersBoardMetrics.sheetHeight
            )
            .background(ColorToken.panel.color)
        }
    }

    struct LabelledField: View {
        let label: String
        @Binding var text: String
        let placeholder: String

        var body: some View {
            VStack(alignment: .leading, spacing: ServersBoardMetrics.tightGap) {
                Text(label)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .typeRole(.body, monospaced: true)
                    .foregroundStyle(ColorToken.t1.color)
                    .padding(.horizontal, ServersBoardMetrics.rowPadding)
                    .frame(height: MetricToken.controlLarge.leadingScalar)
                    .background(
                        RoundedRectangle(
                            cornerRadius: MetricToken.selectionRadius.leadingScalar,
                            style: .continuous
                        )
                        .fill(ColorToken.raised.color)
                    )
            }
        }
    }
#endif
