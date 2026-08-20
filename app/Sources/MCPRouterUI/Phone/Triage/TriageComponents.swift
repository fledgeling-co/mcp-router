import MCPRouterKit
import SwiftUI

/// A designed empty / error / offline pane, taking plain strings.
///
/// I2 has `DiscoverMessageState`, which is the same shape but typed to `DiscoverCopy.Entry`. This
/// one takes primitives instead of being widened to a second manifest's `Entry`, because widening
/// a merged component to know about a new feature's copy type is how a shared component acquires a
/// dependency on every feature in turn.
struct PhoneMessageState: View {
    let headline: String?
    /// Named `message` rather than `body`: `body` is `View`'s own requirement, and a stored
    /// property of that name is an invalid redeclaration rather than a shadowing.
    let message: String
    var actionLabel: String?
    var icon: Icon = .list
    var tint: ColorToken = .t3
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: PhoneMetric.normal) {
            IconView(icon, size: PhoneMetric.emptyGlyph, weight: .light)
                .foregroundStyle(tint.color)
                .accessibilityHidden(true)

            if let headline {
                Text(headline)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                    .multilineTextAlignment(.center)
            }

            Text(message)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // `.cta.sec` inside `.pempty` in i3-phone-triage.html — `width:100%` inside a 12px
            // gutter. Every use of this component is a whole-pane empty or error state, so the
            // action is the pane's action and takes the pane's width. DEF-024.
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(PhoneStandardButtonStyle(fillsWidth: true))
            }
        }
        .padding(.horizontal, PhoneMetric.section)
        .frame(maxWidth: .infinity)
    }
}

/// The bucket control.
///
/// A segmented control, which `DESIGN.md` §3.6 permits precisely here: it switches views in place
/// over one list and is not primary navigation — the tab bar is. Each segment carries its own count
/// because the count is the reason to look at the segment, and every one of those counts is the
/// size of a set the user's own decisions produced.
struct BucketSegments: View {
    let buckets: TriageBuckets
    let selected: TriageBucket
    let onSelect: (TriageBucket) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TriageBucket.allCases) { bucket in
                Button { onSelect(bucket) } label: {
                    segmentLabel(bucket)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PhoneMetric.segmentPadding)
        .background(
            RoundedRectangle(cornerRadius: PhoneMetric.segmentTrackRadius, style: .continuous)
                .fill(ColorToken.f3.color)
        )
        .frame(minHeight: PhoneMetric.minimumTarget)
    }

    /// Split out of the `Button` label because the type checker times out on it inline — the
    /// "unable to type-check this expression in reasonable time" error, which is a real limit and
    /// not a reason to simplify the design.
    private func segmentLabel(_ bucket: TriageBucket) -> some View {
        let isSelected = bucket == selected
        let count = buckets.count(in: bucket)

        return HStack(spacing: PhoneMetric.tight) {
            Text(TriageCopy.entry(bucket.copyKey).body)
                .typeRole(.callout)

            if count > 0 {
                // Instrument data, so monospace — `DESIGN.md` §2. And an observed number: the size
                // of a set the user's own decisions produced.
                Text(String(count))
                    .typeRole(.caption, monospaced: true)
                    .padding(.horizontal, PhoneMetric.tight)
                    .background(
                        RoundedRectangle(cornerRadius: PhoneMetric.tight)
                            .fill(ColorToken.f2.color)
                    )
            }
        }
        .foregroundStyle((isSelected ? ColorToken.t1 : ColorToken.t2).color)
        .frame(maxWidth: .infinity, minHeight: PhoneMetric.segmentHeight)
        .background(segmentBackground(isSelected: isSelected))
        .contentShape(Rectangle())
    }

    private func segmentBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: PhoneMetric.segmentRadius, style: .continuous)
            .fill(isSelected ? ColorToken.raised.color : Color.clear)
    }
}

/// The counted commit bar.
///
/// **It does not exist when there is nothing to commit** — `TriageCommitState.absent` renders
/// nothing at all rather than a dimmed control, because with a Mac paired and nothing ticked there
/// is no act available and a disabled button implies there is one you have not earned yet. With
/// **no Mac paired** it is present and dimmed from first appearance, so the reason is readable
/// before the user ticks anything and wastes the work.
///
/// Cancel leads and the prominent action trails (`DESIGN.md` §3.4); the narrowing sentence is on it
/// verbatim.
struct TriageCommitBar: View {
    let state: TriageCommitState
    let macName: String?
    let onCommit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        if let key = state.copyKey {
            let entry = TriageCopy.entry(key).resolved([
                .count: String(state.count),
                .mac: macName ?? "your Mac"
            ])
            let isDisabled = entry.isDisabled

            VStack(alignment: .leading, spacing: PhoneMetric.snug) {
                if isDisabled {
                    // The reason sits ABOVE the dimmed control, per `DESIGN.md` §3.4 — a disabled
                    // control dims in place with a discoverable reason.
                    Text(entry.body)
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: PhoneMetric.snug) {
                    Button(TriageCopy.entry(.commit(.dismiss)).body, action: onDismiss)
                        .buttonStyle(PhoneStandardButtonStyle())
                        .frame(minHeight: PhoneMetric.minimumTarget)
                        .disabled(isDisabled)

                    Button(entry.actionLabel ?? "", action: onCommit)
                        .buttonStyle(PhoneProminentButtonStyle(fillsWidth: true))
                        .frame(minHeight: PhoneMetric.minimumTarget)
                        .disabled(isDisabled)
                }

                if !isDisabled {
                    Text(entry.body)
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if entry.carriesNarrowing {
                    Text(PairingCopy.neverInstalls)
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(PhoneMetric.loose)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorToken.panel.color)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ColorToken.lineStrong.color)
                    .frame(height: PhoneMetric.hairline)
            }
        }
    }
}

/// The inline undo bar.
///
/// **In the list, never over it**, so it cannot cover a row — and there is no confirmation dialog
/// anywhere on this surface, because the commit bar already stated what would happen and this is
/// the reversal (`DESIGN.md` §9, undo over confirm).
struct UndoBar: View {
    let text: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: PhoneMetric.normal) {
            Text(text)
                .typeRole(.callout)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(TriageCopy.entry(.commit(.undo)).body, action: onUndo)
                .typeRole(.body)
                .foregroundStyle(ColorToken.accent.color)
                .frame(minHeight: PhoneMetric.minimumTarget)
        }
        .padding(.horizontal, PhoneMetric.normal)
        .padding(.vertical, PhoneMetric.snug)
        .background(
            RoundedRectangle(cornerRadius: PhoneMetric.cardRadius, style: .continuous)
                .fill(ColorToken.raised.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhoneMetric.cardRadius, style: .continuous)
                .strokeBorder(ColorToken.lineStrong.color, lineWidth: PhoneMetric.hairline)
        )
    }
}

/// The expanded row: the full capability list, then the invocation as its evidence.
///
/// In place, under the row — never a push. Discover already owns the read-one-thing-properly path;
/// Triage's premise is comparison across rows, and a push destroys the thing being compared.
struct TriageRowDetail: View {
    let entry: RegistryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.snug) {
            Text(entry.description)
                .typeRole(.callout)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)

            Text(TriageCopy.entry(.control(.expandedHeading)).body)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t3.color)

            CapabilityPlateView(
                lines: CapabilityPlate.lines(install: entry.install, archived: entry.archived),
                invocation: CapabilityPlate.invocation(install: entry.install)
            )
        }
        .padding(.leading, PhoneMetric.minimumTarget)
        .padding(.top, PhoneMetric.tight)
    }
}
