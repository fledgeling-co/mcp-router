import Foundation

/// The seven places the Settings window's source list can take you.
///
/// A `CaseIterable` enum for the same reason `Destination` is one: the seven are a compile-time
/// fact, so a pane cannot be added without every exhaustive switch over it failing to compile until
/// it is handled. A hand-maintained array would let one drift in undrawn.
///
/// **The order is the mock's `data-pane` sequence, not the brief's prose.** The two disagree about
/// where Menu bar sits — the brief's sentence puts it last and its own table puts it sixth — and
/// `design/mcp-router-console.html` draws it sixth. `SettingsPaneTests` reads that sequence out of
/// the mock at test time rather than restating it, so this list cannot agree with itself by
/// construction.
public enum SettingsPane: String, CaseIterable, Sendable, Identifiable {
    case router
    case harnesses
    case analyst
    case updates
    case security
    /// The mock spells this `menubar`; the Swift case is spelled the way the rest of the kit spells
    /// the concept. The `rawValue` is the identifier the mock and the restoration key both match.
    case menuBar = "menubar"
    case advanced

    public var id: String { rawValue }

    /// The label in the source list, and the heading the pane opens with.
    ///
    /// Sentence case, stored the way it is drawn — `DESIGN.md` §3.2 says the fix for a tracked
    /// upper-case label is to remove it rather than to re-track it, so there is no case transform
    /// anywhere in this window.
    public var title: String {
        switch self {
        case .router: "Router"
        case .harnesses: "Harnesses"
        case .analyst: "Session analyst"
        case .updates: "Updates"
        case .security: "Security"
        case .menuBar: "Menu bar"
        case .advanced: "Advanced"
        }
    }

    /// The one line under the name, saying what the pane governs.
    ///
    /// **Four of the seven are authored rather than taken from the mock, and each is authored for
    /// the same reason a control is omitted.** `spec-M15.md` §2's fifth assumption is that a control
    /// naming a capability this product does not have is not built; a *sentence* naming one is the
    /// same claim one level up, and it is worse than the control because nothing about it looks
    /// unfinished. The mock's Harnesses line promises "what this app may do to other tools'
    /// configuration files, and how often it re-reads them" — four preferences that exist nowhere in
    /// either target — and its Session analyst line describes a model that reads your sessions.
    /// Router's line survives intact because both of its clauses are drawn.
    ///
    /// Every divergence is a row in `planning/fidelity/settings.pairing.tsv` with the artifact that
    /// already recorded the absence, so it is reported on every run rather than smoothed away.
    public var subtitle: String {
        switch self {
        case .router:
            "The endpoint your harnesses point at, and how long a child stays alive after its last call."
        case .harnesses:
            "Which harnesses this router fronts, and where that is decided."
        case .analyst:
            "Whether anything reads your sessions to suggest capabilities."
        case .updates:
            "How this app and the capabilities you have installed are kept current."
        case .security:
            "The token this app reaches the router with, and the devices allowed to queue work here."
        case .menuBar:
            "What the status item shows, and when it takes a dot."
        case .advanced:
            "Where the router keeps its log and its configuration."
        }
    }

    /// The raw value of the `Icon` case this pane draws.
    ///
    /// A string rather than the `Icon` type itself, for the reason `Destination.iconName` is one:
    /// `Icon` lives in `MCPRouterUI` and this module must stay free of UI frameworks
    /// (`SWIFT_PRACTICES.md` §8). `SettingsPaneTests`' counterpart in the UI module asserts every
    /// one of these resolves to a real case.
    ///
    /// **Four of the mock's seven source-list symbols have no `Icon` case and none is added.** The
    /// mock draws `#i-harness`, `#i-download`, `#i-menubar` and `#i-sliders`; `Icon`'s inventory is
    /// asserted against the *prototype's* 21-symbol sprite by `DesignSystemTests`, so adding four
    /// cases would re-base that count from one document to the other — which is M21's whole
    /// substance rather than this item's. The nearest shipped case is used and the four unmatched
    /// symbols are declared in the fidelity manifest's note.
    public var iconName: String {
        switch self {
        case .router: "servers"
        case .harnesses: "layers"
        case .analyst: "bolt"
        case .updates: "tray"
        case .security: "shield"
        case .menuBar: "list"
        case .advanced: "settings"
        }
    }

    /// The panes in source-list order, which is declaration order.
    public static var ordered: [SettingsPane] { allCases }

    /// What a stored pane restores to when this build no longer has it.
    ///
    /// Router, for the reason `Destination.fallback` is Activity: it is the first pane and the one
    /// that needs no prior selection to be meaningful.
    public static let fallback: SettingsPane = .router

    /// Restores a stored raw value, falling back rather than failing.
    public static func restoring(_ storedRawValue: String?) -> SettingsPane {
        guard let storedRawValue, let pane = SettingsPane(rawValue: storedRawValue) else {
            return fallback
        }
        return pane
    }
}
