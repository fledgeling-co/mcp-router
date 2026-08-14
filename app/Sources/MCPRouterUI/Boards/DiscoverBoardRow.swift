#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// One registry entry.
    ///
    /// Every branch comes from `RegistryPresentation`, which is testable without a host. This file
    /// draws answers and decides nothing — including the two decisions it would be most tempting to
    /// make here: what the date means, and whether there is a number to show.
    struct DiscoverBoardRow: View {
        let entry: RegistryEntry
        let isSelected: Bool
        /// Opening the detail, as an action the row itself offers.
        ///
        /// The board also attaches tap gestures, but a gesture is invisible to the accessibility
        /// plane: the row published no `AXPress`, so the only way to reach the detail sheet was a
        /// mouse. That is a real defect rather than a testing inconvenience — the sheet is where a
        /// user learns what a server will run before they run it, and it was unreachable by
        /// keyboard-and-VoiceOver alone. Found by driving the rendered board over AX.
        let onOpen: () -> Void

        private var dateCell: RegistryPresentation.DateCell? {
            RegistryPresentation.dateCell(for: entry)
        }

        private var figure: RegistryPresentation.Figure? {
            RegistryPresentation.figure(for: entry)
        }

        var body: some View {
            HStack(spacing: DiscoverBoardMetrics.rowPadding) {
                RegistryTile(
                    entry: entry,
                    side: DiscoverBoardMetrics.tile,
                    radius: DiscoverBoardMetrics.tileRadius
                )

                VStack(alignment: .leading, spacing: DiscoverBoardMetrics.hairline) {
                    Text(RegistryPresentation.sanitized(entry.displayName, cap: 80))
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t1.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    secondLine
                }
                .frame(width: DiscoverBoardMetrics.nameColumn, alignment: .leading)

                ProvenanceMark(entry: entry)
                    .frame(width: DiscoverBoardMetrics.markColumn, alignment: .leading)

                // Nothing at all when the row carries neither figure. A dash or a zero here would
                // both be claims: that the number was measured, and that it came out as none.
                Group {
                    if let figure {
                        Text(figure.text)
                            .typeRole(.callout, monospaced: true)
                            .foregroundStyle(ColorToken.t2.color)
                            .lineLimit(1)
                    }
                }
                .frame(width: DiscoverBoardMetrics.figureColumn, alignment: .leading)

                Group {
                    if let dateCell {
                        Text(dateCell.text)
                            .typeRole(.caption)
                            .foregroundStyle(ColorToken.t3.color)
                            .lineLimit(1)
                    }
                }
                .frame(width: DiscoverBoardMetrics.dateColumn, alignment: .leading)

                Spacer(minLength: 0)

                stateCell
                    .frame(width: DiscoverBoardMetrics.stateColumn, alignment: .trailing)
            }
            .padding(.horizontal, DiscoverBoardMetrics.rowPadding)
            // Fixed in every state, so the skeleton and the populated row are the same size and the
            // board does not jump when data lands (§5, Overflow).
            .frame(height: DiscoverBoardMetrics.rowHeight)
            .selectionFill(isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            // **The default action, so the row presses like the button it says it is.**
            //
            // Measured against the running app on 2026-08-15: with only the named action below, the
            // row published `["AXScrollToVisible", "Name:Show details…"]` and **no `AXPress`** — so
            // `.isButton` was a trait the element could not honour, and anything that presses a
            // button (assistive technology, automation, the acceptance gate itself) got nothing
            // while the trait promised otherwise. `AXUIElementPerformAction(kAXPressAction)` simply
            // failed; a gate keyed on its return code would have called that a pass.
            //
            // Both are kept because they do different jobs: this one makes the button pressable,
            // and the named one below makes the announcement say what pressing it *does*.
            .accessibilityAction { onOpen() }
            // Named for what it does, so the announcement is "show details" rather than the
            // default "press" — and it never says "install", because it does not.
            .accessibilityAction(named: "Show details") { onOpen() }
        }

        /// `name` under `displayName` where they differ — or the archived warning, which outranks it.
        @ViewBuilder
        private var secondLine: some View {
            if let archived = RegistryPresentation.archivedNote(for: entry) {
                // `--attn`, because a repository nobody maintains genuinely wants a human decision
                // before its code runs. The word carries the meaning, so colour is never the only
                // signal (§2).
                HStack(spacing: DiscoverBoardMetrics.labelGap) {
                    IconView(.warn, size: TypeToken.caption.size)
                    Text(archived).lineLimit(1).truncationMode(.tail)
                }
                .typeRole(.caption)
                .foregroundStyle(ColorToken.attention.color)
            } else if secondaryName != nil {
                Text(secondaryName ?? "")
                    .typeRole(.caption, monospaced: true)
                    .foregroundStyle(ColorToken.t3.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }

        /// The wire `name`, shown only when it says something `displayName` did not.
        ///
        /// Repeating an identical string in a dimmer colour under itself reads as two facts when
        /// there is one.
        private var secondaryName: String? {
            let name = RegistryPresentation.sanitized(entry.name, cap: 80)
            let display = RegistryPresentation.sanitized(entry.displayName, cap: 80)
            guard !name.isEmpty, name != display else { return nil }
            return name
        }

        /// `installed` as a fact in `--t3` text, never a badge — a badge reads as a status that
        /// might change on its own, and this one is simply true.
        @ViewBuilder
        private var stateCell: some View {
            if entry.installed ?? false {
                Text("installed")
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
            } else {
                IconView(.chev, size: TypeToken.caption.size)
                    .foregroundStyle(ColorToken.t4.color)
                    .accessibilityHidden(true)
            }
        }

        private var accessibilityLabel: String {
            var parts = [RegistryPresentation.sanitized(entry.displayName, cap: 80)]
            parts.append(ProvenanceMark.spokenLabel(for: entry))
            if let figure { parts.append(figure.text) }
            if let dateCell { parts.append(dateCell.text) }
            if let archived = RegistryPresentation.archivedNote(for: entry) { parts.append(archived) }
            if entry.installed ?? false { parts.append("Already installed") }
            return parts.joined(separator: ", ")
        }
    }

    /// Which index said this — drawn, because it is the board's central fact.
    ///
    /// `DESIGN.md` §10 records that the breaker is the app's only subject-mined element and that a
    /// board of stock tables has "one signature and eight defaults". A merged catalogue whose
    /// provenance is a grey text pill is a merged catalogue pretending to be one list, so this is a
    /// two-cell plate: left for the official registry, right for Smithery, each **filled** when that
    /// index supplied the row and drawn as an **empty recess** when it did not — the breaker slot's
    /// established vocabulary for "a place where a thing would be".
    ///
    /// A `both` row is the only shape with both cells filled. Built entirely from existing tokens:
    /// no new shared token, no new colour, no change to any shared component.
    struct ProvenanceMark: View {
        let entry: RegistryEntry

        private var provenance: RegistryPresentation.Provenance {
            RegistryPresentation.provenance(for: entry)
        }

        var body: some View {
            HStack(spacing: DiscoverBoardMetrics.hairline * 2) {
                cell(filled: provenance.showsOfficialMark, checked: false)
                cell(filled: provenance.isSmithery, checked: entry.verified ?? false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spokenLabel(for: entry))
        }

        @ViewBuilder
        private func cell(filled: Bool, checked: Bool) -> some View {
            let shape = RoundedRectangle(
                cornerRadius: DiscoverBoardMetrics.markRadius,
                style: .continuous
            )
            ZStack {
                if filled {
                    shape.fill(ColorToken.f1.color)
                    if checked {
                        IconView(.check, size: TypeToken.caption.size * 0.7)
                            .foregroundStyle(ColorToken.t2.color)
                    }
                } else {
                    // The recess: a place where a thing would be, not a thing that is off.
                    //
                    // **An outline rather than a dimmer fill, and that is a correction.** The first
                    // build drew this as `f3` against the filled cell's `f1`. Both are white at
                    // different alphas, so on the rendered board the two cells read as two nearly
                    // identical grey squares and the mark said nothing — the one fact this board is
                    // built around, invisible. An empty outline differs by *shape*, which survives
                    // the alpha being subtle, and it is the vocabulary `SlotRow` already uses for a
                    // slot whose contents are not asserted.
                    shape.strokeBorder(
                        ColorToken.lineStrong.color,
                        lineWidth: DiscoverBoardMetrics.hairline
                    )
                }
            }
            .frame(width: DiscoverBoardMetrics.markCell, height: DiscoverBoardMetrics.markCell)
        }

        /// The mark in words, for VoiceOver and for the detail sheet's expanded line.
        ///
        /// Static so the sheet can say the same sentence the row's label says, rather than two
        /// wordings of one fact drifting apart.
        static func spokenLabel(for entry: RegistryEntry) -> String {
            let provenance = RegistryPresentation.provenance(for: entry)
            let verified = (entry.verified ?? false) ? ", verified by Smithery" : ""
            switch (provenance.showsOfficialMark, provenance.isSmithery) {
            case (true, true): return "In the official registry and on Smithery\(verified)"
            case (true, false): return "In the official registry"
            case (false, true): return "On Smithery\(verified)"
            case (false, false): return "Source not recorded"
            }
        }
    }

    /// The row's artwork.
    ///
    /// **No remote image is ever fetched**, and the reason is the product's own boundary rather
    /// than taste: `iconUrl` is a URL chosen by a third-party index, so fetching it would open a
    /// connection to a host of an attacker's choosing — once per row — and would be a second
    /// channel out of this app, which is the one thing the loopback-only rule exists to forbid.
    ///
    /// So every tile is the authored monogram plate `DESIGN.md` §4 prescribes for an entry whose
    /// marketplace ships no art: a flat token fill with the entry's initials, never a gradient.
    struct RegistryTile: View {
        let entry: RegistryEntry
        let side: Double
        let radius: Double

        var body: some View {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(ColorToken.raised2.color)
                .overlay {
                    Text(RegistryPresentation.monogram(for: entry))
                        .typeRole(side > DiscoverBoardMetrics.tile ? .title3 : .caption)
                        .foregroundStyle(ColorToken.t2.color)
                }
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }

    /// The loading state, at this board's exact row height.
    ///
    /// Six rows rather than a spinner, and at the populated geometry: this board's loading is
    /// genuinely slow — two live third-party calls at a 12-second timeout, plus up to ten sequential
    /// GitHub fetches — so the skeleton is what the user looks at rather than a flash.
    struct DiscoverSkeletonRows: View {
        var count: Int = 6

        var body: some View {
            VStack(spacing: DiscoverBoardMetrics.hairline) {
                ForEach(0 ..< count, id: \.self) { _ in
                    HStack(spacing: DiscoverBoardMetrics.rowPadding) {
                        RoundedRectangle(
                            cornerRadius: DiscoverBoardMetrics.tileRadius,
                            style: .continuous
                        )
                        .fill(ColorToken.f2.color)
                        .frame(
                            width: DiscoverBoardMetrics.tile,
                            height: DiscoverBoardMetrics.tile
                        )
                        VStack(alignment: .leading, spacing: DiscoverBoardMetrics.tightGap) {
                            bar(
                                width: DiscoverBoardMetrics.nameColumn * 0.7,
                                height: TypeToken.body.size
                            )
                            bar(
                                width: DiscoverBoardMetrics.nameColumn * 0.45,
                                height: TypeToken.caption.size
                            )
                        }
                        .frame(width: DiscoverBoardMetrics.nameColumn, alignment: .leading)
                        bar(width: DiscoverBoardMetrics.markColumn * 0.8, height: TypeToken.body.size)
                            .frame(width: DiscoverBoardMetrics.markColumn, alignment: .leading)
                        bar(
                            width: DiscoverBoardMetrics.figureColumn * 0.65,
                            height: TypeToken.body.size
                        )
                        .frame(width: DiscoverBoardMetrics.figureColumn, alignment: .leading)
                        bar(width: DiscoverBoardMetrics.dateColumn * 0.6, height: TypeToken.body.size)
                            .frame(width: DiscoverBoardMetrics.dateColumn, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DiscoverBoardMetrics.rowPadding)
                    .frame(height: DiscoverBoardMetrics.rowHeight)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Searching the registries")
        }

        private func bar(width: Double, height: Double) -> some View {
            RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar)
                .fill(ColorToken.f2.color)
                .frame(width: width, height: height)
        }
    }
#endif
