#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// One queued item.
    ///
    /// **Nothing on this row is an indicator colour.** The prototype paints its capability cell in
    /// `--fail` when the entry wants shell and network — but `--fail` means "failed or tripped", and
    /// a description of what something *would* do is neither. `DESIGN.md` §2's exclusivity rule is
    /// what makes one amber dot in a menu bar mean anything, and §10 already records the prototype
    /// breaking it on the phone's Discover list. This is the same defect on this pane, and it is not
    /// reproduced: capability reads as text in the label tiers, exactly as M5's declaration sheet
    /// renders it.
    struct InboxBoardRow: View {
        let item: InboxItem
        let isSelected: Bool
        let onOpen: () -> Void
        let onDecline: () -> Void

        var body: some View {
            HStack(spacing: InboxBoardMetrics.rowPadding) {
                tile
                name
                capability
                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, InboxBoardMetrics.rowPadding)
            // Fixed height: §5's Overflow rule is that rows never change height, and this list grows
            // and shrinks as items arrive and are dispositioned.
            .frame(height: InboxBoardMetrics.rowHeight)
            .background {
                // §3.1: an inset rounded fill at the documented radius, never a full-bleed bar.
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: MetricToken.selectionRadius.leadingScalar,
                        style: .continuous
                    )
                    .fill(ColorToken.accent.color.opacity(0.16))
                    .padding(.horizontal, MetricToken.selectionInset.leadingScalar)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        }

        @ViewBuilder
        private var tile: some View {
            if let entry = item.resolved {
                RegistryTile(
                    entry: entry,
                    side: InboxBoardMetrics.tile,
                    radius: InboxBoardMetrics.tileRadius
                )
            } else {
                // An unresolved entry has no monogram to draw, because a monogram is derived from
                // the entry. The tray glyph says "this is a queued thing" without claiming to know
                // which one.
                RoundedRectangle(cornerRadius: InboxBoardMetrics.tileRadius, style: .continuous)
                    .fill(ColorToken.f3.color)
                    .overlay { IconView(.tray, size: TypeToken.caption.size) }
                    .frame(width: InboxBoardMetrics.tile, height: InboxBoardMetrics.tile)
                    .accessibilityHidden(true)
            }
        }

        private var name: some View {
            VStack(alignment: .leading, spacing: InboxBoardMetrics.labelGap) {
                Text(item.title)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(
                    InboxCopy.provenance(
                        queued: shortAgo(item.envelope.queuedAt),
                        device: item.envelope.deviceName
                    )
                )
                .typeRole(.caption)
                .foregroundStyle(ColorToken.t3.color)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .frame(width: InboxBoardMetrics.nameColumn, alignment: .leading)
        }

        /// The headline of what the Mac read, or the Partial sentence when it read nothing.
        ///
        /// Derived from the entry **the Mac resolved**, never from anything the envelope carried:
        /// the phone has no field in which to describe a capability, which is what stops a
        /// compromised sender presenting a shell command as read-only.
        private var capability: some View {
            Text(capabilityText)
                .typeRole(.subheadline)
                .foregroundStyle(item.isPartial ? ColorToken.t3.color : ColorToken.t2.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: InboxBoardMetrics.capabilityColumn, alignment: .leading)
        }

        private var capabilityText: String {
            guard let entry = item.resolved else { return InboxCopy.partialTitle }
            return RegistryCapability.statement(for: entry).headline
        }

        private var actions: some View {
            HStack(spacing: InboxBoardMetrics.tightGap) {
                // §3.4: `…` means "opens a further view". Reviewing is the only route to accepting,
                // and that is the whole shape of this board.
                Button(InboxCopy.reviewAction, action: onOpen)
                    .buttonStyle(StandardButtonStyle())
                Button(InboxCopy.declineAction, action: onDecline)
                    .buttonStyle(StandardButtonStyle())
            }
        }

        private var accessibilityLabel: String {
            let when = InboxCopy.provenance(
                queued: shortAgo(item.envelope.queuedAt),
                device: item.envelope.deviceName
            )
            return "\(item.title), \(capabilityText), \(when)"
        }
    }

    /// The loading state, at this board's exact row height.
    ///
    /// Skeleton rows rather than a spinner (§5), and at the populated geometry so the board does not
    /// jump when data lands.
    struct InboxSkeletonRows: View {
        var count: Int = 3

        var body: some View {
            VStack(spacing: InboxBoardMetrics.hairline) {
                ForEach(0 ..< count, id: \.self) { _ in
                    HStack(spacing: InboxBoardMetrics.rowPadding) {
                        RoundedRectangle(
                            cornerRadius: InboxBoardMetrics.tileRadius,
                            style: .continuous
                        )
                        .fill(ColorToken.f3.color)
                        .frame(width: InboxBoardMetrics.tile, height: InboxBoardMetrics.tile)
                        RoundedRectangle(cornerRadius: InboxBoardMetrics.tileRadius, style: .continuous)
                            .fill(ColorToken.f3.color)
                            .frame(width: InboxBoardMetrics.nameColumn, height: TypeToken.body.size)
                        RoundedRectangle(cornerRadius: InboxBoardMetrics.tileRadius, style: .continuous)
                            .fill(ColorToken.f3.color)
                            .frame(
                                width: InboxBoardMetrics.capabilityColumn,
                                height: TypeToken.body.size
                            )
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, InboxBoardMetrics.rowPadding)
                    .frame(height: InboxBoardMetrics.rowHeight)
                }
            }
            .accessibilityHidden(true)
        }
    }
#endif
