import SwiftUI

/// The four panes. Named `Pane` rather than `Section` so it cannot shadow SwiftUI's
/// `Section` inside a `Form`, which it silently did.
enum Pane: String, Hashable, CaseIterable, Identifiable {
    case activity, servers, discover, cleanup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: "Activity"
        case .servers: "Servers"
        case .discover: "Discover"
        case .cleanup: "Cleanup"
        }
    }
    var icon: String {
        switch self {
        case .activity: "list.bullet.rectangle"
        case .servers: "square.stack.3d.up"
        case .discover: "sparkle.magnifyingglass"
        case .cleanup: "arrow.down.left.and.arrow.up.right.circle"
        }
    }
}

struct RootView: View {
    @Environment(RouterStore.self) private var store
    @State private var pane: Pane? = .activity
    @State private var selectedServer: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                ForEach(Pane.allCases) { s in
                    Label(s.title, systemImage: s.icon)
                        .badge(badge(for: s))
                        .tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 168, ideal: 188, max: 240)
            .safeAreaInset(edge: .bottom) { connectionFooter }
        } detail: {
            switch pane ?? .activity {
            case .activity: ActivityView()
            case .servers: ServersView(selected: $selectedServer)
            case .discover: DiscoverView()
            case .cleanup:
                CleanupView(
                    selected: $selectedServer,
                    pane: .init(get: { pane ?? .cleanup }, set: { pane = $0 })
                )
            }
        }
        .alert("Couldn't do that", isPresented: .init(
            get: { store.actionError != nil },
            set: { if !$0 { store.actionError = nil } }
        )) {
            Button("OK") { store.actionError = nil }
        } message: {
            Text(store.actionError ?? "")
        }
    }

    /// Counts, not dots. A sidebar badge that reads "3" tells you the size of the job;
    /// a dot only tells you there is one, and then you have to click to find out.
    private func badge(for s: Pane) -> Int {
        switch s {
        case .servers: store.needingAttention.count
        case .cleanup: store.neverUsed.count
        default: 0
        }
    }

    private var connectionFooter: some View {
        HStack(spacing: 6) {
            switch store.connection {
            case .up(let port):
                Circle().fill(Theme.ok).frame(width: 6, height: 6)
                Text("127.0.0.1:\(String(port))")
                    .font(Theme.Font.secondary.monospaced())
                    .foregroundStyle(.secondary)
            case .connecting:
                ProgressView().controlSize(.mini)
                Text("Connecting").font(Theme.Font.secondary).foregroundStyle(.secondary)
            case .down(let why):
                // The reason, not a euphemism. "Not running" covered a 401, a wrong port
                // and a missing token identically, which made the one visible piece of
                // diagnostic information in the app useless.
                Circle().fill(Theme.failed).frame(width: 6, height: 6)
                Text(why)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(why)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// A section header used across every detail view, so the four panes read as one app
/// rather than four screens that happen to share a sidebar.
struct PaneHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(Theme.Font.secondary).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

extension PaneHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Column labels for the fixed matrix. Rendered once above a list, never repeated
/// per group, so the eye keeps one set of column positions for the whole pane.
struct ColumnHeader: View {
    let columns: [(String, CGFloat?)]
    var leadingInset: CGFloat = 12

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                Text(col.0.uppercased())
                    .font(Theme.Font.sectionLabel)
                    .foregroundStyle(.tertiary)
                    .kerning(0.4)
                    .frame(width: col.1, alignment: .leading)
                    .frame(maxWidth: col.1 == nil ? .infinity : nil, alignment: .leading)
            }
            // Without this the row of fixed-width labels centres itself in the pane,
            // leaving a wide empty gutter on the left and detaching the headers from
            // the rows they label.
            if columns.allSatisfy({ $0.1 != nil }) { Spacer(minLength: 0) }
        }
        .padding(.horizontal, leadingInset)
        .padding(.vertical, 5)
        .rowDivider()
    }
}
