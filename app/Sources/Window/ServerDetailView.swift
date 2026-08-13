import SwiftUI

/// The inspector for one server: what it is, what it can do, and the four things the
/// router lets you change about it.
struct ServerDetailView: View {
    @Environment(RouterStore.self) private var store
    let server: MCPServer

    @State private var changes: ChangesResponse?
    @State private var confirmingRemove = false
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identity

                if server.pendingChange != nil { quarantine }
                if let e = server.indexError { indexFailure(e) }
                if server.auth.supported { authorization }

                scoping
                warmth
                tools
                remove
            }
            .padding(16)
        }
        .task(id: server.pendingChange?.seenAt) {
            guard server.pendingChange != nil else { changes = nil; return }
            changes = await store.changes(server.name)
        }
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                StateDot(server: server)
                Text(server.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    busy = true
                    Task { _ = await store.reindex(server.name); busy = false }
                } label: {
                    if busy { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless)
                .help("Start it once, re-read its tool list, stop it again")
            }

            // The command is shown, never edited. The router refuses to accept a new
            // command line through this API, and that refusal is the point: an API that can
            // rewrite a command is an API that can run anything.
            if let cmd = server.command {
                Field("Command") {
                    Text(([cmd] + (server.args ?? [])).joined(separator: " "))
                        .font(Theme.Font.rowMono)
                        .textSelection(.enabled)
                }
            }
            if let url = server.url {
                Field("URL") {
                    Text(url).font(Theme.Font.rowMono).textSelection(.enabled)
                }
            }
            // Names only. The router never sends values, and this view never asks for them.
            if let keys = server.envKeys, !keys.isEmpty {
                Field("Environment") { KeyChips(keys: keys) }
            }
            if let keys = server.headerKeys, !keys.isEmpty {
                Field("Headers") { KeyChips(keys: keys) }
            }

            HStack(spacing: 14) {
                Stat("Tools", "\(server.tools)")
                Stat("Calls", "\(server.usage.calls)")
                if server.usage.errors > 0 { Stat("Errors", "\(server.usage.errors)", tint: Theme.failed) }
                Stat("Last used", server.usage.lastUsed == nil ? "Never" : shortAgo(iso: server.usage.lastUsed))
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Schema quarantine

    private var quarantine: some View {
        Card(tint: Theme.attention) {
            VStack(alignment: .leading, spacing: 9) {
                Label("Tool descriptions changed", systemImage: "shield.lefthalf.filled")
                    .font(Theme.Font.row.weight(.semibold))

                // Why this is held rather than shown as a notice: a tool description is
                // read by a model as instruction, and the router answers tools/list from
                // disk with nothing running. A server that ships benignly then rewrites a
                // description changes nothing a health check can see.
                Text("Your sessions are still being served the descriptions you already approved. Nothing here has reached a model.")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)

                if let changes {
                    ForEach(changes.changes) { c in ChangeRow(change: c) }
                } else {
                    ProgressView().controlSize(.small)
                }

                HStack {
                    Button("Approve") { Task { _ = await store.approve(server.name) } }
                        .controlSize(.small)
                    Button("Remove server", role: .destructive) { confirmingRemove = true }
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    private func indexFailure(_ message: String) -> some View {
        Card(tint: Theme.failed) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Couldn't start", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.row.weight(.semibold))
                Text(message)
                    .font(Theme.Font.rowMono)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                // The tools stay on the list rather than disappearing, and this explains
                // why: a tool that answers "inoperative, use X" reroutes an agent on the
                // first attempt, where a tool that vanished makes it improvise.
                Text("Its tools stay listed and answer with this reason, so a session reroutes instead of improvising around a capability that silently vanished.")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Auth

    private var authorization: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Authorization", systemImage: server.auth.authorized ? "checkmark.seal.fill" : "key")
                        .font(Theme.Font.row.weight(.semibold))
                        .foregroundStyle(server.auth.authorized ? Theme.ok : Theme.attention)
                    Spacer()
                }
                if server.auth.authorized {
                    Text("Authorized \(shortAgo(iso: server.auth.authorizedAt)) ago. Tokens live in the router's own directory at 0600, never in this app.")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                    Button("Sign out") { Task { _ = await store.clearAuth(server.name) } }
                        .controlSize(.small)
                } else {
                    Text("This server asked for OAuth. Authorizing opens your browser; the router holds the callback and the tokens.")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                    Button("Authorize in browser") { Task { _ = await store.authorize(server.name) } }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Project scoping

    private var scoping: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Projects", systemImage: "folder")
                    .font(Theme.Font.row.weight(.semibold))

                if server.projects.isEmpty {
                    Text("Available everywhere.")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(server.projects, id: \.self) { p in
                        HStack(spacing: 6) {
                            Text((p as NSString).lastPathComponent)
                                .font(Theme.Font.rowMono)
                            Spacer()
                            Button {
                                Task { _ = await store.setProjects(server.name, server.projects.filter { $0 != p }) }
                            } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.tertiary)
                        }
                        .help(p)
                    }
                }

                // Scoping is the one control here that changes what a model can see. A
                // session outside the listed directories is not told this server exists,
                // so its tools cost nothing in that session's context.
                Text("A session outside these directories isn't offered this server's tools at all.")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.tertiary)

                HStack {
                    Button("Add directory…") { pickDirectory() }
                        .controlSize(.small)
                    if !server.projects.isEmpty {
                        Button("Everywhere") { Task { _ = await store.setProjects(server.name, []) } }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scope"
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.map(\.path)
        Task { _ = await store.setProjects(server.name, Array(Set(server.projects + added)).sorted()) }
    }

    // MARK: - Warm

    private var warmth: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: .init(
                    get: { server.warm },
                    set: { v in Task { _ = await store.setWarm(server.name, v) } }
                )) {
                    Label("Keep warm", systemImage: "flame")
                        .font(Theme.Font.row.weight(.semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Text(server.warm
                     ? "Started with the router and never reaped. Trades resident memory for the cold start."
                     : "Starts on the first call and is reaped when idle. Cold calls on this server are marked in the log.")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tools

    private var tools: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(server.toolNames, id: \.self) { t in
                    Text(t)
                        .font(Theme.Font.rowMono)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 5)
        } label: {
            Text("\(server.tools) tool\(server.tools == 1 ? "" : "s")")
                .font(Theme.Font.row.weight(.medium))
        }
    }

    // MARK: - Remove

    private var remove: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Button("Remove \(server.name)", role: .destructive) { confirmingRemove = true }
                .controlSize(.small)
        }
        .confirmationDialog("Remove \(server.name)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { _ = await store.remove(server.name) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes it from the router's config, along with its cached tools, any stored tokens, and its call history. Sessions stop being offered its tools on their next tool list.")
        }
    }
}

// MARK: - Small pieces

private struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Theme.Font.sectionLabel)
                .foregroundStyle(.tertiary)
                .kerning(0.4)
            content
        }
    }
}

private struct KeyChips: View {
    let keys: [String]
    var body: some View {
        // Names, never values. The router sends key names only; showing a secret in a
        // window that can be screen-shared would undo that on this side of the wire.
        FlowRow(spacing: 4) {
            ForEach(keys, id: \.self) { k in
                Text(k)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .help("Names only — the router never sends values, and this app never asks for them.")
    }
}

private struct Stat: View {
    let label: String, value: String
    var tint: Color = .primary
    init(_ label: String, _ value: String, tint: Color = .primary) {
        self.label = label; self.value = value; self.tint = tint
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Theme.Font.row.weight(.medium)).foregroundStyle(tint)
            Text(label).font(Theme.Font.secondary).foregroundStyle(.tertiary)
        }
    }
}

private struct Card<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background((tint ?? Color.primary).opacity(tint == nil ? 0.04 : 0.08),
                        in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct ChangeRow: View {
    let change: ToolChange
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(change.kind.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(change.name).font(Theme.Font.rowMono.weight(.medium))
            }
            // Invisible codepoints get named rather than rendered, because rendering them
            // shows nothing — which is exactly why they are worth using against a reader.
            if let inv = change.invisible, !inv.isEmpty {
                Label(inv.joined(separator: " "), systemImage: "eye.slash")
                    .font(Theme.Font.secondary.monospaced())
                    .foregroundStyle(Theme.failed)
            }
            if let before = change.before?.description {
                Text(before).font(Theme.Font.secondary).foregroundStyle(.secondary).strikethrough()
            }
            if let after = change.after?.description {
                Text(after).font(Theme.Font.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// Minimal wrapping row. `LazyVGrid` can't size to content and `HStack` can't wrap.
struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + spacing; lineHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}
