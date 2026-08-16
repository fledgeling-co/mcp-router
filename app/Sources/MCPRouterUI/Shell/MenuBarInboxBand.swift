#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The queue, in the menu bar.
    ///
    /// `D-m6-d`: the popover is the app's most visible surface and the one place a queued item
    /// should appear without opening the window. It renders `PopoverContent.InboxZone` and decides
    /// nothing — the ordering, the cap, the overflow arithmetic and every sentence were settled in
    /// `MCPRouterKit`, where a test calls them.
    ///
    /// **Two actions, and the asymmetry between them is the whole design.** Pressing a row opens the
    /// *review* — which activates the app, because the sheet is a window and what the item runs has
    /// to be on screen when the install is pressed. `Decline` acts here, with no window and no
    /// activation, because declining costs a resend and is reversible in one press.
    struct MenuBarInboxBand: View {
        let zone: PopoverContent.InboxZone
        @Bindable var shell: ShellModel

        var body: some View {
            switch zone {
            case let .band(band):
                bandView(band)
            case let .unreadable(message):
                // The queue itself could not be read. Its own row rather than an empty band: an
                // empty band claims nothing is waiting, which is exactly the claim a failed read
                // gives nobody the right to make.
                noticeRow(title: message.title, detail: message.detail, tint: ColorToken.fail)
            }
        }

        // MARK: - The band

        private func bandView(_ band: InboxBand) -> some View {
            VStack(alignment: .leading, spacing: PopoverMetrics.gap) {
                Text(band.headline)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .padding(.horizontal, PopoverMetrics.rowPadding)
                VStack(spacing: 0) {
                    ForEach(band.rows) { row(for: $0) }
                    if band.overflow > 0 { overflowRow(band.overflow) }
                }
                .background(
                    RoundedRectangle(cornerRadius: PopoverMetrics.childRadius, style: .continuous)
                        .fill(ColorToken.f3.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverMetrics.childRadius, style: .continuous)
                        // `--attn` because a queued item is asking for a human decision, which is
                        // the only thing this token means (§2). Never as decoration.
                        .strokeBorder(
                            ColorToken.attention.color.opacity(PopoverMetrics.bandEdgeAlpha),
                            lineWidth: PopoverMetrics.hairline
                        )
                )
                if let report = band.report { reportRow(report) }
            }
        }

        /// One queued item.
        ///
        /// **The accessibility shape is M6's lesson applied to a second surface.** There, a
        /// `.combine` on a row swallowed its Review and Decline controls into the label while
        /// `AXPress` answered `.success` and did nothing — a VoiceOver user could reach every row and
        /// act on none of them. So this row declares its default action and its decline action by
        /// name, and the two named actions are what the acceptance path exercises.
        private func row(for row: InboxBand.Row) -> some View {
            HStack(spacing: PopoverMetrics.gap) {
                Button { MenuBarRouter.revealInbox(itemID: row.id, on: shell) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.title)
                            .typeRole(.callout)
                            .foregroundStyle(ColorToken.t1.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(row.capability ?? InboxCopy.Band.partialCapability)
                            .typeRole(.subheadline)
                            .foregroundStyle(ColorToken.t2.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(row.provenance)
                            .typeRole(.caption, monospaced: true)
                            .foregroundStyle(ColorToken.t3.color)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The full name for a truncated one, to pointer and to VoiceOver alike — `DESIGN.md`
                // §5's overflow rule met in place, since a popover has no inspector.
                .help(row.title)
                .accessibilityValue(row.title)

                Button(InboxCopy.declineAction) { shell.declineFromOutside(itemID: row.id) }
                    .buttonStyle(StandardButtonStyle())
            }
            .padding(.horizontal, PopoverMetrics.rowPadding)
            .frame(minHeight: PopoverMetrics.inboxRow)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(row.title), \(row.provenance)")
            .accessibilityAction(named: Text(InboxCopy.reviewAction)) {
                MenuBarRouter.revealInbox(itemID: row.id, on: shell)
            }
            .accessibilityAction(named: Text(InboxCopy.declineAction)) {
                shell.declineFromOutside(itemID: row.id)
            }
        }

        /// Everything past the cap. It names the remainder and where the rest of them are; the
        /// band's header line already states the true total, so nothing is hidden by the cap.
        private func overflowRow(_ remaining: Int) -> some View {
            Button { MenuBarRouter.openInbox(on: shell) } label: {
                HStack(spacing: PopoverMetrics.gap) {
                    Text(InboxCopy.Band.overflow(remaining))
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t2.color)
                    Spacer(minLength: 0)
                    IconView(.chev, size: TypeToken.caption.size)
                        .foregroundStyle(ColorToken.t4.color)
                }
                .padding(.horizontal, PopoverMetrics.rowPadding)
                .frame(height: PopoverMetrics.bandRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        /// The in-place report. §5: macOS does not toast a click.
        private func reportRow(_ report: InboxBand.Report) -> some View {
            HStack(spacing: PopoverMetrics.gap) {
                Text(report.sentence)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t2.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // Drawn only where it would do what it says. An accept is reported and not offered
                // as reversible, because removing a server is Servers' own undoable operation.
                if report.isUndoable {
                    Button(InboxCopy.undoAction) { shell.inboxBoard.undoLastDisposition() }
                        .buttonStyle(StandardButtonStyle())
                }
            }
            .padding(.horizontal, PopoverMetrics.rowPadding)
        }

        private func noticeRow(title: String, detail: String, tint: ColorToken) -> some View {
            HStack(alignment: .top, spacing: PopoverMetrics.gap) {
                IconView(.warn, size: TypeToken.callout.size)
                    .foregroundStyle(tint.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t1.color)
                    Text(detail)
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(PopoverMetrics.rowPadding)
            .background(
                RoundedRectangle(cornerRadius: PopoverMetrics.childRadius, style: .continuous)
                    .fill(ColorToken.f3.color)
            )
        }
    }
#endif
