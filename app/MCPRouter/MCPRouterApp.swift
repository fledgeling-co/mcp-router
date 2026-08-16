import AppKit
import MCPRouterKit
import MCPRouterUI
import SwiftUI

/// The macOS shell: the window, the menu bar, and nothing decidable.
///
/// Everything this file does is assembly. `app/MCPRouter` is not a SwiftPM target, so nothing here
/// can be reached by `swift test` — which means anything with a decision in it would be a clause
/// with no possible red-green evidence. The navigation model, the command inventory, the readout
/// derivation, the shell's views and **which control client it talks to** all live in
/// `MCPRouterKit` and `MCPRouterUI` for that reason, and what is left here is a `Scene` and six menu
/// builders whose *contents* come from the model.
@main
struct MCPRouterApp: App {
    @NSApplicationDelegateAdaptor(ShellAppDelegate.self) private var appDelegate
    /// A Release build gets the live loopback client and can never be talked into a fixture; a Debug
    /// build takes a scenario from the environment so the acceptance gate can drive the app into any
    /// of `DESIGN.md` §5's states. `ShellClientFactory` holds that rule, where a test reaches it.
    /// The notifier needs the process's own bundle identifier, and this is the only file that may
    /// read it: A36's one-channel gate forbids the name `Bundle` in `MCPRouterUI`'s shell files, and
    /// that gate is satisfied rather than amended. Assembly, like everything else here.
    @State private var model = ShellModel(
        client: ShellClientFactory.makeClient(),
        notifier: ArrivalNotifierFactory.make(bundleIdentifier: Bundle.main.bundleIdentifier)
    )

    var body: some Scene {
        WindowGroup("MCP Router") {
            ShellWindow(model: model)
                // Assembly, like everything else here: the guard, the mapping from a press to an
                // operation, and both operations live in `MCPRouterUI` where a test reaches them.
                .onAppear {
                    InboxNotificationDelegate.install(
                        on: model,
                        bundleIdentifier: Bundle.main.bundleIdentifier
                    )
                }
                .frame(
                    minWidth: MetricToken.sidebar.leadingScalar * 2,
                    minHeight: MetricToken.sidebar.leadingScalar
                )
        }
        .commands { ShellCommands() }

        // The glanceable instrument. `isInserted` is the gating API — `SceneBuilder` has no
        // `buildOptional`, so `if flag { MenuBarExtra(…) }` does not compile, and this is the only
        // way a scene can be conditionally present.
        //
        // The binding is on the model rather than an `@AppStorage` here, so the preference has an
        // evidence lane: nothing in this directory is a SwiftPM target, and a value read straight
        // from a `Scene` is a value no test can drive. `ShellRestoration` owns it.
        //
        // Assembly only, like everything else in this file: the popover's counts, sentences, tints
        // and actions are all settled in `MCPRouterUI` and `MCPRouterKit`.
        MenuBarExtra(isInserted: $model.isMenuBarVisible) {
            MenuBarPopover(shell: model)
        } label: {
            MenuBarStatusItem(servers: model.servers, waiting: model.inboxBoard.waitingForStatusItem)
        }
        .menuBarExtraStyle(.window)

        #if DEBUG
            // Debug only, and the acceptance harness asserts its identifier is absent from a
            // Release binary. A reference surface that shipped would be a feature nobody designed.
            //
            // A `Window` scene is listed in the Window menu under its own title, which is macOS
            // contributing an entry rather than the app declaring a command — A19 excludes it by
            // name for exactly that reason.
            Window("Design system", id: "design-gallery") {
                DesignGallery()
            }
        #endif
    }
}

/// The complete command surface, per `DESIGN.md` §3.9.
///
/// Six explicit builders rather than a loop, because SwiftUI's `CommandsBuilder` cannot iterate
/// top-level menus — command groups are *positions* in a menu macOS already owns, not a list. What
/// is driven by the model is every item's title, shortcut, enabled state and disabled reason, which
/// is the part A19 and A20 actually check.
///
/// **No item names its own operation.** Each action is the same generic line — hand the command to
/// `ShellCommandRouter` — because nothing in this file can be reached by `swift test`, and a
/// decision written here is a decision with no evidence lane. `ShellCommandRouterTests` asserts the
/// whole mapping, and its `assemblyCarriesNoOperation` test greps this file to keep the line
/// generic. See `ShellCommandRouter`'s note for why driving the menu instead was not an option.
///
/// Four kinds of item are deliberately **not** declared here: Hide / Hide Others / Show All / Quit
/// in the app menu, Close in File, the standard Edit items, and Minimize / Zoom / Bring All to
/// Front in Window. macOS contributes all of those itself, and re-declaring one would produce two
/// items that do the same thing with different spellings. They are in the inventory because they
/// are in the menu bar; they are absent here because the system puts them there.
struct ShellCommands: Commands {
    @FocusedValue(\.shellModel) private var model

    /// One item, wired to the router rather than to an operation chosen here.
    private func item(_ command: MenuCommand) -> some View {
        CommandItem(command) { ShellCommandRouter.perform(command, on: model) }
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            item(.about)
        }

        CommandGroup(replacing: .appSettings) {
            // No ellipsis: Settings is a sidebar destination in this build, so `⌘,` selects a pane
            // rather than opening a further view. §3.4 makes that distinction the ellipsis's whole
            // job, so writing one here would be a false promise about what the key does.
            item(.settings)
        }

        CommandGroup(replacing: .newItem) {
            item(.addServer)
            item(.addMarketplace)
            item(.pairPhone)
            Divider()
            item(.exportLibrary)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            item(.find)
            item(.resetServer)
            item(.removeServer)
        }

        // Replacing `.sidebar` puts these in the View menu and removes the system's own sidebar
        // toggle, so there is one command for showing the sidebar rather than two.
        CommandGroup(replacing: .sidebar) {
            ForEach(Destination.ordered.filter { $0.selectionDigit != nil }, id: \.self) { target in
                item(.selectDestination(target))
            }
            Divider()
            item(.showSidebar)
        }

        CommandGroup(replacing: .help) {
            item(.help)
            item(.whatTheRouterDoes)
            item(.reportIssue)
        }
    }
}

/// The one thing the app needs AppKit for.
///
/// SwiftUI's `.help(_:)` does not reach an `NSMenuItem` — measured against this very build, every
/// item in all six menus reported `AXHelp` as `missing value` while the modifier was applied. §3.4
/// requires a disabled command to carry a discoverable reason, and a menu item's tool tip is the
/// only place macOS has for one, so the reasons are applied through AppKit each time a menu opens.
///
/// The walker itself is in `MCPRouterUI` where a test can reach it; this is only where it is armed.
final class ShellAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        ShellMenuReasons.install()
    }
}
