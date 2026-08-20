#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// How long the router has been recording, drawn at its real length.
    ///
    /// **The app's second subject-mined element**, which `DESIGN.md` §10 asks any new surface to add.
    /// The question Cleanup exists to answer is *how much do we actually know*, and the answer is
    /// dominated by one number nobody looks at: "never used" over 41 days is evidence, over two hours
    /// it is nothing, and a table showing only the verdict renders those two identically.
    ///
    /// The real figure sits beside the bar in mono, so nothing depends on reading the drawing — the
    /// bar is the shape of the answer and the number is the answer. Beyond the 30-day reference it
    /// pegs full rather than overflowing its own track.
    struct CleanupObservationTrack: View {
        let window: CleanupPresentation.Window?

        var body: some View {
            HStack(spacing: M7BoardMetrics.gap) {
                track
                Text(label)
                    .typeRole(.caption)
                    .monospaced()
                    .foregroundStyle(ColorToken.t2.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Observation window: \(label)")
        }

        private var label: String {
            guard let window else { return "window unknown" }
            return "\(window.days)d recorded"
        }

        private var fill: Color {
            // `--attn` at its own meaning — "wants a human decision" — and only for the weak window,
            // which is the same condition the banner reports. One condition, two renderings.
            guard let window, window.isWeak else { return ColorToken.t3.color }
            return ColorToken.attention.color
        }

        private var track: some View {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ColorToken.f2.color)
                    // Drawn only when there is a window to draw. A bar filled to zero for an
                    // unknown window is the same substitution as printing "0 days": the shape
                    // states a measurement, and an empty one states that nothing was recorded,
                    // which is a different claim from "the router did not say". The mono label
                    // beside it already reads "window unknown"; leaving the fill out keeps the two
                    // saying the same thing instead of the drawing contradicting the text.
                    if let window {
                        Capsule()
                            .fill(fill)
                            .frame(
                                width: proxy.size.width * CleanupPresentation.trackFraction(
                                    days: window.days
                                )
                            )
                    }
                }
            }
            .frame(width: M7BoardMetrics.trackWidth, height: M7BoardMetrics.trackHeight)
        }
    }

    /// One proposed row: what it is, and the observation that proposed it.
    ///
    /// No trash metaphor anywhere — not in the icon, not in the words. A never-used server was never
    /// deleted, and nothing here is rubbish awaiting disposal.
    struct CleanupBoardRow: View {
        let candidate: CleanupBoardModel.Candidate
        let isSelected: Bool
        /// What the row's own actions do. Optional because the skeleton and the previews render a
        /// row with nothing behind it, and a row that had to invent a closure to be drawn would be
        /// drawing a control that does nothing — the thing §3.4 forbids.
        var inspect: (() -> Void)?
        var remove: (() -> Void)?
        /// What `Read first…` does. Separate from `inspect` because it is not a quieter inspect: it
        /// opens the one sheet on this board that asks for nothing, and the row that offers it
        /// offers neither of the other two.
        var readFirst: (() -> Void)?

        var body: some View {
            HStack(spacing: M7BoardMetrics.rowPadding) {
                RoundedRectangle(cornerRadius: M7BoardMetrics.tileRadius, style: .continuous)
                    .fill(ColorToken.f2.color)
                    .frame(width: M7BoardMetrics.tile, height: M7BoardMetrics.tile)
                    .overlay {
                        IconView(candidate.kind == .server ? .servers : .skills, size: TypeToken.callout.size)
                            // The mock's leading dot carries the same one bit: `dot f` for a row
                            // whose marketplace moved, `dot idle` for every other. Here the leading
                            // element is the kind tile, so the tint lands on it.
                            .foregroundStyle(
                                candidate.provenance == nil
                                    ? ColorToken.t3.color
                                    : ColorToken.fail.color
                            )
                    }

                VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                    Text(candidate.name)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t1.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(candidate.detail)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: M7BoardMetrics.nameColumn, alignment: .leading)

                Text(candidate.kind.label)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t2.color)
                    .frame(width: M7BoardMetrics.kindColumn, alignment: .leading)

                reason

                Spacer(minLength: 0)

                actions
            }
            .padding(.horizontal, M7BoardMetrics.rowPadding)
            .frame(height: M7BoardMetrics.rowHeight)
            .selectionFill(isSelected)
            // **Behind the selection fill, not in front of it.** The mock sets the tint as an
            // inline style, which in CSS beats the selected class — so a selected flagged row there
            // reads as unselected. Painting it furthest back keeps both legible: the tint marks the
            // row at rest, and selection still wins when the row is the one being acted on. The row
            // is marked three other ways regardless, so nothing is lost when selection covers it.
            .background {
                if candidate.provenance != nil {
                    RoundedRectangle(
                        cornerRadius: MetricToken.selectionRadius.leadingScalar,
                        style: .continuous
                    )
                    .fill(ColorToken.fail.color.opacity(M7BoardMetrics.flaggedRowTint))
                    .padding(.horizontal, MetricToken.selectionInset.leadingScalar)
                }
            }
            // **`.contain`, not `.combine`.** Combining flattens the row's buttons into the label
            // and leaves nothing for VoiceOver or a UI test to press — the same trap the campaign
            // already recorded for a time-limited undo inside an `aria-live` region, where the only
            // people who could reach the control were mouse users.
            .accessibilityElement(children: .contain)
            // Both sentences, and the candidacy reason first. The tinted row shows the provenance
            // note in place of the reason because the column has room for one line; a label read
            // aloud has room for both, and dropping "installed nowhere" would leave a listener
            // unable to say why the row is on a list of never-used things at all.
            .accessibilityLabel(accessibilityLabel)
        }

        private var accessibilityLabel: String {
            let head = "\(candidate.name), \(candidate.kind.label). \(candidate.reason)"
            guard let provenance = candidate.provenance else { return head }
            return "\(head) \(provenance)"
        }

        /// Why the row is here — or, on a flagged row, the thing that matters more.
        ///
        /// `prototype.html:958` substitutes rather than appends: the column fits one line, and a
        /// marketplace that moved outranks "installed 4mo ago, never invoked" for the one decision
        /// this row exists to inform. The candidacy reason is not lost — it leads the accessibility
        /// label, and the inspector prints it under "Why it is here".
        private var reason: some View {
            HStack(spacing: M7BoardMetrics.labelGap) {
                if candidate.provenance != nil {
                    IconView(.warn, size: TypeToken.caption.size)
                        .foregroundStyle(ColorToken.fail.color)
                }
                Text(candidate.provenance ?? candidate.reason)
                    .typeRole(.caption)
                    .foregroundStyle(
                        candidate.provenance == nil ? ColorToken.t2.color : ColorToken.fail.color
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: M7BoardMetrics.reasonColumn, alignment: .leading)
        }

        /// The row's own actions, which the design draws on every row and the build drew on none.
        ///
        /// `prototype.html:950` puts `Inspect` and `Remove` in a 150px trailing column, and
        /// `prototype.html:961` gives a flagged skill `Read first…` **in their place** rather than
        /// beside them. The substitution is the point: a skill whose marketplace moved since the
        /// router first saw it is the one candidate where "never invoked" is the least interesting
        /// thing about it, and leaving Remove on that row puts a removal one click from a fact
        /// nobody has read yet.
        ///
        /// Removal is server-only, dimmed in place for a skill with its reason, exactly as
        /// `CleanupInspector.actions` already does it: there is no code path from this board to a
        /// skill write because the control API has none. The reason travels as an accessibility
        /// hint as well as a tooltip, because a reason only a mouse can reach is not a reason.
        ///
        /// No `@ViewBuilder`: the body is one `HStack` expression, and `swiftformat`'s
        /// `redundantViewBuilder` rule rejects the attribute where the builder does nothing —
        /// the `if`s are inside the stack, not at the top level.
        private var actions: some View {
            HStack(spacing: M7BoardMetrics.labelGap) {
                if candidate.provenance != nil {
                    // Prominent, and it is the one place on this pane that earns it. §3.4 allows a
                    // single prominent action per view and forbids a destructive one as the
                    // default; this action removes nothing, and it is the only thing the row now
                    // offers, so there is nothing for it to compete with.
                    if let readFirst {
                        Button("Read first…", action: readFirst)
                            .buttonStyle(ProminentButtonStyle())
                            .controlSize(.small)
                    }
                } else {
                    if let inspect {
                        Button("Inspect", action: inspect)
                            .buttonStyle(StandardButtonStyle())
                            .controlSize(.small)
                    }
                    if let remove {
                        Button("Remove…", action: remove)
                            .buttonStyle(StandardButtonStyle())
                            .controlSize(.small)
                            .disabled(candidate.kind == .skill)
                            .help(candidate.kind == .skill ? CheckCopy.skillRemoveDisabled : "")
                            .accessibilityHint(
                                candidate.kind == .skill ? CheckCopy.skillRemoveDisabled : ""
                            )
                    }
                }
            }
            .frame(width: M7BoardMetrics.actionColumn, alignment: .trailing)
        }
    }
#endif
