import SwiftUI

@main
struct MCPRouterApp: App {
    @State private var store = RouterStore()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("mcp-router", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 880, minHeight: 560)
                .task { store.start() }
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        // `.window` rather than `.menu`: the popover is a live log with columns and its
        // own scroll region, and a menu can hold neither. It also lets the same row view
        // render in both surfaces, which is what keeps the two consistent.
        MenuBarExtra {
            MenuBarView()
                .environment(store)
                .task { store.start() }
        } label: {
            MenuBarIcon(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(store)
        }
    }
}

/// The whole of what the menu bar is allowed to say when nothing needs a decision:
/// one template glyph, no badge, no count.
///
/// The temptation is a live call counter, and it is the wrong instinct. A menu bar item
/// that changes constantly is one the eye learns to filter, and then the one time it
/// changes for a reason — a server rewrote its tool descriptions — it is filtered too.
/// So: silent at rest, and a dot only for the three states in `MCPServer.needsAttention`.
struct MenuBarIcon: View {
    let store: RouterStore

    var body: some View {
        let attention = store.needingAttention.count
        Image(systemName: "arrow.triangle.merge")
            .overlay(alignment: .topTrailing) {
                if attention > 0 {
                    Circle()
                        .fill(Theme.attention)
                        .frame(width: 5, height: 5)
                        .offset(x: 2, y: -1)
                }
            }
            .accessibilityLabel(
                attention > 0
                    ? "mcp-router — \(attention) server\(attention == 1 ? "" : "s") need attention"
                    : "mcp-router"
            )
    }
}
