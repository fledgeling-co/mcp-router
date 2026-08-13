import SwiftUI

/// Every server the router knows about, and the two numbers that matter per row:
/// how many tools it contributes, and when it was last actually used.
struct ServersView: View {
    @Environment(RouterStore.self) private var store
    @Binding var selected: String?
    @State private var filter: Filter = .all
    @State private var query = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all, running, idle, attention
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .running: "Running"
            case .idle: "Idle"
            case .attention: "Needs you"
            }
        }
    }

    private func count(_ f: Filter) -> Int {
        switch f {
        case .all: store.servers.count
        case .running: store.runningCount
        case .idle: store.idleCount
        case .attention: store.needingAttention.count
        }
    }

    private var rows: [MCPServer] {
        store.servers.filter { s in
            let passesFilter = switch filter {
            case .all: true
            case .running: s.isRunning
            case .idle: !s.isRunning
            case .attention: s.needsAttention
            }
            let passesQuery = query.isEmpty
                || s.name.localizedCaseInsensitiveContains(query)
                || s.toolNames.contains { $0.localizedCaseInsensitiveContains(query) }
            return passesFilter && passesQuery
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Servers", subtitle: "\(store.totalTools) tools from \(store.servers.count) servers")

            // Counts live in the tab, not beside it. A tab reading "Running 1" answers the
            // question before you click it, which is what makes the row of tabs a summary
            // rather than a navigation control.
            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { f in
                    Text(count(f) > 0 ? "\(f.title)  \(count(f))" : f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()
            ColumnHeader(columns: [("", Theme.Row.gutter), ("server", 150), ("transport", 74),
                                   ("tools", 48), ("calls", 54), ("last used", 72), ("", 100)])

            if rows.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Nothing here" : "No match for \"\(query)\"",
                    systemImage: "square.stack.3d.up.slash"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { s in
                            ServerRow(server: s, isSelected: selected == s.name)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = (selected == s.name) ? nil : s.name }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search servers and tools")
        .inspector(isPresented: .init(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let name = selected, let s = store.servers.first(where: { $0.name == name }) {
                ServerDetailView(server: s)
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
            }
        }
    }
}

struct ServerRow: View {
    @Environment(RouterStore.self) private var store
    let server: MCPServer
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            StateDot(server: server)
                .frame(width: Theme.Row.gutter)

            VStack(alignment: .leading, spacing: 1) {
                Text(server.name).font(Theme.Font.row.weight(.medium)).lineLimit(1)
                if !server.projects.isEmpty {
                    Text("scoped to \(server.projects.count) project\(server.projects.count == 1 ? "" : "s")")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 150, alignment: .leading)

            Text(server.transport)
                .font(Theme.Font.secondary.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            Text("\(server.tools)")
                .font(Theme.Font.rowMono)
                .foregroundStyle(server.tools == 0 ? .tertiary : .secondary)
                .frame(width: 48, alignment: .leading)

            HStack(spacing: 3) {
                Text("\(server.usage.calls)")
                    .font(Theme.Font.rowMono)
                    .foregroundStyle(server.usage.calls == 0 ? .tertiary : .secondary)
                if server.usage.errors > 0 {
                    Text("\(server.usage.errors)")
                        .font(Theme.Font.rowMono)
                        .foregroundStyle(Theme.failed.opacity(0.8))
                        .help("\(server.usage.errors) failed")
                }
            }
            .frame(width: 54, alignment: .leading)

            // "Never" as a value in the column, rather than a separate screen for unused
            // servers. The question "is anything using this" is the same question for every
            // row, so it gets the same column.
            Text(server.usage.lastUsed == nil ? "Never" : shortAgo(iso: server.usage.lastUsed))
                .font(Theme.Font.rowMono)
                .foregroundStyle(server.usage.lastUsed == nil ? .tertiary : .secondary)
                .frame(width: 72, alignment: .leading)

            Spacer(minLength: 8)
            trailing.frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .rowDivider()
    }

    @ViewBuilder private var trailing: some View {
        if server.pendingChange != nil {
            Label("Held", systemImage: "shield.lefthalf.filled")
                .labelStyle(.titleAndIcon)
                .font(Theme.Font.secondary.weight(.medium))
                .foregroundStyle(Theme.attention)
        } else if server.indexError != nil {
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Font.secondary.weight(.medium))
                .foregroundStyle(Theme.failed)
        } else if server.auth.supported && !server.auth.authorized {
            Button("Authorize") { Task { await store.authorize(server.name) } }
                .controlSize(.small)
                .font(Theme.Font.secondary)
        } else if server.warm {
            Label("Warm", systemImage: "flame")
                .font(Theme.Font.secondary)
                .foregroundStyle(.secondary)
                .help("Kept running rather than reaped when idle")
        } else if server.isRunning {
            // "in flight" and "served" are different facts and both are worth showing:
            // one says why it can't be reaped yet, the other says whether it earns its
            // place. An idle-but-alive server shows the second alone.
            Text(server.inFlight > 0 ? "\(server.inFlight) in flight" : "idle \(server.idleSec)s")
                .font(Theme.Font.secondary)
                .foregroundStyle(.tertiary)
                .help("\(server.callsServed) call\(server.callsServed == 1 ? "" : "s") served since it started")
        }
    }
}
