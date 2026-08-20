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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The recovery action for a message block, drawn BELOW it rather than inside it.
///
/// `i1-phone-pairing.html` §L draws it as a `<button class="cta">` sibling *after* the `wants`
/// card, on all five Settings states that carry one, and this used to be the block's own last
/// child — so the control sat inside the card's inset instead of under it. DEF-025.
///
/// Its own view rather than a flag on the block, because the two are genuinely separate things:
/// the block is prose about a state and this is what you can do about it. A `placesActionBelow`
/// boolean would have left the block owning a control it does not draw.
///
/// Full content width, the same as every other pairing action.
struct PhoneBlockActions: View {
    let entry: PairingCopy.Entry
    var action: (() -> Void)?
    var secondaryAction: (() -> Void)?

    /// Whether this entry and these handlers produce any control at all, so a caller can leave the
    /// spacing out rather than emitting an empty view with a gap above it.
    var isEmpty: Bool {
        (entry.actionLabel == nil || action == nil)
            && (entry.secondaryActionLabel == nil || secondaryAction == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.snug) {
            if let label = entry.actionLabel, let action {
                Button(label, action: action)
                    .buttonStyle(PhoneProminentButtonStyle(fillsWidth: true))
            }
            if let label = entry.secondaryActionLabel, let secondaryAction {
                Button(label, action: secondaryAction)
                    .buttonStyle(PhoneStandardButtonStyle(fillsWidth: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The never-paired empty state — centred, with an illustration above the headline.
///
/// `i1-phone-pairing.html` §B draws this as `.pempty`: a 34pt glyph, then the headline, then the
/// prose, then the action, all centred. Rendering it through `PhoneMessageBlock` made it read as a
/// notice about a problem rather than as a surface with nothing on it yet, which is the wrong
/// first impression on the screen a new user meets first. DEF-028.
///
/// Deliberately NOT a mode on `PhoneMessageBlock`. That block draws eight other Settings states
/// and the design centres none of them, so a `isCentred` flag would put one state's treatment
/// within one boolean of all nine.
struct PhoneEmptyState: View {
    let entry: PairingCopy.Entry
    var glyph: Icon?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: PhoneMetric.snug) {
            if let glyph {
                IconView(glyph, size: PhoneMetric.emptyGlyph, weight: .light)
                    .foregroundStyle(ColorToken.t3.color)
                    .accessibilityHidden(true)
                    .padding(.bottom, PhoneMetric.tight)
            }

            if let headline = entry.headline {
                Text(headline)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                    .multilineTextAlignment(.center)
            }

            Text(entry.body)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if entry.carriesNarrowing {
                Text(PairingCopy.neverInstalls)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Below the prose and full width, as §B draws it — the same placement DEF-025 gives
            // the notice states, reached from the other direction.
            if let label = entry.actionLabel, let action {
                Button(label, action: action)
                    .buttonStyle(PhoneProminentButtonStyle(fillsWidth: true))
                    .padding(.top, PhoneMetric.tight)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PhoneMetric.loose)
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
            PhoneSectionLabel(text: PairingCopy.entry(.settingsSectionPairedMac).body)

            switch state {
            case let .reachable(mac):
                PairedMacRow(mac: mac)
                ConnectionBanner(.reachable, macName: nil)
                    .overlay(alignment: .leading) { EmptyView() }
                unpairButton

            case .neverPaired:
                // Centred, with a glyph above the headline — `i1-phone-pairing.html` §B draws
                // this one as `.pempty` rather than as a notice, and it is the only Settings
                // state the design centres. That is why the treatment lives here at the call
                // site instead of inside `PhoneMessageBlock`: the same block draws eight other
                // states, and centring them all would be applying one state's design to nine.
                // DEF-028.
                PhoneEmptyState(
                    entry: PairingCopy.entry(.settingsNeverPaired),
                    glyph: .conduit,
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
                    glyph: .warn
                )
                PhoneBlockActions(
                    entry: PairingCopy.entry(.settingsUnreadable),
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

            // The narrowing appears exactly once. `settingsNeverPaired` carries it inside its own
            // block — i1-phone-pairing.html §B states it there, under the button, with no About
            // header — while every other Settings state states it under About, as §I draws it.
            // Rendering both put the same sentence on screen twice on the surface a first-time user
            // meets first, which reads as the app repeating itself rather than as emphasis. DEF-026.
            if !stateStatesTheNarrowingItself {
                PhoneSectionLabel(text: PairingCopy.entry(.settingsSectionAbout).body)
                Text(PairingCopy.neverInstalls)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Whether this state's own block already states the narrowing.
    ///
    /// Read off the copy rather than off a list of cases, so an entry that gains `carriesNarrowing`
    /// later does not silently reintroduce the duplicate.
    private var stateStatesTheNarrowingItself: Bool {
        switch state {
        case .neverPaired: PairingCopy.entry(.settingsNeverPaired).carriesNarrowing
        default: false
        }
    }

    /// Destructive, and never the default. The consequence is named in the dialog this opens, not
    /// implied by the button.
    private var unpairButton: some View {
        Button(
            PairingCopy.entry(.settingsUnpairAction).body,
            role: .destructive,
            action: onUnpair
        )
        .buttonStyle(PhoneStandardButtonStyle())
        .padding(.top, PhoneMetric.tight)
    }
}
