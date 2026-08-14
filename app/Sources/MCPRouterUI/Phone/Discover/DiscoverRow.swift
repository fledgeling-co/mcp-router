import MCPRouterKit
import SwiftUI

/// One registry entry in the list.
///
/// **This view formats nothing.** Its one figure arrives as a finished string from
/// `DiscoverPresentation`, which is what makes A1 and A7 checkable — see that type's doc comment
/// for why the whole feature is built this way.
struct DiscoverRow: View {
    let entry: RegistryEntry
    /// The band this row is being shown under, which decides which single figure it carries.
    /// A row under Most used shows sessions; a row under Recently changed shows when it changed.
    /// Showing both would put two numbers on a 44pt row and make neither read.
    let band: DiscoverBand?

    var body: some View {
        HStack(spacing: PhoneMetric.normal) {
            RoundedRectangle(cornerRadius: PhoneMetric.tileRadius)
                .fill(ColorToken.raised.color)
                .frame(width: PhoneMetric.tile, height: PhoneMetric.tile)
                .overlay {
                    IconView(.discover, size: PhoneMetric.tile / 2)
                        .foregroundStyle(ColorToken.t3.color)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                Text(entry.displayName)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                    // Overflow: a long display name truncates on one line. The full value is on
                    // Detail. The row grows with Dynamic Type but never with the name (A29).
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let figure {
                    Text(figure)
                        // Instrument data, so monospace — `DESIGN.md` §2.
                        .typeRole(.caption, monospaced: true)
                        .foregroundStyle(ColorToken.t2.color)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            IconView(.chev, size: TypeToken.caption.size)
                .foregroundStyle(ColorToken.t3.color)
                .accessibilityHidden(true)
        }
        .padding(.vertical, PhoneMetric.snug)
        // A **minimum**, not a fixed height. `DESIGN.md` §5's "rows never change height" is an
        // Overflow rule about long values — satisfied above by truncating the name — and pinning a
        // height here would clip the row at accessibility text sizes. The skeleton row uses this
        // same modifier so nothing jumps when data lands (A29).
        .frame(minHeight: PhoneMetric.row)
        .contentShape(Rectangle())
    }

    /// The one figure this row carries, already rendered.
    private var figure: String? {
        switch band {
        case .mostUsed: DiscoverPresentation.useCountText(entry)
        case .recentlyChanged: DiscoverPresentation.changedText(entry)
        // In search results there are no bands, so the row falls back to the figure the endpoint
        // itself ranks on. Nil where the entry carries no count — never "0 sessions" (A2).
        case nil: DiscoverPresentation.useCountText(entry)
        }
    }
}

/// The loading row.
///
/// `DESIGN.md` §5: a skeleton matching the real row geometry, never a spinner over a blank pane.
/// It reads the **same** `minHeight` modifier the populated row does, which is what stops the list
/// jumping when results land — a skeleton that guesses a height is a skeleton that lies about what
/// is arriving.
struct DiscoverSkeletonRow: View {
    var body: some View {
        HStack(spacing: PhoneMetric.normal) {
            RoundedRectangle(cornerRadius: PhoneMetric.tileRadius)
                .fill(ColorToken.f2.color)
                .frame(width: PhoneMetric.tile, height: PhoneMetric.tile)

            VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                bar(width: PhoneMetric.skeletonTitle, role: .body, fill: ColorToken.f2)
                bar(
                    width: PhoneMetric.skeletonSubtitle,
                    role: .caption,
                    monospaced: true,
                    fill: ColorToken.f3
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, PhoneMetric.snug)
        .frame(minHeight: PhoneMetric.row)
        .accessibilityHidden(true)
    }

    /// One placeholder line.
    ///
    /// Its height comes from **hidden text at the row's own type role**, not from a number. Sizing
    /// the bar to `TypeToken.body.size` looks equivalent and is not: a font's rendered line box is
    /// taller than its point size, and the two roles differ again, so the skeleton measured 1.67pt
    /// shorter than the row it replaces and the list stepped when results landed. Taking the height
    /// from the same text that will occupy the space makes them equal by construction rather than
    /// by an arithmetic that has to be redone whenever the ladder moves.
    private func bar(
        width: CGFloat,
        role: TypeToken,
        monospaced: Bool = false,
        fill: ColorToken
    ) -> some View {
        Text(verbatim: " ")
            .typeRole(role, monospaced: monospaced)
            .hidden()
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: PhoneMetric.hairline * 2).fill(fill.color)
            )
    }
}
