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
                RoundedRectangle(cornerRadius: PhoneMetric.hairline * 2)
                    .fill(ColorToken.f2.color)
                    .frame(width: PhoneMetric.skeletonTitle, height: TypeToken.body.size)
                RoundedRectangle(cornerRadius: PhoneMetric.hairline * 2)
                    .fill(ColorToken.f3.color)
                    .frame(width: PhoneMetric.skeletonSubtitle, height: TypeToken.caption.size)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, PhoneMetric.snug)
        .frame(minHeight: PhoneMetric.row)
        .accessibilityHidden(true)
    }
}
