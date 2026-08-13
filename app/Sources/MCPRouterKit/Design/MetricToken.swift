import Foundation

/// Chrome geometry from `DESIGN.md` §2.
///
/// Only the **leading scalar** of each documented cell is represented here, because several of
/// those cells are prose rather than a single number — `52pt (8 + 36 XL controls + 8)` and
/// `24–28pt for dense lists` carry a value plus an explanation. The parity test compares that
/// leading scalar and nothing else, and the rows whose cell does not begin with a number are
/// excluded from the check by name so the gap is visible rather than implied.
public enum MetricToken: String, CaseIterable, Sendable {
    case titlebar = "Titlebar"
    case unifiedToolbar = "Unified toolbar"
    case sidebar = "Sidebar"
    case popoverRadius = "Popover radius"
    case tableRows = "Table rows"

    /// The leading number of the documented value.
    public var leadingScalar: Double {
        switch self {
        case .titlebar: 33
        case .unifiedToolbar: 52
        case .sidebar: 256
        case .popoverRadius: 20
        case .tableRows: 24
        }
    }
}
