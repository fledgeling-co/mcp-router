#if canImport(AppKit)
    import AppKit
#endif
#if canImport(UIKit)
    import UIKit
#endif
import MCPRouterKit
import SwiftUI

/// Binds the token values to a SwiftUI `Color` that follows the system appearance.
///
/// **This file and `TypeToken+SwiftUI.swift` are the only two places in the product allowed to
/// write a raw colour component or a raw size.** `scripts/lint/no-raw-design-values.sh` exempts
/// them by explicit path, so the exemption is visible in the gate rather than implied — everywhere
/// else, a literal fails the build.
///
/// The colour is built with a dynamic provider rather than read from an asset catalogue. A
/// catalogue would keep the light values in JSON that `DesignTokenParityTests` never opens, so the
/// light half of the system would drift unwatched — which is the single failure the parity suite
/// exists to prevent. A dynamic provider is what a catalogue compiles down to anyway, and it keeps
/// the values in the one place the check can read.
public extension ColorToken {
    /// The token as a colour that resolves per appearance.
    var color: Color {
        #if canImport(AppKit)
            return Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark
                    ? NSColor(hex: hex, alpha: opacity)
                    : NSColor(hex: lightHex, alpha: lightOpacity)
            })
        #elseif canImport(UIKit)
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: hex, alpha: opacity)
                    : UIColor(hex: lightHex, alpha: lightOpacity)
            })
        #else
            return .clear
        #endif
    }

    /// The value that will actually be drawn in a named appearance.
    ///
    /// Exposed so a test or the acceptance harness can assert what *should* appear on screen
    /// without having to resolve a dynamic colour against a live trait collection.
    func components(for scheme: ColorScheme) -> (hex: String, opacity: Double) {
        scheme == .dark ? (hex, opacity) : (lightHex, lightOpacity)
    }
}

// MARK: - Hex decoding

/// The three channels of a colour, as a named value rather than a bare tuple.
struct RGBChannels: Equatable {
    let r: Double
    let g: Double
    let b: Double
}

/// Splits `#RRGGBB` into its three channels.
///
/// Returns nil rather than defaulting to black on a malformed string: a colour that silently
/// becomes black is the same class of quiet-wrong-answer the router's own decoding rules forbid.
func rgbChannels(of hex: String) -> RGBChannels? {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
    return RGBChannels(
        r: Double((value >> 16) & 0xFF) / 255,
        g: Double((value >> 8) & 0xFF) / 255,
        b: Double(value & 0xFF) / 255
    )
}

#if canImport(AppKit)
    extension NSColor {
        convenience init(hex: String, alpha: Double) {
            guard let c = rgbChannels(of: hex) else {
                self.init(srgbRed: 0, green: 0, blue: 0, alpha: 0)
                return
            }
            self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
        }
    }
#endif

#if canImport(UIKit)
    extension UIColor {
        convenience init(hex: String, alpha: Double) {
            guard let c = rgbChannels(of: hex) else {
                self.init(red: 0, green: 0, blue: 0, alpha: 0)
                return
            }
            self.init(red: c.r, green: c.g, blue: c.b, alpha: alpha)
        }
    }
#endif
