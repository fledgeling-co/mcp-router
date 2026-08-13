import SwiftUI

/// The log. Which sessions, in which directories, called what.
///
/// This is the pane that answers the question the router made askable for the first
/// time: with one shared endpoint, every call from every session passes through one
/// process, so "which project is using this server" stops being unanswerable.
struct ActivityView: View {
    @Environment(RouterStore.self) private var store
    @State private var serverFilter: String?
    @State private var projectFilter: String?
    @State private var showErrorsOnly = false
    @State private var confirmingReset = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private var filtered: [CallRecord] {
        store.calls.filter { c in
            (serverFilter == nil || c.server == serverFilter)
                && (projectFilter == nil || c.cwd == projectFilter)
                && (!showErrorsOnly || !c.ok)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "Activity",
                subtitle: store.since.map { "Since \(($0.asDate).map { shortAgo($0) } ?? "install") ago · \(store.calls.count) calls" }
            ) {
                Button("Reset log", systemImage: "arrow.counterclockwise") {
                    confirmingReset = true
                }
                .controlSize(.small)
            }

            filterBar
            Divider()

            ColumnHeader(columns: [("", Theme.Row.gutter), ("when", 34), ("server", Theme.Row.server),
                                   ("tool", nil), ("project", 130), ("took", Theme.Row.duration)])

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { call in
                            CallRow(call: call, now: now)
                                .contextMenu {
                                    Button("Only \(call.server)") { serverFilter = call.server }
                                    if let cwd = call.cwd {
                                        Button("Only \(projectLabel(cwd: cwd, project: call.project))") {
                                            projectFilter = cwd
                                        }
                                        Button("Reveal project in Finder") {
                                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
                                        }
                                    }
                                    if let err = call.err {
                                        Divider()
                                        Button("Copy error") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(err, forType: .string)
                                        }
                                    }
                                }
                        }
                    }
                }
            }
        }
        .onReceive(tick) { now = $0 }
        .confirmationDialog(
            "Reset the activity log?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { Task { await store.resetUsage() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Naming the consequence, because the cleanup pane's answer depends on it: a
            // server with no calls since a reset five minutes ago is not the same claim as
            // one with no calls since it was installed.
            Text("Clears every recorded call and restarts the \"last used\" clock. Cleanup will report servers as unused from now, not from install.")
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All servers") { serverFilter = nil }
                Divider()
                ForEach(store.servers) { s in
                    Button("\(s.name)  (\(s.usage.calls))") { serverFilter = s.name }
                }
            } label: {
                Label(serverFilter ?? "All servers", systemImage: "square.stack.3d.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Button("All projects") { projectFilter = nil }
                Divider()
                ForEach(store.projects, id: \.key) { p in
                    Button("\(p.label)  (\(p.calls))") { projectFilter = p.key }
                }
            } label: {
                Label(
                    projectFilter.map { k in store.projects.first { $0.key == k }?.label ?? k } ?? "All projects",
                    systemImage: "folder"
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Toggle("Errors only", isOn: $showErrorsOnly)
                .toggleStyle(.checkbox)
                .font(Theme.Font.row)

            Spacer()

            if serverFilter != nil || projectFilter != nil || showErrorsOnly {
                Button("Clear") {
                    serverFilter = nil; projectFilter = nil; showErrorsOnly = false
                }
                .buttonStyle(.link)
                .font(Theme.Font.secondary)
            }

            Text("\(filtered.count)")
                .font(Theme.Font.rowMono)
                .foregroundStyle(.tertiary)
        }
        .font(Theme.Font.row)
        .padding(.horizontal, 14)
        .padding(.bottom, 9)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: store.calls.isEmpty ? "moon.zzz" : "line.3.horizontal.decrease")
                .font(.system(size: 26))
                .foregroundStyle(.quaternary)
            Text(store.calls.isEmpty ? "Nothing has been called yet" : "No calls match these filters")
                .font(Theme.Font.row)
                .foregroundStyle(.secondary)
            if store.calls.isEmpty {
                Text("Servers stay stopped until a session calls one of their tools.")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
