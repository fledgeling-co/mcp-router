import Foundation

/// The six menus, in bar order.
public enum MenuBarMenu: String, CaseIterable, Sendable {
    case app = "MCP Router"
    case file = "File"
    case edit = "Edit"
    case view = "View"
    case window = "Window"
    case help = "Help"
}

/// A keyboard shortcut as data.
///
/// Deliberately **not** SwiftUI's `KeyboardShortcut`: this module must stay free of UI frameworks
/// (`SWIFT_PRACTICES.md` §8) so the router's own tests can import it, and so the parity test that
/// compares this map against `DESIGN.md` §8 can run without a UI stack. `MCPRouterUI` maps this
/// to the SwiftUI value at the point of binding.
public struct KeyChord: Hashable, Sendable {
    public enum Modifier: String, CaseIterable, Sendable, Comparable {
        case control, option, shift, command

        /// Apple's canonical display position: ⌃ ⌥ ⇧ ⌘.
        ///
        /// An exhaustive `switch` rather than an index into a literal array, because the array
        /// form needs a force-unwrap to compare — and `force_unwrapping` is a SwiftLint *error*
        /// here (`SWIFT_PRACTICES.md` §3). This spelling also fails to compile when a modifier is
        /// added without being given a position, which the array form would not.
        var displayRank: Int {
            switch self {
            case .control: 0
            case .option: 1
            case .shift: 2
            case .command: 3
            }
        }

        public static func < (lhs: Modifier, rhs: Modifier) -> Bool {
            lhs.displayRank < rhs.displayRank
        }

        public var glyph: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }
    }

    /// The key itself, as the glyph the menu shows: `N`, `,`, `⌫`, `1`, `?`.
    public let key: String
    public let modifiers: Set<Modifier>

    public init(_ key: String, _ modifiers: Set<Modifier> = [.command]) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The shortcut as `DESIGN.md` §8 and the menu bar both write it — modifiers in Apple's order,
    /// then the key. This is the string the parity test compares, so the two cannot drift.
    public var display: String {
        modifiers.sorted().map(\.glyph).joined() + key
    }
}

/// Why a command cannot be used right now.
///
/// Exactly two reasons exist, and they are on the type rather than at each call site so a third
/// cannot be invented in passing. `DESIGN.md` §3.4 requires a disabled control to dim in place
/// with a discoverable reason and forbids hiding it; on macOS a menu item's only place for that
/// reason is its help tag, which is where `MCPRouterUI` puts this string.
public enum CommandAvailability: Hashable, Sendable {
    /// Usable now.
    case enabled
    /// The surface this command acts on is not installed in this build.
    case surfaceAbsent
    /// The command acts on a selected server and there is no selection.
    case needsServerSelection

    public var isEnabled: Bool { self == .enabled }

    /// The sentence shown in the item's help tag. Non-blaming, non-emoting, and honest about the
    /// actual condition — a state-shaped reason for a surface that simply does not exist yet
    /// would be a lie, and `DESIGN.md` §6 rules out both blame and invention.
    public var reason: String? {
        switch self {
        case .enabled: nil
        case .surfaceAbsent: "This part of the app isn't built yet."
        case .needsServerSelection: "Select a server first."
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
    case addServer, addMarketplace, pairPhone, exportLibrary, closeWindow
    /// Edit.
    case undo, redo, cut, copy, paste, selectAll, find, resetServer, removeServer
    // View.
    case selectDestination(Destination)
    case showSidebar
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
        .addServer, .addMarketplace, .pairPhone, .exportLibrary, .closeWindow,
        .undo, .redo, .cut, .copy, .paste, .selectAll, .find, .resetServer, .removeServer,
        .showSidebar,
        .minimise, .zoom, .bringAllToFront,
        .help, .whatTheRouterDoes, .reportIssue
    ]

    /// The destination-selection commands are generated from `Destination`, so the View menu can
    /// never fall out of step with the sidebar.
    public static var allCases: [MenuCommand] {
        let destinations = Destination.allCases
            .filter { $0.selectionDigit != nil }
            .map { MenuCommand.selectDestination($0) }
        return fixedCases + destinations
    }

    public var menu: MenuBarMenu {
        switch self {
        case .about, .settings, .hide, .hideOthers, .showAll, .quit: .app
        case .addServer, .addMarketplace, .pairPhone, .exportLibrary, .closeWindow: .file
        case .undo, .redo, .cut, .copy, .paste, .selectAll, .find, .resetServer, .removeServer: .edit
        case .selectDestination, .showSidebar: .view
        case .minimise, .zoom, .bringAllToFront: .window
        case .help, .whatTheRouterDoes, .reportIssue: .help
        }
    }

    public var title: String {
        switch self {
        case .about: "About MCP Router"
        case .settings: "Settings"
        case .hide: "Hide MCP Router"
        case .hideOthers: "Hide others"
        case .showAll: "Show all"
        case .quit: "Quit MCP Router"
        case .addServer: "Add server…"
        case .addMarketplace: "Add marketplace…"
        case .pairPhone: "Pair iPhone…"
        case .exportLibrary: "Export library…"
        case .closeWindow: "Close window"
        case .undo: "Undo"
        case .redo: "Redo"
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste: "Paste"
        case .selectAll: "Select all"
        case .find: "Find"
        case .resetServer: "Reset server"
        case .removeServer: "Remove server"
        case let .selectDestination(destination): destination.title
        case .showSidebar: "Show sidebar"
        case .minimise: "Minimise"
        case .zoom: "Zoom"
        case .bringAllToFront: "Bring all to front"
        case .help: "MCP Router help"
        case .whatTheRouterDoes: "What the router actually does"
        case .reportIssue: "Report an issue"
        }
    }

    /// `DESIGN.md` §3.4: `…` means "opens a further view"; its absence means "commits now".
    ///
    /// Derived from the title rather than stored beside it, so the two cannot disagree — a stored
    /// flag and a title ending in an ellipsis are two places to say one thing.
    public var opensAFurtherView: Bool { title.hasSuffix("…") }

    public var shortcut: KeyChord? {
        switch self {
        case .settings: KeyChord(",")
        case .hide: KeyChord("H")
        case .hideOthers: KeyChord("H", [.command, .option])
        case .quit: KeyChord("Q")
        case .addServer: KeyChord("N")
        case .addMarketplace: KeyChord("N", [.command, .shift])
        case .exportLibrary: KeyChord("E")
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
        case .help: KeyChord("?")
        case .about, .showAll, .pairPhone, .zoom, .bringAllToFront,
             .whatTheRouterDoes, .reportIssue: nil
        }
    }

    /// Whether this command is usable in the build M1 ships.
    ///
    /// The commands that act on a server or open a sheet are `surfaceAbsent` here rather than
    /// `needsServerSelection`, because in this build the reason really is that the surface does
    /// not exist — there is no servers board to select on. The board flips them to
    /// `needsServerSelection` or to `.enabled` when it lands, and the two reasons live on
    /// `CommandAvailability` so neither is retyped at a call site.
    public var availability: CommandAvailability {
        switch self {
        case .addServer, .addMarketplace, .pairPhone, .exportLibrary,
             .find, .resetServer, .removeServer:
            .surfaceAbsent
        case .about, .settings, .hide, .hideOthers, .showAll, .quit, .closeWindow,
             .undo, .redo, .cut, .copy, .paste, .selectAll,
             .selectDestination, .showSidebar,
             .minimise, .zoom, .bringAllToFront,
             .help, .whatTheRouterDoes, .reportIssue:
            .enabled
        }
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
