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
    case sidebar = "Sidebar"
    case popoverRadius = "Popover radius"
    case tableRows = "Table rows"

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
        case .sidebar: 256
        case .popoverRadius: 20
        case .tableRows: 24
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
        .controlMini, .controlSmall, .controlRegular, .controlLarge, .controlExtraLarge,
    ]
}
