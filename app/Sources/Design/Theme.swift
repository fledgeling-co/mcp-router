import SwiftUI

/// The visual system, in one place.
///
/// Two rules from the design trawl are encoded here rather than left to each view.
///
/// **Dark cockpit.** Nothing draws attention unless it needs a decision. That is why
/// there is a single `attention` colour and it is used in exactly three places (a
/// held schema change, an index failure, an unauthorized server) — a palette with
/// four alert colours trains the eye to ignore all of them.
///
/// **Fixed spatial matrix.** The menu bar popover and the main window are the same
/// instrument at two sizes, so a row is built once and rendered in both. The columns
/// do not reflow: a log you read by scanning down a fixed gutter is a log you can
/// read at a glance, and a log whose timestamp column moves with content length is
/// one you have to read word by word.
enum Theme {
    // Semantic colours. Everything resolves through the asset catalogue's system
    // colours so the app follows appearance, accent and increased-contrast settings
    // without a second palette.
    static let ok = Color.green
    static let failed = Color.red
    static let attention = Color.orange
    static let idle = Color.secondary.opacity(0.45)

    /// Row geometry, from the density note in `design/app/mobbin-ledger.md`:
    /// real shipped log tables sit at 26–30pt rows with 11–12px body text.
    enum Row {
        static let height: CGFloat = 28
        static let compactHeight: CGFloat = 26
        static let gutter: CGFloat = 14      // status dot column
        static let time: CGFloat = 62        // monospace HH:MM:SS
        static let server: CGFloat = 104
        static let duration: CGFloat = 54
    }

    enum Font {
        static let row = SwiftUI.Font.system(size: 12)
        static let rowMono = SwiftUI.Font.system(size: 11.5, design: .monospaced)
        static let secondary = SwiftUI.Font.system(size: 10.5)
        static let sectionLabel = SwiftUI.Font.system(size: 10, weight: .semibold)
        static let metric = SwiftUI.Font.system(size: 22, weight: .medium, design: .rounded)
    }

    static let popoverWidth: CGFloat = 380
    static let popoverMaxHeight: CGFloat = 480
}

/// A server's live state as one dot. Deliberately the only always-present colour in a
/// row: state is glanceable, everything else is read.
struct StateDot: View {
    let server: MCPServer
    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: server.isRunning ? 7 : 5, height: server.isRunning ? 7 : 5)
            .help(tip)
    }
    private var colour: Color {
        if server.indexError != nil || server.placard != nil { return Theme.failed }
        if server.needsAttention { return Theme.attention }
        if server.isRunning { return Theme.ok }
        if server.isStarting { return Theme.attention.opacity(0.7) }
        return Theme.idle
    }
    private var tip: String {
        if let e = server.indexError { return "Failed to index: \(e)" }
        if let p = server.placard { return "Inoperative: \(p.reason)" }
        if server.pendingChange != nil { return "Tool descriptions changed — held for review" }
        if server.auth.supported && !server.auth.authorized { return "Needs authorization" }
        if server.isRunning { return "Running · \(server.inFlight) in flight, \(server.callsServed) served" }
        return "Idle — starts when a tool is called"
    }
}

/// A relative time that stays short enough for a fixed column. `RelativeDateTimeFormatter`
/// produces "3 minutes ago", which is twice as wide as this needs at every value.
func shortAgo(_ date: Date, from now: Date = Date()) -> String {
    let s = max(0, Int(now.timeIntervalSince(date)))
    switch s {
    case ..<5: return "now"
    case ..<60: return "\(s)s"
    case ..<3600: return "\(s / 60)m"
    case ..<86_400: return "\(s / 3600)h"
    case ..<(86_400 * 30): return "\(s / 86_400)d"
    default: return "\(s / (86_400 * 30))mo"
    }
}

func shortAgo(iso: String?) -> String {
    guard let iso, let d = iso.asDate else { return "never" }
    return shortAgo(d)
}

/// A project path shown as the directory name people actually recognise. The full path
/// stays available as a tooltip rather than being thrown away.
func projectLabel(cwd: String?, project: String?) -> String {
    if let project, !project.isEmpty { return project }
    guard let cwd, !cwd.isEmpty else { return "—" }
    return (cwd as NSString).lastPathComponent
}

extension View {
    /// A hairline that reads as a rule at every appearance, rather than a grey line that
    /// disappears in dark mode and shouts in light.
    func rowDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
    }
}
