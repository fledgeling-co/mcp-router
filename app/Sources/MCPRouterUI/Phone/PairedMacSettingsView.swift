import MCPRouterKit
import SwiftUI

/// The paired-Mac row. One height, whatever the name.
///
/// The height is `PhoneMetric.row` and it is fixed, which is what makes the Overflow state work:
/// a long name truncates rather than wrapping, so a list of Macs stays a list of equal rows instead
/// of a ragged column. `DESIGN.md` §5 states it as a rule — "rows never change height" — and the
/// skeleton reads the same constant so nothing jumps when data lands.
struct PairedMacRow: View {
    let mac: PairedMac
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: PhoneMetric.normal) {
            RoundedRectangle(cornerRadius: PhoneMetric.tileRadius, style: .continuous)
                .fill(ColorToken.f2.color)
                .frame(width: PhoneMetric.tile, height: PhoneMetric.tile)
                .overlay(
                    // The product mark stands in for a device glyph: the shared icon set has no
                    // `mac`, and adding one is a change to F2's inventory rather than this
                    // feature's. Recorded as a shared-surface item; the mark is at least honest —
                    // it is the Mac running MCP Router that this row is about.
                    IconView(.conduit, size: PhoneMetric.tile / 2)
                        .foregroundStyle(ColorToken.t2.color)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                Text(mac.name)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(PairingSubtitle.text(for: mac))
                    .typeRole(.callout, monospaced: true)
                    .foregroundStyle(ColorToken.t3.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                IconView(.chev, size: TypeToken.callout.size)
                    .foregroundStyle(ColorToken.t4.color)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, PhoneMetric.normal)
        .frame(height: PhoneMetric.row)
        .background(
            RoundedRectangle(cornerRadius: PhoneMetric.cardRadius, style: .continuous)
                .fill(ColorToken.raised.color)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mac.name), \(PairingSubtitle.text(for: mac))")
    }
}

/// The loading skeleton, at exactly the populated row's geometry.
///
/// It reads `PhoneMetric.row` and `PhoneMetric.tile` rather than restating them, so the two cannot
/// drift. A skeleton that is a different height from the row it replaces makes the whole surface
/// jump the moment data arrives, which is the specific failure `DESIGN.md` §2 calls out about the
/// Servers board and which applies identically here.
struct PairedMacSkeleton: View {
    var body: some View {
        HStack(spacing: PhoneMetric.normal) {
            RoundedRectangle(cornerRadius: PhoneMetric.tileRadius, style: .continuous)
                .fill(ColorToken.f2.color)
                .frame(width: PhoneMetric.tile, height: PhoneMetric.tile)

            VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                RoundedRectangle(cornerRadius: PhoneMetric.hairline, style: .continuous)
                    .fill(ColorToken.f2.color)
                    .frame(width: PhoneMetric.skeletonTitle, height: TypeToken.body.size)
                RoundedRectangle(cornerRadius: PhoneMetric.hairline, style: .continuous)
                    .fill(ColorToken.f3.color)
                    .frame(width: PhoneMetric.skeletonSubtitle, height: TypeToken.caption.size)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, PhoneMetric.normal)
        .frame(height: PhoneMetric.row)
        .background(
            RoundedRectangle(cornerRadius: PhoneMetric.cardRadius, style: .continuous)
                .fill(ColorToken.raised.color)
        )
        .accessibilityLabel(PairingCopy.entry(.settingsLoading).body)
    }
}

/// A titled block of prose with an optional action — the shape the empty, error and camera states
/// all take.
struct PhoneMessageBlock: View {
    let entry: PairingCopy.Entry
    var tone: Tone = .neutral
    var glyph: Icon?
    var action: (() -> Void)?
    var secondaryAction: (() -> Void)?

    enum Tone {
        case neutral
        /// An actionable warning — a caution before an irreversible grant. `--attn` earns its
        /// meaning here: a decision is genuinely being asked for.
        case caution
        /// Something the flow depends on is unavailable. `--fail`.
        case failure

        var accent: ColorToken {
            switch self {
            case .neutral: .t3
            case .caution: .attention
            case .failure: .fail
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.snug) {
            if let headline = entry.headline {
                HStack(spacing: PhoneMetric.snug) {
                    if let glyph {
                        IconView(glyph, size: TypeToken.callout.size)
                            .foregroundStyle(tone.accent.color)
                            .accessibilityHidden(true)
                    }
                    Text(headline)
                        .typeRole(.title3)
                        .foregroundStyle(ColorToken.t1.color)
                }
            }

            Text(entry.body)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)

            if entry.carriesNarrowing {
                Text(PairingCopy.neverInstalls)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let label = entry.actionLabel, let action {
                Button(label, action: action)
                    .buttonStyle(ProminentButtonStyle())
                    .frame(minHeight: PhoneMetric.minimumTarget)
            }
            if let label = entry.secondaryActionLabel, let secondaryAction {
                Button(label, action: secondaryAction)
                    .buttonStyle(StandardButtonStyle())
                    .frame(minHeight: PhoneMetric.minimumTarget)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A quiet section label. Sentence case, secondary colour — `DESIGN.md` §3.2 is explicit that
/// tracked uppercase is the loudest web tell and that the fix is removal, not tighter tracking.
struct PhoneSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .typeRole(.subheadline)
            .foregroundStyle(ColorToken.t3.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The paired-Mac surface, in all nine of its states.
///
/// Driven by one enum rather than a scatter of optionals, so `DESIGN.md` §5 is checkable: a test
/// constructs each case and renders it, and a tenth state added later fails to compile until its
/// copy exists.
public struct PairedMacSettingsView: View {
    private let state: PairedMacSurfaceState
    private let onPair: () -> Void
    private let onUnpair: () -> Void

    public init(
        state: PairedMacSurfaceState,
        onPair: @escaping () -> Void = {},
        onUnpair: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onPair = onPair
        self.onUnpair = onUnpair
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.normal) {
            PhoneSectionLabel(text: "Paired Mac")

            switch state {
            case let .reachable(mac):
                PairedMacRow(mac: mac)
                ConnectionBanner(.reachable, macName: nil)
                    .overlay(alignment: .leading) { EmptyView() }
                unpairButton

            case .neverPaired:
                PhoneMessageBlock(
                    entry: PairingCopy.entry(.settingsNeverPaired),
                    glyph: nil,
                    action: onPair
                )

            case .loading:
                PairedMacSkeleton()
                Text(PairingCopy.entry(.settingsLoading).body)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)

            case let .partial(mac):
                PairedMacRow(mac: mac)
                Text(PairingCopy.entry(.settingsPartial).body)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                unpairButton

            case .unreadable:
                PhoneMessageBlock(
                    entry: PairingCopy.entry(.settingsUnreadable),
                    tone: .failure,
                    glyph: .warn,
                    action: onPair
                )

            case let .justPaired(mac):
                PairedMacRow(mac: mac)
                Text(PairingCopy.entry(.settingsJustPaired).body)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                unpairButton

            case let .macUnreachable(mac):
                PairedMacRow(mac: mac)
                Text(PairingCopy.entry(.settingsMacUnreachable).body)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                unpairButton
            }

            PhoneSectionLabel(text: "About")
            Text(PairingCopy.neverInstalls)
                .typeRole(.callout)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Destructive, and never the default. The consequence is named in the dialog this opens, not
    /// implied by the button.
    @ViewBuilder
    private var unpairButton: some View {
        Button("Unpair this Mac", role: .destructive, action: onUnpair)
            .buttonStyle(StandardButtonStyle())
            .frame(minHeight: PhoneMetric.minimumTarget)
            .padding(.top, PhoneMetric.tight)
    }
}
