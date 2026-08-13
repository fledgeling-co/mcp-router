import SwiftUI

/// Servers nothing has called.
///
/// The frame here is "idle, consider removing", not a trash can. A never-used server was
/// never deleted, so there is nothing to restore and nothing to purge; the honest offer
/// is a list of things that are costing you tool-list space and giving nothing back, with
/// the evidence for that claim shown next to each one.
struct CleanupView: View {
    @Environment(RouterStore.self) private var store
    @Binding var selected: String?
    @Binding var pane: Pane
    @State private var confirming: MCPServer?

    /// How long the log has been running. Every claim on this pane depends on it, so it
    /// is stated rather than assumed: "never used" over four minutes of history is not
    /// evidence of anything.
    private var window: (label: String, trustworthy: Bool) {
        guard let since = store.since?.asDate else { return ("unknown", false) }
        let days = Date().timeIntervalSince(since) / 86_400
        return (shortAgo(since), days >= 7)
    }

    private var unusedTools: Int { store.neverUsed.reduce(0) { $0 + $1.tools } }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "Cleanup",
                subtitle: "Recording for \(window.label) · \(store.calls.count) calls seen"
            )

            if store.neverUsed.isEmpty {
                allClear
            } else {
                summary
                Divider()
                ColumnHeader(columns: [("", Theme.Row.gutter), ("server", 170), ("tools", 60),
                                       ("added", 80), ("", nil)])
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.neverUsed) { s in
                            UnusedRow(server: s,
                                      inspect: { selected = s.name; pane = .servers },
                                      remove: { confirming = s })
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove \(confirming?.name ?? "")?",
            isPresented: .init(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let c = confirming { Task { _ = await store.remove(c.name) } }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text("Deletes it from the router's config along with its cached tools and any stored tokens. You can install it again from Discover, or by adding it to ~/.claude.json as you always did.")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(store.neverUsed.count)").font(Theme.Font.metric)
                    Text("never called").font(Theme.Font.secondary).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(unusedTools)").font(Theme.Font.metric)
                    Text("tools they contribute").font(Theme.Font.secondary).foregroundStyle(.secondary)
                }
                Spacer()
            }

            // The honest cost, and only the honest cost. The tempting number here is memory
            // saved, and it would be invented: the router never runs the world where these
            // servers are all resident, so it has no counterfactual to subtract from. What
            // it does know is that these tools are in every session's tool list.
            Text(unusedTools > 0
                 ? "These sit in every session's tool list, where a model reads them, and none has been called."
                 : "None of these contributes any tools.")
                .font(Theme.Font.secondary)
                .foregroundStyle(.secondary)

            if !window.trustworthy {
                Label("Less than a week of history so far — a server you use monthly will show up here.",
                      systemImage: "clock.badge.questionmark")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.attention)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var allClear: some View {
        ContentUnavailableView {
            Label("Everything here gets used", systemImage: "checkmark.circle")
        } description: {
            Text("All \(store.servers.count) servers have been called at least once in the \(window.label) of history recorded.")
        }
    }
}

private struct UnusedRow: View {
    let server: MCPServer
    let inspect: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            StateDot(server: server).frame(width: Theme.Row.gutter)

            Text(server.name)
                .font(Theme.Font.row.weight(.medium))
                .frame(width: 170, alignment: .leading)

            Text("\(server.tools)")
                .font(Theme.Font.rowMono)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(shortAgo(iso: server.indexedAt))
                .font(Theme.Font.rowMono)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)
                .help("First indexed by the router")

            // A reason it might legitimately be unused, where there is one. A server scoped
            // to a project you haven't opened this month is not a candidate for removal, and
            // presenting it as one is how a cleanup tool loses trust.
            if !server.projects.isEmpty {
                Label("scoped to \(server.projects.count) project\(server.projects.count == 1 ? "" : "s")",
                      systemImage: "folder")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.tertiary)
            } else if server.indexError != nil {
                Label("never started", systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.failed)
            }

            Spacer()

            Button("Inspect", action: inspect).controlSize(.small)
            Button("Remove", role: .destructive, action: remove).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .rowDivider()
    }
}
