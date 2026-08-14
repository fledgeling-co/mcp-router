import MCPRouterKit
import SwiftUI

/// One Triage row: **two targets, each doing exactly one thing.**
///
/// The leading checkbox selects. The meta block expands. A row that both selects and expands from
/// one tap makes the more consequential act — putting something in front of a human on another
/// machine — an accident of where the thumb landed. Both targets meet the 44pt floor.
///
/// The capability line is the second of the two prototype bugs inverted: it is **always visible**,
/// it **wraps rather than truncates**, and the thing that truncates instead is the entry *name*,
/// which is what `DESIGN.md` §5's Overflow rule actually asks for — the long *value* truncates and
/// its full form is one tap away.
struct TriageRow: View {
    let entry: RegistryEntry
    let bucket: TriageBucket
    let isSelected: Bool
    let isExpanded: Bool
    let onToggleSelection: () -> Void
    let onToggleExpansion: () -> Void
    let onRestore: () -> Void

    private var summary: CapabilitySummary.Resolved {
        CapabilitySummary.resolve(for: entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.tight) {
            HStack(alignment: .top, spacing: PhoneMetric.snug) {
                leading
                meta
            }

            if isExpanded {
                TriageRowDetail(entry: entry)
            }

            if bucket == .dismissed {
                Button(TriageCopy.entry(.control(.restore)).body, action: onRestore)
                    .buttonStyle(PhoneStandardButtonStyle())
                    .frame(minHeight: PhoneMetric.minimumTarget)
                    .padding(.leading, PhoneMetric.section + PhoneMetric.snug)
            }
        }
        .padding(.vertical, PhoneMetric.tight)
    }

    /// Target one of two — or, in a bucket with no batch act, the entry's tile instead. A checkbox
    /// in a bucket where nothing can be selected is an affordance that does nothing.
    @ViewBuilder
    private var leading: some View {
        if bucket.isSelectable {
            Button(action: onToggleSelection) {
                TriageCheckbox(isSelected: isSelected)
                    // **The frame was already 44pt; the target was not.** `TriageCheckbox` ends in a
                    // 44pt frame around its 22pt box, so the row laid out correctly — but a
                    // Button's hit region defaults to its label's drawn content, which is the 22pt
                    // rounded rectangle. `TriageSurfaceIOSTests.testRowTargetsMeetTheFloor` walks
                    // the accessibility tree and measured exactly that: 22pt against a 44pt floor
                    // (A3, A27), on the primary act of the whole surface.
                    //
                    // `contentShape` is what makes the transparent half of the frame tappable. It
                    // is the failure worth remembering: the geometry looked right in every
                    // screenshot, and only a measurement of the *target* could see it.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!summary.isSelectable)
            .accessibilityLabel(Text(entry.displayName))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        } else {
            IconView(entry.install?.type == .stdio ? .bolt : .conduit)
                .foregroundStyle(ColorToken.t3.color)
                .frame(width: PhoneMetric.minimumTarget, height: PhoneMetric.minimumTarget)
                .accessibilityHidden(true)
        }
    }

    /// Target two of two.
    private var meta: some View {
        Button(action: onToggleExpansion) {
            VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                Text(entry.displayName)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                    // The NAME is what truncates — one line, tail. `DESIGN.md` §5 Overflow.
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(TriagePresentation.provenance(for: entry))
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .lineLimit(1)
                    .truncationMode(.tail)

                CapabilityLine(summary: summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: PhoneMetric.minimumTarget, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
    }
}

/// The 22pt box inside a 44pt target: the control is quiet and the target is not.
struct TriageCheckbox: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: PhoneMetric.checkboxRadius, style: .continuous)
            .fill(isSelected ? ColorToken.accent.color : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: PhoneMetric.checkboxRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? ColorToken.accent.color : ColorToken.lineStrong.color,
                        lineWidth: PhoneMetric.checkboxBorder
                    )
            }
            .overlay {
                if isSelected {
                    IconView(.check, size: PhoneMetric.checkGlyph)
                        .foregroundStyle(ColorToken.onAccent.color)
                }
            }
            .frame(width: PhoneMetric.checkbox, height: PhoneMetric.checkbox)
            .frame(width: PhoneMetric.minimumTarget, height: PhoneMetric.minimumTarget)
    }
}

/// The row's one security line.
///
/// **No `lineLimit`, and that omission is the fix**, not an oversight. `.fixedSize(vertical:)` lets
/// it wrap and the row grows. Colour is `--attn` or a label tier and never anything else: `--live`
/// means "a child process is running" and `--fail` means "failed or tripped", and a registry entry
/// nobody has installed is neither. The glyph and the words carry the same signal, so the line reads
/// correctly with no colour at all.
struct CapabilityLine: View {
    let summary: CapabilitySummary.Resolved

    var body: some View {
        HStack(alignment: .top, spacing: PhoneMetric.tight) {
            IconView(summary.wantsAttention ? .warn : .check, size: PhoneMetric.clauseGlyph)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(TriagePresentation.summaryText(summary))
                .typeRole(.subheadline)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tint: Color {
        summary.wantsAttention ? ColorToken.attention.color : ColorToken.t2.color
    }
}
