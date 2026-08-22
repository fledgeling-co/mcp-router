import Foundation

/// The eight menus the app is responsible for, in bar order.
///
/// **Six until M20.** `Router` and `Library` are the mock's own two, and they sit between View and
/// Window because that is where `design/mcp-router-console.html` draws them — the bar order is a
/// fact about the drawn menu bar rather than a preference, and `mac-shell.sh` reads it back off the
/// running app in this order.
///
/// The Apple menu is macOS's and is not here, for the reason fourteen individual *items* are marked
/// `isSystemProvided`: the app does not build it and cannot rename it.
public enum MenuBarMenu: String, CaseIterable, Sendable {
    case app = "MCP Router"
    case file = "File"
    case edit = "Edit"
    case view = "View"
    case router = "Router"
    case library = "Library"
    case window = "Window"
    case help = "Help"
}

/// Why a command cannot be used right now.
///
/// Exactly three reasons exist, and they are on the type rather than at each call site so a fourth
/// cannot be invented in passing. `DESIGN.md` §3.4 requires a disabled control to dim in place
/// with a discoverable reason and forbids hiding it; on macOS a menu item's only place for that
/// reason is its help tag, which is where `MCPRouterUI` puts this string.
///
/// **The third was added by M14, on the type and once**, which is what the rule above protects:
/// adding a reason *here* is a deliberate widening of the vocabulary, adding one at a call site is
/// the drift it forbids. It exists because two refusals could not tell apart the only two ways a
/// command can be unusable for good, and collapsing them shipped a live defect. `.surfaceAbsent`
/// says **this build** lacks a surface the product has — a `Destination` whose board is not
/// compiled in. `.featureUnbuilt` says **the product** lacks the thing entirely. With one refusal
/// covering both, a command kept the answer it was given when its surface had not shipped, and
/// nothing could detect that it had stopped being true: `Pair iPhone…` told the user the app was
/// not built for two items after M6 shipped the pairing sheet it opens.
public enum CommandAvailability: Hashable, Sendable {
    /// Usable now.
    case enabled
    /// The surface this command acts on is not installed in this build.
    case surfaceAbsent
    /// The feature this command performs does not exist in the product yet, in any build.
    case featureUnbuilt
    /// The command acts on a selected server and there is no selection.
    case needsServerSelection

    public var isEnabled: Bool { self == .enabled }

    /// The sentence shown in the item's help tag. Non-blaming, non-emoting, and honest about the
    /// actual condition — a state-shaped reason for a surface that simply does not exist yet
    /// would be a lie, and `DESIGN.md` §6 rules out both blame and invention.
    ///
    /// **This is the generic answer, and `MenuCommand.reason(in:)` is the one the menu reads.**
    /// `.featureUnbuilt`'s sentence used to be generic *because* exactly one command carried it,
    /// and its own note named the moment that stops being true: *"both are larger than the item
    /// that added the case, and both become worth doing the moment a second command takes it."*
    /// M20 is that moment — eight commands carry it — and of the two options the note offered, the
    /// one taken is moving resolution onto `MenuCommand`. An associated value would have changed
    /// every `==` against the case at six sites; this changes none of them, and every existing
    /// reader of this property keeps the answer it already had.
    public var reason: String? {
        switch self {
        case .enabled: nil
        case .surfaceAbsent: "This part of the app isn't built yet."
        case .featureUnbuilt: "This feature hasn't been built yet."
        case .needsServerSelection: "Select a server first."
        }
    }

    /// The short form, for the shortcut column.
    ///
    /// The brief and `PRD.md` §9.8 both put the reason **in the shortcut column** rather than only
    /// in a tool tip — `Install Command-Line Tool · Installed` is the pattern — because a reason
    /// that needs a hover is a reason a person reading the menu does not have. `NSMenuItemBadge` is
    /// the platform's own right-aligned trailing text and is what `ShellMenuReasons` writes this
    /// into; the full sentence above stays in the help tag, where the accessibility tree reads it.
    ///
    /// **The two unbuilt answers keep different words here too.** Collapsing them to one badge
    /// would undo M14's separation one layer down, where no test was looking: the sentences would
    /// still differ and the thing a person actually reads would not.
    public var badge: String? {
        switch self {
        case .enabled: nil
        case .surfaceAbsent: "Not in this build"
        case .featureUnbuilt: "Not built yet"
        case .needsServerSelection: "No selection"
        }
    }
}

/// Every command the menu bar offers.
///
/// `DESIGN.md` §3.9 makes the menu bar the complete command surface, so this is the whole of what
/// the app can be asked to do. The oracle for completeness is **not** this type — a list that
/// defines itself proves nothing. It is the inventory table in `planning/specs/spec-M1.md`, which
/// `MenuCommandTests` parses and compares in both directions, so a command added here without
/// being specified fails just as loudly as one specified and never built.
///
/// `Space`, `Return` and `Esc` have no case here on purpose. Every ⌘-combination in §8 is a menu
/// item because a ⌘-shortcut with no menu item is undiscoverable; a bare key on a focused row is
/// not a menu command on macOS — Finder binds Space to Quick Look and lists "Quick Look ⌘Y". The
/// shell routes those three to the content zone instead, which `ShellKeyRoutingTests` proves.
public enum MenuCommand: Hashable, Sendable {
    /// App.
    case about, settings, hide, hideOthers, showAll, quit
    /// File.
    case addServer, addMarketplace, pairPhone, closeWindow
    /// Edit.
    case undo, redo, cut, copy, paste, selectAll, find, resetServer, removeServer
    // View.
    case selectDestination(Destination)
    case showSidebar
    /// Router — the daemon's own verbs (M20).
    case reindexManifest, restartRouter, wakeServer, tripBreaker, reapChildren
    case reviewHeldChanges, revealRouterLog, stopRouter
    /// Library (M20). `exportLibrary` moved here from File, which is where the mock draws it.
    case updateAllSkills, runDoctor, runAllChecks, exportLibrary
    // Window.
    case minimise, zoom, bringAllToFront
    // Help.
    case help, whatTheRouterDoes, reportIssue

    /// The commands that are not per-destination.
    ///
    /// Hand-written, and safe to be: `MenuCommandTests` compares the whole of `allCases` against
    /// the spec's inventory table in both directions, so an omission here is a test failure rather
    /// than a silent gap. That external oracle is what makes a literal list acceptable.
    private static let fixedCases: [MenuCommand] = [
        .about, .settings, .hide, .hideOthers, .showAll, .quit,
        .addServer, .addMarketplace, .pairPhone, .closeWindow,
        .undo, .redo, .cut, .copy, .paste, .selectAll, .find, .resetServer, .removeServer,
        .showSidebar,
        .reindexManifest, .restartRouter, .wakeServer, .tripBreaker, .reapChildren,
        .reviewHeldChanges, .revealRouterLog, .stopRouter,
        .updateAllSkills, .runDoctor, .runAllChecks, .exportLibrary,
        .minimise, .zoom, .bringAllToFront,
        .help, .whatTheRouterDoes, .reportIssue
    ]

    /// The destination-selection commands are generated from `Destination`, so the View menu can
    /// never fall out of step with the sidebar.
    ///
    /// **Ordered by accelerator digit rather than by sidebar order since M20.** The mock draws the
    /// View menu in digit order and the digits are no longer contiguous with the sidebar's order —
    /// `⌘5` and `⌘9` belong to Harnesses and Insights, which M22 ships. A menu reading 4, 3, 2, 1
    /// is what sidebar order would produce, and the digit is the only thing this menu is for.
    public static var allCases: [MenuCommand] {
        let destinations = Destination.allCases
            .filter { $0.selectionDigit != nil }
            .sorted { ($0.selectionDigit ?? 0) < ($1.selectionDigit ?? 0) }
            .map { MenuCommand.selectDestination($0) }
        return fixedCases + destinations
    }

    public var menu: MenuBarMenu {
        switch self {
        case .about, .settings, .hide, .hideOthers, .showAll, .quit: .app
        case .addServer, .addMarketplace, .pairPhone, .closeWindow: .file
        case .undo, .redo, .cut, .copy, .paste, .selectAll, .find, .resetServer, .removeServer: .edit
        case .selectDestination, .showSidebar: .view
        case .reindexManifest, .restartRouter, .wakeServer, .tripBreaker, .reapChildren,
             .reviewHeldChanges, .revealRouterLog, .stopRouter: .router
        case .updateAllSkills, .runDoctor, .runAllChecks, .exportLibrary: .library
        case .minimise, .zoom, .bringAllToFront: .window
        case .help, .whatTheRouterDoes, .reportIssue: .help
        }
    }

    /// The item's title.
    ///
    /// **Title case since M20, and it is the kit winning rather than §6 losing.** `DESIGN.md` §6
    /// asks for sentence case everywhere and its own precedence rule says the macOS 27 kit wins
    /// where the two disagree; Apple's HIG specifies title-style capitalization for menu items, and
    /// the brief, `PRD.md` §9.8 and the mock all draw them that way. Six of the titles below were
    /// already title case for exactly this reason — they are strings macOS contributes and the app
    /// cannot rename — so the menu bar was previously carrying `Hide Others` directly above `Add
    /// server…`. §6 now records the exception explicitly rather than being quietly broken by half
    /// the menu.
    ///
    /// The **verbs are unchanged**: this is a case conversion, not a rename. The mock spells `⌘N`
    /// as `New Server…` and `DESIGN.md` §8 spells it `Add server…`; §8 is the document
    /// `MenuCommandTests` holds this model against and it wins, so the command stays `Add`.
    public var title: String {
        switch self {
        case .about: "About MCP Router"
        // `…` because it opens a window now (§3.4). M8 shipped it without one, correctly, while
        // Settings was a sidebar destination and `⌘,` moved the selection; M15 makes that false.
        // `opensAFurtherView` is derived from this string, so it follows for free.
        case .settings: "Settings…"
        case .hide: "Hide MCP Router"
        case .hideOthers: "Hide Others"
        case .showAll: "Show All"
        case .quit: "Quit MCP Router"
        case .addServer: "Add Server…"
        // **No longer `SkillPresentation.marketplacesAction`.** The Skills board draws that string
        // on two buttons, and `DESIGN.md` §6 keeps buttons in sentence case — so the menu item and
        // the button stopped being able to share one literal the moment the menu went title case.
        // `ActivityResetEntryPointTests` pins the button's spelling and is untouched by this.
        case .addMarketplace: "Add Marketplace…"
        case .pairPhone: "Pair iPhone…"
        case .exportLibrary: "Export Library…"
        case .closeWindow: "Close"
        case .undo: "Undo"
        case .redo: "Redo"
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste: "Paste"
        case .selectAll: "Select All"
        case .find: "Find"
        case .resetServer: "Reset Server"
        case .removeServer: "Remove Server"
        case let .selectDestination(destination): destination.title
        case .showSidebar: "Show Sidebar"
        case .reindexManifest: "Re-index Manifest"
        case .restartRouter: "Restart Router"
        case .wakeServer: "Wake Selected Server"
        case .tripBreaker: "Trip Selected Breaker"
        case .reapChildren: "Reap Idle Children"
        case .reviewHeldChanges: "Review Held Changes…"
        case .revealRouterLog: "Reveal Router Log in Finder"
        case .stopRouter: "Stop Router"
        case .updateAllSkills: "Update All Skills"
        case .runDoctor: "Run Doctor"
        case .runAllChecks: "Run All Checks"
        case .minimise: "Minimize"
        case .zoom: "Zoom"
        case .bringAllToFront: "Bring All to Front"
        case .help: "MCP Router Help"
        case .whatTheRouterDoes: "What the Router Actually Does"
        case .reportIssue: "Report an Issue"
        }
    }

    /// `DESIGN.md` §3.4: `…` means "opens a further view"; its absence means "commits now".
    ///
    /// Derived from the title rather than stored beside it, so the two cannot disagree — a stored
    /// flag and a title ending in an ellipsis are two places to say one thing.
    public var opensAFurtherView: Bool { title.hasSuffix("…") }

    /// Whether **macOS** puts this item in the menu bar rather than the app declaring it.
    ///
    /// Fourteen of the thirty-three are the system's. The app does not build them, cannot rename
    /// them, and re-declaring one would produce two items that do the same thing under two
    /// spellings. They are in this inventory because they are genuinely in the menu bar and §3.9
    /// makes it the complete command surface — but the acceptance walk needs to know which are the
    /// app's, because "the menu bar carries exactly the inventory" is only checkable in both
    /// directions over the items the app is responsible for.
    ///
    /// This is also why six of the titles above are title case against `DESIGN.md` §6's sentence
    /// case: they are the kit's own strings, measured from the running menu bar — `Hide Others`,
    /// `Show All`, `Select All`, `Minimize`, `Bring All to Front`, `Close`. `DESIGN.md`'s own
    /// precedence rule settles it: where the document and the macOS kit disagree, the kit wins.
    public var isSystemProvided: Bool {
        switch self {
        // `settings` joined at M15, and it is a reading rather than a reclassification. Declaring a
        // `Settings` scene makes macOS contribute `Settings…` at `⌘,` on its own; the app also
        // declaring one put **two** items with one spelling and one chord in the app menu, measured
        // on the running build on 2026-08-22. So the item is the platform's, exactly as Hide and
        // Quit are, and the app builds none.
        case .hide, .hideOthers, .showAll, .quit,
             .closeWindow,
             .settings,
             .undo, .redo, .cut, .copy, .paste, .selectAll,
             .minimise, .zoom, .bringAllToFront:
            true
        case .about,
             .addServer, .addMarketplace, .pairPhone, .exportLibrary,
             .find, .resetServer, .removeServer,
             .selectDestination, .showSidebar,
             .reindexManifest, .restartRouter, .wakeServer, .tripBreaker, .reapChildren,
             .reviewHeldChanges, .revealRouterLog, .stopRouter,
             .updateAllSkills, .runDoctor, .runAllChecks,
             .help, .whatTheRouterDoes, .reportIssue:
            false
        }
    }

    /// The commands the app itself builds, which is what A19 compares in both directions.
    public static var appDeclared: [MenuCommand] {
        allCases.filter { !$0.isSystemProvided }
    }

    public var shortcut: KeyChord? {
        switch self {
        case .settings: KeyChord(",")
        case .hide: KeyChord("H")
        case .hideOthers: KeyChord("H", [.command, .option])
        case .quit: KeyChord("Q")
        case .addServer: KeyChord("N")
        case .addMarketplace: KeyChord("N", [.command, .shift])
        case .closeWindow: KeyChord("W")
        case .undo: KeyChord("Z")
        case .redo: KeyChord("Z", [.command, .shift])
        case .cut: KeyChord("X")
        case .copy: KeyChord("C")
        case .paste: KeyChord("V")
        case .selectAll: KeyChord("A")
        case .find: KeyChord("F")
        case .resetServer: KeyChord("R")
        case .removeServer: KeyChord("⌫")
        case let .selectDestination(destination):
            destination.selectionDigit.map { KeyChord("\($0)") }
        case .showSidebar: KeyChord("S", [.command, .control])
        case .minimise: KeyChord("M")
        // The one accelerator M20 grants, and the rule that granted only one.
        //
        // The mock's Router and Library menus claim ten chords. Nine of them sit on commands that
        // are `.featureUnbuilt` in every context, and this repo already argued that case at length
        // over `⌘E` below: a shortcut on a command that can never fire is a system combination
        // claimed for nothing. So the rule generalises rather than being re-decided per item — **a
        // command that cannot fire in any context carries no accelerator** — and `⌃W` is the only
        // one left, because `Wake Selected Server` is the only Router verb the control API can
        // perform (`patch(warm: true)`).
        //
        // `⌘R` is deliberately **not** re-pointed at `Re-index Manifest`, which is where the mock
        // binds it. `DESIGN.md` §8 binds `⌘R` to resetting the selected server and was re-authored
        // *from* this same mock under M21 on 2026-08-22 — the later reading of one source — and it
        // is the document `MenuCommandTests` holds this map against.
        //
        // `Stop Router` would carry none regardless of that rule: `PRD.md` §9.7's gate row and the
        // brief both say so, because its blast radius is every session on the machine.
        case .wakeServer: KeyChord("W", [.control])
        // `MCP Router help` deliberately carries **no** shortcut, and this is measured rather
        // than assumed. `DESIGN.md` §8 never asked for one; an earlier draft of the inventory
        // invented `⌘?`, which is `⇧⌘/` on every layout macOS ships and is **reserved by the
        // system** for the Help menu's own search field — it silently binds nothing. Verified by
        // binding `⌘J` to this same item in this same menu, which appeared immediately, so the
        // Help menu does not strip shortcuts and `⇧⌘/` specifically is unavailable.
        // `Export library…` deliberately carries **no** shortcut, for the same reason `MCP Router
        // help` does not, and it used to carry `⌘E`. Two things are wrong with that and neither is
        // about export. `DESIGN.md` §8's table is where this app's ⌘-combinations are granted and
        // it never granted `⌘E`. And `⌘E` is a **standard macOS shortcut** already — Finder's
        // *Eject*, and Cocoa's *Use Selection for Find* in any text context — so the app was
        // claiming a system combination for a command that can never fire, since `exportLibrary` is
        // `.featureUnbuilt` in every context. Same class as the `⌘?` draft below: a shortcut nobody
        // can reach, discovered by reading rather than by measuring the key.
        //
        // The day export ships, §8 is the place that grants it a key, not this switch.
        case .about, .showAll, .pairPhone, .exportLibrary, .zoom, .bringAllToFront,
             .reindexManifest, .restartRouter, .tripBreaker, .reapChildren,
             .reviewHeldChanges, .revealRouterLog, .stopRouter,
             .updateAllSkills, .runDoctor, .runAllChecks,
             .help, .whatTheRouterDoes, .reportIssue: nil
        }
    }

    /// Whether this command selects a destination.
    ///
    /// So the View menu's builder can take its items from `inMenu(.view)` — which is already in
    /// digit order — rather than re-deriving the order from `Destination`. Two places deriving one
    /// order is two places for it to be wrong, and the digits stopped being contiguous at M20.
    public var isDestinationSelection: Bool {
        if case .selectDestination = self { return true }
        return false
    }

    /// The commands in one menu, in menu order.
    public static func inMenu(_ menu: MenuBarMenu) -> [MenuCommand] {
        allCases.filter { $0.menu == menu }
    }

    /// The three bare keys the shell must not claim, named so a test can assert their absence.
    ///
    /// `DESIGN.md` §8 gives each a behaviour that belongs to a surface with rows, a default action
    /// or a sheet. The shell routes them to the content zone rather than binding them, and
    /// `MenuCommandTests` fails if any command here ever takes one.
    public static let keysReservedForContent: Set<String> = ["Space", "Return", "Esc"]
}
