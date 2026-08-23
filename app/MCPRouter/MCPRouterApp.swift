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
/// `MCPRouterKit` and `MCPRouterUI` for that reason, and what is left here is four `Scene`s and
/// eight menu builders whose *contents* come from the model.
@main
@MainActor
struct MCPRouterApp: App {
    @NSApplicationDelegateAdaptor(ShellAppDelegate.self) private var appDelegate
    /// The one shell, owned by the app delegate rather than by this scene.
    ///
    /// It moved there so the notification delegate could be attached at launch: a response that
    /// *launches* the app is delivered once, before launching finishes, and is discarded outright if
    /// nothing is listening yet. Installed from a `WindowGroup.onAppear` — where this was — the
    /// press that woke the app is lost, and `Decline` is the bad half of that: the user presses it,
    /// the app opens, and nothing is declined.
    @State private var model = ShellAppDelegate.shell

    var body: some Scene {
        WindowGroup("MCP Router") {
            ShellWindow(model: model)
                .frame(
                    minWidth: MetricToken.sidebar.leadingScalar * 2,
                    minHeight: MetricToken.sidebar.leadingScalar
                )
        }
        .commands { ShellCommands() }

        // The fourth scene, and SwiftUI's `Settings` rather than a hand-built `Window`.
        //
        // On macOS the standard settings window is what carries the **disabled minimise and zoom**,
        // the titlebar height and the `⌘,` binding; building those by hand reproduces something the
        // platform already gives, and reproduces it slightly wrong. It is also why no Window-menu
        // item is declared here: whatever macOS contributes is macOS's, and a second Settings
        // command would put two items with two spellings in two menus.
        //
        // `BuildIdentity` is constructed here because this file is the one permitted to name
        // `Bundle` (A36), and it travels in as a value rather than being read inside the window.
        Settings {
            SettingsWindow(model: model, buildIdentity: BuildIdentity(bundle: .main))
        }

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
/// Eight explicit builders rather than a loop, because SwiftUI's `CommandsBuilder` cannot iterate
/// top-level menus — a `CommandGroup` is a *position* in a menu macOS already owns and a
/// `CommandMenu` is a whole menu of the app's, and neither is a list. What is driven by the model
/// is every item's title, shortcut, enabled state and disabled reason, which is the part A19 and
/// A20 actually check.
///
/// **Six until M20**, which adds the mock's Router and Library menus as the two `CommandMenu`s
/// below. They are declared last because SwiftUI places a `CommandMenu` immediately before the
/// Window menu regardless of declaration order, and grouping them at the end is the only way this
/// file's reading order matches the bar's.
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

        // **No `CommandGroup(replacing: .appSettings)`, and that is a measurement rather than a
        // preference.** Declaring the `Settings` scene above makes macOS contribute `Settings…` at
        // `⌘,` by itself. With a `SettingsLink` also declared here, the running app's menu bar
        // carried **two** `Settings…` items bound to the same chord — measured over the
        // accessibility plane on 2026-08-22, `AXMenuItemCmdChar` `,` on both. Two items with one
        // spelling and one chord is exactly what this file's own note says re-declaring a system
        // item produces, so the app declares none and `MenuCommand.settings.isSystemProvided`
        // records that the item is the platform's now.

        // `Export Library…` left this group at M20. The mock draws it in the Library menu and the
        // command model moved with it; leaving the item declared here as well would put one command
        // in two menus, which is the two-`Settings…` defect above with a different title.
        CommandGroup(replacing: .newItem) {
            item(.addServer)
            item(.addMarketplace)
            item(.pairPhone)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            item(.find)
            item(.resetServer)
            item(.removeServer)
        }

        // Replacing `.sidebar` puts these in the View menu and removes the system's own sidebar
        // toggle, so there is one command for showing the sidebar rather than two.
        //
        // `MenuCommand.allCases` orders the destinations by accelerator digit since M20, so this
        // `ForEach` reads the menu the mock draws — `⌘1` first — rather than sidebar order.
        CommandGroup(replacing: .sidebar) {
            ForEach(MenuCommand.inMenu(.view).filter(\.isDestinationSelection), id: \.self) { target in
                item(target)
            }
            Divider()
            item(.showSidebar)
        }

        // The two menus M20 adds. `CommandMenu` rather than `CommandGroup`, because these are whole
        // top-level menus the app declares rather than positions in a menu macOS already owns — and
        // SwiftUI places a `CommandMenu` before the Window menu, which is where the mock draws both.
        //
        // Their **contents** come from `MenuCommand.inMenu(_:)` exactly as the six groups above do,
        // so the dividers are the only thing written here. The divider positions are the mock's own
        // and are the one thing in this file that is a layout decision; they carry no behaviour, and
        // A19's walk reads items rather than separators.
        CommandMenu(MenuBarMenu.router.rawValue) {
            item(.reindexManifest)
            item(.restartRouter)
            Divider()
            item(.wakeServer)
            item(.tripBreaker)
            item(.reapChildren)
            Divider()
            item(.reviewHeldChanges)
            item(.revealRouterLog)
            Divider()
            item(.stopRouter)
        }

        CommandMenu(MenuBarMenu.library.rawValue) {
            item(.updateAllSkills)
            item(.runDoctor)
            Divider()
            item(.runAllChecks)
            item(.exportLibrary)
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
    /// The one shell for this process.
    ///
    /// A Release build gets the live loopback client and can never be talked into a fixture; a Debug
    /// build takes a scenario from the environment so the acceptance gate can drive the app into any
    /// of `DESIGN.md` §5's states. `ShellClientFactory` holds that rule, where a test reaches it.
    /// The notifier needs the process's own bundle identifier, and this file is the only one that
    /// may read it: A36's one-channel gate forbids the name `Bundle` in `MCPRouterUI`'s shell files,
    /// and that gate is satisfied rather than amended.
    ///
    /// Here rather than as the scene's `@State` because the notification delegate has to be attached
    /// before launching finishes, which is earlier than any scene exists.
    @MainActor static let shell = ShellModel(
        client: ShellClientFactory.makeClient(),
        notifier: ArrivalNotifierFactory.make(bundleIdentifier: Bundle.main.bundleIdentifier)
    )

    func applicationDidFinishLaunching(_: Notification) {
        ShellMenuReasons.install()
        // **At launch, not on a view's appearance.** `UNUserNotificationCenter.delegate` must be set
        // before the app finishes launching, or the response that launched the app is delivered to
        // nobody and thrown away. Assembly, like everything else here: the guard, the mapping from a
        // press to a route, and every operation a route names live in `MCPRouterUI` and
        // `MCPRouterKit` where a test reaches them.
        InboxNotificationDelegate.install(
            on: Self.shell,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    }
}
