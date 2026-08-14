#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The inspector's lower half: what the server is configured as, what may be changed about it,
    /// what tools it declares, and the one destructive act.
    ///
    /// An extension purely for length — but the division it fell along is the meaningful one, since
    /// `configuration` is the read-only half and `behaviour` is the writable one.
    extension ServerInspector {
        /// Read-only, and labelled as such.
        var configuration: some View {
            section("Configuration") {
                row("Transport", server.transport.rawValue)
                if let command = server.command { row("Command", command) }
                if let args = server.args, !args.isEmpty {
                    // The argument array as an array. Subprocess arguments are never a shell string
                    // in this codebase (`SWIFT_PRACTICES.md` §6) and are not displayed as one either.
                    row("Arguments", args.joined(separator: " · "))
                }
                if let cwd = server.cwd { row("Working directory", cwd) }
                if let url = server.url { row("URL", url) }
                if let keys = server.envKeys, !keys.isEmpty {
                    // **Names only.** The control API never sends values and this surface never asks
                    // for them; `SWIFT_PRACTICES.md` §6 keeps secrets out of every log and screen.
                    row("Environment", "\(keys.count) set · \(keys.joined(separator: ", "))")
                }
                if let keys = server.headerKeys, !keys.isEmpty {
                    row("Headers", "\(keys.count) set · \(keys.joined(separator: ", "))")
                }
                if let hash = server.hash { row("Config hash", hash) }
                row("Indexed", relative(server.indexedAt))
                if let indexError = server.indexError {
                    row("Index error", indexError, tint: .fail)
                }
                Text(
                    """
                    MCP Router reads these from the config file the server is declared in, and never \
                    writes them there. Change them where you declared it.
                    """
                )
                .typeRole(.callout)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        var behaviour: some View {
            section("Behaviour") {
                ToggleRow(
                    title: "Keep warm",
                    help: "Skip the reaper. Costs resident memory to save a cold start.",
                    isOn: server.warm,
                    disabledReason: disabledReason
                ) { warm in
                    Task { await board.setWarm(server.name, to: warm) }
                }

                ToggleRow(
                    title: "Only load in named projects",
                    help: server.projects.isEmpty
                        ? "Every session sees its \(server.tools) tools."
                        : "Sessions outside these directories do not see its tools.",
                    isOn: !server.projects.isEmpty,
                    disabledReason: disabledReason
                ) { on in
                    if on {
                        // Turning this on needs a directory, and there is no honest default — a path
                        // invented here would scope the server somewhere the user never named.
                        guard let chosen = board.chooseDirectory() else { return }
                        Task { await board.setProjects(server.name, to: [chosen]) }
                    } else {
                        Task { await board.setProjects(server.name, to: []) }
                    }
                }

                ForEach(server.projects, id: \.self) { project in
                    HStack {
                        Text(project)
                            .typeRole(.callout, monospaced: true)
                            .foregroundStyle(ColorToken.t2.color)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: 0)
                        Button("Remove") {
                            Task {
                                await board.setProjects(
                                    server.name,
                                    to: server.projects.filter { $0 != project }
                                )
                            }
                        }
                        .buttonStyle(StandardButtonStyle(scale: .mini))
                        .disabled(disabledReason != nil)
                        .accessibilityHint(disabledReason ?? "")
                    }
                }
                if !server.projects.isEmpty {
                    Button("Add a project…") {
                        guard let chosen = board.chooseDirectory() else { return }
                        Task {
                            await board.setProjects(server.name, to: server.projects + [chosen])
                        }
                    }
                    .buttonStyle(StandardButtonStyle(scale: .small))
                    .disabled(disabledReason != nil)
                    .accessibilityHint(disabledReason ?? "")
                }

                if server.auth.supported, server.auth.authorized {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Signed in")
                                .typeRole(.body)
                                .foregroundStyle(ColorToken.t1.color)
                            Text(ServerInspector.signedInDetail(server.auth.authorizedAt))
                                .typeRole(.callout)
                                .foregroundStyle(ColorToken.t3.color)
                        }
                        Spacer(minLength: 0)
                        Button("Sign out") { Task { await board.signOut(server.name) } }
                            .buttonStyle(StandardButtonStyle(scale: .small))
                            .disabled(disabledReason != nil)
                            .accessibilityHint(disabledReason ?? "")
                    }
                }
            }
        }

        var tools: some View {
            section("Tools") {
                if server.toolNames.isEmpty {
                    Text(
                        server.indexError == nil
                            ? "The router has not indexed any tools on this server."
                            : "Its tools could not be read, so none are declared to your sessions."
                    )
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    FlowingTags(names: server.toolNames)
                    if server.tools > server.toolNames.count {
                        Text("+\(server.tools - server.toolNames.count) more")
                            .typeRole(.callout, monospaced: true)
                            .foregroundStyle(ColorToken.t4.color)
                    }
                }
            }
        }

        var danger: some View {
            section("Danger") {
                Button("Remove this server…") {
                    board.sheet = .removeServer(server: server.name)
                }
                // Destructive, and never the default (§3.4). It is a standard control rather than a
                // filled one; the view's single prominent action is `Add server…`.
                .buttonStyle(StandardButtonStyle(scale: .small))
                .foregroundStyle(ColorToken.fail.color)
            }
        }
    }
#endif
