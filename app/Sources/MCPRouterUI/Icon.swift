import MCPRouterKit
import SwiftUI

/// The icon set, closed.
///
/// The inventory is the prototype's 21-symbol sprite. Modelling it as an exhaustive enum rather
/// than passing symbol names around as strings is the whole point: a surface cannot ask for an icon
/// that does not exist, because a missing case is a compile error rather than a blank square.
///
/// `DESIGN.md` §4 says drawn, never unicode — SF Symbols at matched weights where one fits, an
/// authored asset where none does. Exactly one of the 21 has no reasonable symbol: `conduit` is the
/// product's own mark, so it is drawn here as a `Shape`. A gradient rectangle standing in for an
/// authored asset is called out in §4 as the loudest low-fidelity tell available, and this avoids
/// it by actually drawing the thing.
public enum Icon: String, CaseIterable, Sendable {
    case activity, servers, skills, discover, inbox, evals, cleanup, settings
    case harness, insights
    case search, chev, check, warn, bang, shield, bolt, tray, book, list, compass, layers
    case conduit
    /// The cold-start mark, on a call row and on a popover call row alike.
    ///
    /// §4 says drawn, never unicode, and the prototype marks a cold call with `❄` — a character,
    /// at whatever weight the font happens to carry, on no grid. This is the symbol that replaces
    /// it, so the mark sits at the same stroke weight as every other icon in the app.
    ///
    /// M8 arrived with a second case, `cold`, for the popover's mark — same concept, same
    /// `snowflake`, drawn beside a different row. Two names for one mark is how the sprite grows a
    /// duplicate that the count assertion cannot see (22 is 22 either way), so the merge keeps this
    /// one and the popover uses it.
    case frost

    /// The SF Symbol that carries this icon, or nil when it is authored here instead.
    ///
    /// Every name is asserted at runtime by `IconTests` — an unknown symbol name renders as nothing
    /// at all rather than failing, so "the string is non-empty" would be a check that passes while
    /// the icon is invisible.
    public var systemName: String? {
        switch self {
        case .activity: "waveform.path.ecg"
        case .servers: "square.stack.3d.up"
        case .skills: "rhombus"
        case .discover: "sparkles"
        case .inbox: "tray.and.arrow.down"
        case .evals: "checkmark.seal"
        // Deliberately NOT a bin or a trash can. `DESIGN.md` §9: a never-used server was never
        // deleted, so Cleanup does not use a trash metaphor.
        case .cleanup: "arrow.down.circle"
        // The mock draws a drawn harness glyph and a bar-chart glyph; these are the SF
        // Symbols nearest each at the same 1.4-ish stroke weight, per §4.
        case .harness: "point.3.connected.trianglepath.dotted"
        case .insights: "chart.bar"
        case .settings: "gearshape"
        case .search: "magnifyingglass"
        case .chev: "chevron.right"
        case .check: "checkmark"
        case .warn: "exclamationmark.triangle"
        case .bang: "exclamationmark.circle"
        case .shield: "shield"
        case .bolt: "bolt"
        case .tray: "tray.full"
        case .book: "book"
        case .list: "list.bullet"
        case .compass: "location.north.circle"
        case .layers: "square.3.layers.3d"
        case .conduit: nil
        case .frost: "snowflake"
        }
    }

    /// Whether this icon is drawn here rather than taken from the system set.
    public var isAuthored: Bool { systemName == nil }
}

/// Renders an `Icon` at a weight matched to the surrounding type.
public struct IconView: View {
    private let icon: Icon
    private let size: Double
    private let weight: Font.Weight

    public init(_ icon: Icon, size: Double = TypeToken.body.size, weight: Font.Weight = .semibold) {
        self.icon = icon
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        Group {
            if let name = icon.systemName {
                Image(systemName: name)
                    .font(.system(size: size, weight: weight))
            } else {
                ConduitMark()
                    .stroke(style: .init(lineWidth: size / 9.5, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityLabel(icon.rawValue)
    }
}

/// The product's own mark: two runs converging into one, which is what the router does.
///
/// Authored rather than approximated with a system symbol, because §4 permits an authored asset
/// exactly where no symbol fits and forbids standing a decorative shape in its place.
struct ConduitMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Two inbound runs.
        p.move(to: CGPoint(x: w * 0.10, y: h * 0.20))
        p.addCurve(
            to: CGPoint(x: w * 0.52, y: h * 0.50),
            control1: CGPoint(x: w * 0.36, y: h * 0.20),
            control2: CGPoint(x: w * 0.36, y: h * 0.50)
        )
        p.move(to: CGPoint(x: w * 0.10, y: h * 0.80))
        p.addCurve(
            to: CGPoint(x: w * 0.52, y: h * 0.50),
            control1: CGPoint(x: w * 0.36, y: h * 0.80),
            control2: CGPoint(x: w * 0.36, y: h * 0.50)
        )
        // One outbound.
        p.move(to: CGPoint(x: w * 0.52, y: h * 0.50))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.50))
        return p
    }
}
