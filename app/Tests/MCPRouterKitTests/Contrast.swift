import Foundation

/// WCAG 2.x relative luminance and contrast, so the document's ratios are computed rather than
/// trusted.
///
/// Written out here rather than pulled from a dependency because it is thirty lines and the
/// alternative is adding a package to the one target that must stay dependency-free.
enum Contrast {
    /// One colour's three channels, each 0…1. A struct rather than a tuple because the lint's
    /// two-member ceiling is the right rule — `.r` reads better than `.1` at every call site here.
    struct Channels {
        let r: Double
        let g: Double
        let b: Double
    }

    /// sRGB companded channel → linear light.
    static func linearise(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// The three channels of `#RRGGBB`.
    static func channels(_ hex: String) -> Channels {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 else { return Channels(r: 0, g: 0, b: 0) }
        func byte(_ index: Int) -> Double {
            let start = digits.index(digits.startIndex, offsetBy: index * 2)
            let end = digits.index(start, offsetBy: 2)
            return Double(UInt8(digits[start ..< end], radix: 16) ?? 0) / 255
        }
        return Channels(r: byte(0), g: byte(1), b: byte(2))
    }

    private static func luminance(_ c: Channels) -> Double {
        0.2126 * linearise(c.r) + 0.7152 * linearise(c.g) + 0.0722 * linearise(c.b)
    }

    static func relativeLuminance(_ hex: String) -> Double {
        luminance(channels(hex))
    }

    /// A token composited over its background at its own alpha, then measured.
    ///
    /// The tiers and fills are semi-transparent, so their contrast is a property of the pair rather
    /// than of the colour — measuring `#000` alone would answer 21:1 for every one of them.
    /// Compositing happens in companded sRGB, which is what a display actually does.
    static func compositedLuminance(hex: String, alpha: Double, over background: String) -> Double {
        let f = channels(hex)
        let b = channels(background)
        return luminance(Channels(
            r: f.r * alpha + b.r * (1 - alpha),
            g: f.g * alpha + b.g * (1 - alpha),
            b: f.b * alpha + b.b * (1 - alpha)
        ))
    }

    static func ratio(_ one: Double, _ other: Double) -> Double {
        (max(one, other) + 0.05) / (min(one, other) + 0.05)
    }
}
