import SwiftUI

/// The menu bar popover: the same instrument as the window, at a glance size.
///
/// It answers three questions and refuses the rest — what is running right now, what
/// just happened, and is anything waiting on me. Everything that needs a decision lives
/// in the window; a popover that dismisses when you reach for another app is the wrong
/// place to be halfway through installing a server.
struct MenuBarView: View {
    @Environment(RouterStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var now = Date()

    private let tick = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if !store.needingAttention.isEmpty {
                attentionBand
                Divider()
            }

            if store.calls.isEmpty {
                emptyLog
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.calls.prefix(14)) { call in
                            CallRow(call: call, now: now, compact: true)
                        }
                    }
                }
                .frame(maxHeight: Theme.popoverMaxHeight)
            }

            Divider()
            footer
        }
        .frame(width: Theme.popoverWidth)
        .onReceive(tick) { now = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            switch store.connection {
            case .up:
                // The count that matters is the one the router exists to make small.
                // "1 running" against "10 idle" is the product working, stated as a fact
                // rather than as a claim about memory the app cannot verify.
                Text("\(store.runningCount) running")
                    .font(Theme.Font.row.weight(.medium))
                Text("·").foregroundStyle(.tertiary)
                Text("\(store.idleCount) idle")
                    .font(Theme.Font.row)
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text("\(store.totalTools) tools")
                    .font(Theme.Font.row)
                    .foregroundStyle(.secondary)
            case .connecting:
                Text("Connecting…").font(Theme.Font.row).foregroundStyle(.secondary)
            case .down(let why):
                Label(why, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.failed)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var attentionBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.needingAttention) { s in
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: icon(for: s))
                            .foregroundStyle(Theme.attention)
                            .font(.system(size: 11))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name).font(Theme.Font.row.weight(.medium))
                            Text(reason(for: s))
                                .font(Theme.Font.secondary)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.attention.opacity(0.07))
    }

    private func icon(for s: MCPServer) -> String {
        if s.pendingChange != nil { return "shield.lefthalf.filled" }
        if s.indexError != nil { return "exclamationmark.triangle.fill" }
        return "key.fill"
    }

    private func reason(for s: MCPServer) -> String {
        if let p = s.pendingChange { return "\(p.count) tool description\(p.count == 1 ? "" : "s") changed — held" }
        if let e = s.indexError { return e }
        return "Needs authorization"
    }

    private var emptyLog: some View {
        VStack(spacing: 5) {
            Text("No tool calls yet")
                .font(Theme.Font.row)
                .foregroundStyle(.secondary)
            Text("Nothing is running until a session calls something.")
                .font(Theme.Font.secondary)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Open mcp-router") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .font(Theme.Font.row)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .font(Theme.Font.row)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// One tool call, in fixed columns.
///
/// The columns do not reflow with content, and that is the whole design: a log read by
/// scanning down a gutter is read at a glance, while a log whose timestamp moves with the
/// length of the tool name above it has to be read line by line. Long names truncate;
/// the column stays where it is.
struct CallRow: View {
    let call: CallRecord
    let now: Date
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(call.ok ? Theme.ok.opacity(0.65) : Theme.failed)
                .frame(width: 5, height: 5)
                .frame(width: Theme.Row.gutter, alignment: .center)

            Text(shortAgo(call.date, from: now))
                .font(Theme.Font.rowMono)
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .leading)

            Text(call.server)
                .font(Theme.Font.row.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: compact ? 84 : Theme.Row.server, alignment: .leading)

            Text(call.tool)
                .font(Theme.Font.rowMono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !compact {
                Text(projectLabel(cwd: call.cwd, project: call.project))
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)
                    .help(call.cwd ?? "")
            }

            // A cold call is the one number on this row that explains the product: the
            // process was not running, so this call paid to start it. Marking it is how
            // "lazy" stops being a claim in a README and becomes something you watch happen.
            HStack(spacing: 3) {
                if call.cold {
                    Image(systemName: "snowflake")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                Text("\(call.ms)ms")
                    .font(Theme.Font.rowMono)
                    .foregroundStyle(call.ms > 1000 ? .secondary : .tertiary)
            }
            .frame(width: Theme.Row.duration, alignment: .trailing)
        }
        .padding(.horizontal, compact ? 8 : 12)
        .frame(height: compact ? Theme.Row.compactHeight : Theme.Row.height)
        .help(call.err ?? "")
        .rowDivider()
    }
}
