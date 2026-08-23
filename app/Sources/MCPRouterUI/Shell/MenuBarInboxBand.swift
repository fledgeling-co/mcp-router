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
    /// **Three actions, and the asymmetry between them is the whole design.** `Review…` opens the
    /// sheet — which activates the app, because what the item runs has to be on screen when an
    /// install is pressed from *there*. `Not now` acts here, with no window and no activation, because
    /// declining costs a resend and is reversible in one press. And `Approve` acts here too, which is
    /// the one place in this product where something a remote device asked for is installed without
    /// the window opening.
    ///
    /// **That third one is a deliberate exception with three conditions, not a relaxation.**
    /// `InboxBand.Row.isApprovable` holds them — the entry resolved, the Settings preference on, and
    /// nothing the entry asks for left blank — and `ShellModel.approveFromOutside` re-checks all three
    /// rather than trusting that the button was only drawn where it should be. `plan-M20.md` §3.1
    /// records why the argument against it does not transfer: the recorded doctrine against a
    /// one-press install is `InboxArrival.swift`'s and it is about a *notification*, *"the least
    /// deliberate press available on a Mac … it appears over whatever the user was doing,
    /// unrequested."* A popover the user opened, prompted by a dot that appears only while something
    /// wants a decision, is the opposite case.
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
            .measured(
                "inbox-band", role: "banner", kind: .vstack, alignment: "leading",
                tokens: ["border": .attention, "background": .f3], type: .subheadline,
                text: band.headline
            )
        }

        /// One queued item.
        ///
        /// **The accessibility shape is M6's lesson applied to a second surface.** There, a
        /// `.combine` on a row swallowed its Review and Decline controls into the label while
        /// `AXPress` answered `.success` and did nothing — a VoiceOver user could reach every row and
        /// act on none of them. So this row declares its default action and its decline action by
        /// name, and the two named actions are what the acceptance path exercises.
        ///
        /// **A row whose entry could not be read carries no review affordance**, per the Disabled
        /// state. It is drawn as content rather than as a control, and its capability line says why.
        /// The earlier version drew the same full-width Review button on it and opened a sheet that
        /// could never install — an affordance that is a lie rather than a hole.
        private func row(for row: InboxBand.Row) -> some View {
            HStack(spacing: PopoverMetrics.gap) {
                if row.isReviewable {
                    Button { MenuBarRouter.revealInbox(itemID: row.id, on: shell) } label: {
                        rowDetail(row)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // The full name for a truncated one, to pointer and to VoiceOver alike —
                    // `DESIGN.md` §5's overflow rule met in place, since a popover has no inspector.
                    .help(row.title)
                    .accessibilityValue(row.title)
                } else {
                    rowDetail(row)
                        .help(row.title)
                        .accessibilityValue(row.title)
                }

                controls(for: row)
            }
            .padding(.horizontal, PopoverMetrics.rowPadding)
            .frame(minHeight: PopoverMetrics.inboxRow)
            // **The row's id is in the measured id, and it has to be.** `MeasureTree.assemble` keys
            // nodes by path and resolves a collision with `uniquingKeysWith: { first, _ in first }`, so
            // two rows whose controls carry the same id at the same path drop the second row's
            // controls silently — measured here: a two-item queue dumped three controls, not six, and
            // nothing said so. Scoping the row rather than the controls keeps the control ids stable
            // for `popover.pairing.tsv` while making every path unique.
            .measured(
                "inbox-row-\(row.id)", role: "table-row", kind: .hstack,
                type: .callout, text: row.title
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(row.title), \(row.provenance)")
            .accessibilityActions {
                // Named only where it does something. A VoiceOver action that opens a review which
                // cannot install is the same lie as the button, said to a user who cannot see that
                // the button is gone — and the same is true of an approval that could not construct
                // a declaration.
                if row.isApprovable {
                    Button(InboxCopy.Band.approveAction) { approve(row) }
                }
                if row.isReviewable {
                    Button(InboxCopy.reviewAction) {
                        MenuBarRouter.revealInbox(itemID: row.id, on: shell)
                    }
                }
                Button(InboxCopy.Band.declineAction) { shell.declineFromOutside(itemID: row.id) }
            }
        }

        /// The row's controls, in the mock's order: `Approve`, `Review…`, `Not now`.
        ///
        /// Three separate `Button`s rather than a menu or a segmented control, because
        /// `spec-M20.md`'s acceptance line is that *"a structure dump of the popover shows three
        /// separately focusable controls in the queued-item band"* — a control that has to be opened
        /// before its options are reachable is one focusable thing, not three.
        ///
        /// `Approve` is absent rather than disabled where the row is not approvable, which is the
        /// same rule the row's own `Review` affordance follows: this band has no room for a
        /// disabled-reason line beside a button, and `DESIGN.md`'s Disabled state asks for the reason
        /// to be readable where the control is. A row that cannot be approved still carries
        /// `Review…`, which is where the requirement fields and the full statement are.
        ///
        /// **`Approve` leads but is not accent-filled, and that is a declared divergence from the
        /// mock rather than an oversight.** The mock draws it `btn primary` (`:1486`) and
        /// `plan-M20.md` step 13 says *"(prominent)"*. `ProminentButtonStyle` here would put between
        /// two and four accent-filled controls in the smallest surface in the app — the band caps at
        /// `MenuBarPresentation.inboxBandLimit` rows and the footer's `Open MCP Router` already holds
        /// this view's prominent slot — and `DESIGN.md:212` binds that budget to a live accessibility
        /// deviation rather than to taste: `--on-accent` on `--accent` is a recorded contrast
        /// shortfall that `LightAppearanceTests.darkOnAccentDeviationIsPinned` measures every run,
        /// and *"exposure is bounded by §3 rule 4 — one prominent accent-filled action per view."*
        /// The same passage names the way out: *"that control is distinguished by shape and position
        /// too, never by colour alone."* So the emphasis is the mock's own leading position, and the
        /// fill divergence is declared in `planning/fidelity/popover.pairing.tsv` where the gate
        /// reads it.
        @ViewBuilder
        private func controls(for row: InboxBand.Row) -> some View {
            if row.isApprovable {
                Button(InboxCopy.Band.approveAction) { approve(row) }
                    .buttonStyle(StandardButtonStyle())
                    .measured(
                        "inbox-approve", role: "primary-action", kind: .leaf,
                        type: .body, text: InboxCopy.Band.approveAction
                    )
            }
            if row.isReviewable {
                Button(InboxCopy.reviewAction) { MenuBarRouter.revealInbox(itemID: row.id, on: shell) }
                    .buttonStyle(StandardButtonStyle())
                    .measured(
                        "inbox-review", role: "state-action", kind: .leaf,
                        type: .body, text: InboxCopy.reviewAction
                    )
            }
            Button(InboxCopy.Band.declineAction) { shell.declineFromOutside(itemID: row.id) }
                .buttonStyle(StandardButtonStyle())
                .measured(
                    "inbox-decline", role: "state-action", kind: .leaf,
                    type: .body, text: InboxCopy.Band.declineAction
                )
        }

        /// Approving is `async` on the model and a `Button` action is not, so it crosses a task
        /// boundary here. `MenuBarRouter` is not involved: nothing is revealed and nothing activates.
        private func approve(_ row: InboxBand.Row) {
            Task { await shell.approveFromOutside(itemID: row.id) }
        }

        /// The three lines of a row. Shared so the reviewable and unreviewable shapes cannot say
        /// different things about the same item.
        private func rowDetail(_ row: InboxBand.Row) -> some View {
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
