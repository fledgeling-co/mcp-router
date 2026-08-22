import Foundation

/// Chrome geometry from `DESIGN.md` §2, plus the focus ring from §8.
///
/// Only the **leading scalar** of each documented cell is represented here, because several of
/// those cells carry a value plus an explanation — `52pt (8 + 36 XL controls + 8)` and
/// `24–28pt for dense lists`. The parity test compares that leading scalar and nothing else.
///
/// The control ladder and the selection fill used to be excluded from the machine check because
/// their cells were prose (`Mini 16 · Small 20 · Regular 24 · …` cannot be read as one number).
/// They are now individual rows in the document and individual cases here, because the design
/// system has to *build* controls from them, and `SWIFT_PRACTICES.md` §5 forbids hardcoding a size
/// or radius. A value that no check can read is a value that drifts.
public enum MetricToken: String, CaseIterable, Sendable {
    case titlebar = "Titlebar"
    case unifiedToolbar = "Unified toolbar"

    /// The toolbar a secondary window wears — Settings, the GFM viewer. Shorter than the unified
    /// toolbar because it carries no extra-large controls, and its own row because a window that
    /// borrows the 52pt figure lays out a band of empty chrome above its first control.
    case compactToolbar = "Compact toolbar"

    case sidebar = "Sidebar"

    /// The two sidebar row heights the destinations actually use. `Sidebar` above carries the
    /// width and names the ladder in prose (`rows 24/32/40`); a height buried in another cell's
    /// prose cannot be checked, which is the reason the Servers row and the control ladder are
    /// rows of their own too.
    case sidebarRowMedium = "Sidebar row medium"
    case sidebarRowLarge = "Sidebar row large"

    case popoverRadius = "Popover radius"

    /// A card's own corner. Split out of the popover cell, which used to carry `card radius 10–14`
    /// as prose beside the popover's own number — the same value in two places, one of them
    /// unreadable to the check.
    case cardRadius = "Card radius"

    case tableRows = "Table rows"

    /// The spacing unit the whole layout is a multiple of.
    case gridUnit = "Grid unit"

    /// The Signal Path's lane (M16) and the scrollbar's track. Authored here rather than by the
    /// items that draw them, because `no-raw-design-values.sh` forbids a geometry literal under
    /// `Boards/` — so a board that arrived before its token would have to bring the token with it.
    case jackLane = "Jack lane"
    case scrollbar = "Scrollbar"

    /// The Servers board's row. Its own row in the document rather than prose inside `Table rows`,
    /// because the loading skeleton has to reproduce it exactly — a skeleton at a different height
    /// makes the board jump when the data lands, which is the one thing a skeleton exists to avoid.
    case serversRow = "Servers row"

    // The control ladder, one row per size.
    case controlMini = "Control mini"
    case controlSmall = "Control small"
    case controlRegular = "Control regular"
    case controlLarge = "Control large"
    case controlExtraLarge = "Control extra large"

    // The selection fill and the focus ring.
    case selectionRadius = "Sidebar selection radius"
    case selectionInset = "Sidebar selection inset"
    case focusRing = "Focus ring"

    /// The leading number of the documented value.
    public var leadingScalar: Double {
        switch self {
        case .titlebar: 33
        case .unifiedToolbar: 52
        case .compactToolbar: 40
        case .sidebar: 256
        case .sidebarRowMedium: 32
        case .sidebarRowLarge: 40
        case .popoverRadius: 20
        case .cardRadius: 10
        case .tableRows: 24
        case .gridUnit: 8
        case .jackLane: 44
        case .scrollbar: 12
        case .serversRow: 56
        case .controlMini: 16
        case .controlSmall: 20
        case .controlRegular: 24
        case .controlLarge: 28
        case .controlExtraLarge: 36
        case .selectionRadius: 8
        case .selectionInset: 4
        case .focusRing: 2
        }
    }

    /// The five control sizes, smallest first — the ladder a control style selects from.
    public static let controlLadder: [MetricToken] = [
        .controlMini, .controlSmall, .controlRegular, .controlLarge, .controlExtraLarge
    ]
}
