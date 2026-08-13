import MCPRouterKit
import SwiftUI

/// Binds the eight-role ramp to `Font`.
///
/// One of the two files allowed to write a raw size (see `ColorToken+SwiftUI.swift`); everywhere
/// else a numeric font size fails the lint gate. Nothing in the product renders off this ladder —
/// 13pt body is the loudest native-versus-web discriminator there is, and a 16pt body means it is
/// not a Mac app.
public extension TypeToken {
    /// The role as a system font at its documented size and emphasis.
    var font: Font {
        .system(size: size, weight: weight)
    }

    /// The instrument voice: monospace, for numerals, counts, durations, error codes and status
    /// subtitles. `DESIGN.md` §2 is explicit that it loses its meaning if it leaks into prose, so
    /// this is deliberately a separate call rather than a parameter with a default.
    var monospacedFont: Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    var weight: Font.Weight {
        switch emphasis {
        case .bold: .bold
        case .semibold: .semibold
        }
    }

    /// The leading the document specifies, expressed as the adjustment SwiftUI wants.
    ///
    /// SwiftUI has no direct line-height API; `lineSpacing` is the gap *between* lines, so the
    /// document's line height has to have the font's own line height subtracted from it. Clamped at
    /// zero because a negative spacing would tighten text below the ramp rather than match it.
    var lineSpacing: Double { max(0, lineHeight - size * 1.2) }
}

public extension View {
    /// Applies a role's font and its documented leading together.
    ///
    /// Separate modifiers let a surface take the font and forget the leading, which is how a ladder
    /// stops being a ladder.
    func typeRole(_ token: TypeToken, monospaced: Bool = false) -> some View {
        font(monospaced ? token.monospacedFont : token.font)
            .lineSpacing(token.lineSpacing)
    }
}
