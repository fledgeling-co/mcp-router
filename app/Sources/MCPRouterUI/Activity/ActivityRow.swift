#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The log's column geometry, composed from `MetricToken` and from nothing else.
    ///
    /// `SWIFT_PRACTICES.md` §5 forbids hardcoding a size, and `no-raw-design-values.sh` is extended
    /// by this item to scan this directory under the shell's geometry rule — so every width below is
    /// a sum or an integer multiple of a documented value, the same composition idiom
    /// `StateContainer.swift` already uses (`selectionRadius * 3`, `selectionInset * 3`).
    ///
    /// They live in one enum rather than beside each `Text`, because the header, the populated row
    /// and the skeleton row must agree to the point: a header that drifts a few points from its
    /// column turns a scannable gutter into five labels that nearly line up.
    enum ActivityColumn {
        /// The failure dot. Small enough to read as a mark rather than a control.
        static let mark = MetricToken.selectionInset.leadingScalar + MetricToken.focusRing.leadingScalar
        /// `now`, `22s`, `6m` — never wider than three characters of monospace.
        static let when = MetricToken.tableRows.leadingScalar + MetricToken.controlMini.leadingScalar
        static let server = MetricToken.controlExtraLarge.leadingScalar * 3
        static let project = MetricToken.sidebar.leadingScalar / 2
        /// The pid, which is what tells two agent windows apart at a glance. The client name and
        /// the full form are in the inspector — the brief asks the row to show the session, not to
        /// spell it out.
        static let session = MetricToken.controlExtraLarge.leadingScalar + MetricToken.controlMini
            .leadingScalar
        /// Wide enough for a four-digit millisecond value and the cold mark beside it.
        static let took = MetricToken.controlExtraLarge.leadingScalar
            + MetricToken.controlRegular.leadingScalar
        /// The one height every row in this list is drawn at — populated, header-adjacent and
        /// skeleton alike.
        ///
        /// Named rather than repeated, because `DESIGN.md` §5's rule is that the row height never
        /// moves and the skeleton matches the real geometry exactly. Two independent
        /// `.frame(height: MetricToken.tableRows...)` expressions satisfy that by coincidence and
        /// stop satisfying it the moment one is edited; one constant, asserted to be the only
        /// height either draws at, cannot drift apart.
        static let rowHeight = MetricToken.tableRows.leadingScalar

        /// The gutter between columns, and the row's own leading inset.
        static let gutter = MetricToken.selectionRadius.leadingScalar
        static let inset = MetricToken.selectionRadius.leadingScalar * 2
    }

    /// One call, on one line, at a height that never moves.
    ///
    /// The fixed frame is the assertion rather than a style choice. `DESIGN.md` §5's overflow rule
    /// is "long names truncate with the full value in the inspector; rows never change height", and
    /// without the frame a long tool name wraps and the row grows — which is exactly the failure the
    /// rule exists to rule out. The value is `MetricToken.tableRows`, `DESIGN.md` §2's documented
    /// height for dense lists, and it is the same expression the skeleton row uses so nothing jumps
    /// when the data lands.
    struct ActivityRow: View {
        let record: CallRecord
        let age: String
        let isSelected: Bool

        var body: some View {
            HStack(spacing: ActivityColumn.gutter) {
                mark
                Text(text(.when))
                    .typeRole(.subheadline, monospaced: true)
                    .foregroundStyle(ColorToken.t3.color)
                    .frame(width: ActivityColumn.when, alignment: .leading)
                Text(text(.server))
                    .typeRole(.callout)
                    .foregroundStyle(isSelected ? ColorToken.accent.color : ColorToken.t1.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: ActivityColumn.server, alignment: .leading)
                // Not monospace. §2 reserves the instrument voice for "numerals, counts,
                // durations, error codes, status subtitles"; a tool name and a project name are
                // identifiers and are on none of those lists, and the column is fixed-width anyway
                // so the gutter is aligned without borrowing the voice.
                Text(text(.tool))
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t2.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(text(.project))
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: ActivityColumn.project, alignment: .leading)
                // A numeral, so it keeps the instrument voice.
                Text(text(.session))
                    .typeRole(.subheadline, monospaced: true)
                    .foregroundStyle(ColorToken.t3.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: ActivityColumn.session, alignment: .leading)
                took
            }
            .padding(.horizontal, ActivityColumn.inset)
            .frame(height: ActivityColumn.rowHeight)
            .frame(maxWidth: .infinity)
            .background(isSelected ? ColorToken.f1.color : Color.clear)
            .contentShape(Rectangle())
            // The untruncated values, always. A screen reader is never handed the truncation, and
            // this is what B6 measures against the rendered row.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }

        /// Only a failure is marked. `--live` means "a child process is running" (§2), and a call
        /// that has finished is not a running process — so a successful row carries no indicator
        /// colour at all, which also sends the eye to the rows that went wrong.
        private var mark: some View {
            Circle()
                .fill(record.ok ? Color.clear : ColorToken.fail.color)
                .frame(width: ActivityColumn.mark, height: ActivityColumn.mark)
        }

        /// The duration, with the cold mark where the call is what spawned the server.
        ///
        /// The mark is a drawn symbol in `t2` — not the snowflake character, which §4 forbids, and not
        /// `--accent`, which
        /// §2 reserves for selection, focus and the one primary action and which here would compete
        /// with the selected row.
        private var took: some View {
            HStack(spacing: MetricToken.selectionInset.leadingScalar) {
                if record.cold {
                    IconView(.frost, size: TypeToken.caption.size, weight: .medium)
                        .foregroundStyle(ColorToken.t2.color)
                }
                Text(text(.took))
                    .typeRole(.subheadline, monospaced: true)
                    .foregroundStyle(record.cold ? ColorToken.t2.color : ColorToken.t3.color)
            }
            .frame(width: ActivityColumn.took, alignment: .trailing)
        }

        /// Every visible string goes through `ActivityRowField`, so no text can reach this row
        /// without a named `CallRecord` source. That indirection is what gives B4 an oracle: the
        /// mapping's field set is compared against the table in the spec, which this code did not
        /// write.
        private func text(_ field: ActivityRowField) -> String {
            field.text(for: record, age: age) ?? ""
        }

        /// Outcome first, because it is the thing a listener most needs and the thing colour alone
        /// would otherwise be carrying (§7's `differentiateWithoutColor`).
        var accessibilityLabel: String {
            var parts: [String] = []
            parts.append(record.ok ? "succeeded" : "failed")
            parts.append(record.tool)
            parts.append("on \(record.server)")
            parts.append("in \(projectLabel(cwd: record.cwd, project: record.project))")
            parts.append(ActivityCopy.sessionFull(pid: record.pid, client: record.client))
            parts.append(ActivityCopy.duration(ms: record.ms))
            parts.append(ActivityCopy.startDescription(cold: record.cold))
            parts.append(age)
            if let err = record.err, !err.isEmpty { parts.append(err) }
            return parts.joined(separator: ", ")
        }
    }

    /// The column header. Sentence case, secondary colour, and drawn during loading too — it is not
    /// data, and hiding it would make the board reflow when rows land.
    struct ActivityColumnHeader: View {
        var body: some View {
            HStack(spacing: ActivityColumn.gutter) {
                Spacer().frame(width: ActivityColumn.mark)
                header(ActivityCopy.columns[0], width: ActivityColumn.when)
                header(ActivityCopy.columns[1], width: ActivityColumn.server)
                Text(ActivityCopy.columns[2])
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                header(ActivityCopy.columns[3], width: ActivityColumn.project)
                header(ActivityCopy.columns[4], width: ActivityColumn.session)
                Text(ActivityCopy.columns[5])
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .frame(width: ActivityColumn.took, alignment: .trailing)
            }
            .padding(.horizontal, ActivityColumn.inset)
            .padding(.vertical, MetricToken.selectionInset.leadingScalar)
            .overlay(alignment: .bottom) {
                // The platform hairline, drawn by the kit rather than by a fractional height this
                // file would have to choose. Tinted to the document's own divider token.
                Divider().overlay(ColorToken.line.color)
            }
            .accessibilityHidden(true)
        }

        private func header(_ text: String, width: Double) -> some View {
            Text(text)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t3.color)
                .frame(width: width, alignment: .leading)
        }
    }

    /// The loading state: the same row, at the same height, with nothing in it.
    ///
    /// `SkeletonRows` in `StateContainer.swift` is the *servers* board's skeleton, built around a
    /// 48pt breaker housing. This is the log's, and the height it reads is the same token
    /// `ActivityRow` reads — which is what B5 compares, and what stops the board jumping when the
    /// backfill lands.
    struct ActivitySkeletonRows: View {
        let count: Int

        init(count: Int = 8) {
            self.count = count
        }

        var body: some View {
            VStack(spacing: 0) {
                ForEach(0 ..< count, id: \.self) { index in
                    HStack(spacing: ActivityColumn.gutter) {
                        Spacer().frame(width: ActivityColumn.mark)
                        bar(width: ActivityColumn.when)
                        // Two widths rather than one, so the skeleton reads as a list of different
                        // things rather than as a loading bar drawn eight times.
                        bar(
                            width: index.isMultiple(of: 2)
                                ? ActivityColumn.server
                                : MetricToken.controlExtraLarge.leadingScalar * 2
                        )
                        bar(width: nil)
                        bar(width: ActivityColumn.project)
                        bar(width: ActivityColumn.session)
                        bar(width: ActivityColumn.took)
                    }
                    .padding(.horizontal, ActivityColumn.inset)
                    .frame(height: ActivityColumn.rowHeight)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading the call log")
        }

        private func bar(width: Double?) -> some View {
            RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar)
                .fill(ColorToken.f2.color)
                .frame(width: width.map { CGFloat($0) }, height: TypeToken.caption.size)
                .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        }
    }
#endif
