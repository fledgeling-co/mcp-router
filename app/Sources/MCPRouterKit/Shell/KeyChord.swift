import Foundation

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
