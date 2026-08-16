#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Geometry for the popover, for the same reason `SettingsMetrics` exists: `DESIGN.md` gives
    /// "popover radius 20 · card radius 10–14 · concentric children" and `MetricToken` carries only
    /// the leading scalar, so the concentric child radius and the call-row height have no token.
    enum PopoverMetrics {
        private static var unit: Double { MetricToken.tableRows.leadingScalar }
        private static var inset: Double { MetricToken.selectionInset.leadingScalar }

        static var width: Double { MetricToken.sidebar.leadingScalar + unit * 3.5 }
        static var radius: Double { MetricToken.popoverRadius.leadingScalar }
        static var padding: Double { inset + inset / 2 }
        /// Concentric: child radius = parent radius − padding (§2).
        static var childRadius: Double { radius - padding }
        /// A call row. Slightly taller than a dense table row because it carries two type sizes.
        static var callRow: Double { unit + inset / 2 }
        static var bandRow: Double { unit + inset * 2 }
        /// An inbox row carries three type sizes and two controls, so it is taller than a band row.
        static var inboxRow: Double { unit + inset * 5 }
        /// The alpha of the band's own hairline edge. Named here rather than written inline, because
        /// M6's Phase D critic found a hand-rolled `0.16` on the inbox row and the fix was a name,
        /// not a constant in a second place.
        static var bandEdgeAlpha: Double { 0.28 }
        static var gap: Double { inset }
        static var rowPadding: Double { inset * 2.5 }
        static var hairline: Double { MetricToken.focusRing.leadingScalar / 2 }
        static var dot: Double { inset + 1 }
        static var ageColumn: Double { unit + inset * 2.5 }
        static var serverColumn: Double { unit * 3.5 }
        static var durationColumn: Double { unit * 2.3 }
    }

    /// The glanceable instrument.
    ///
    /// It renders `PopoverContent` and decides nothing — every count, sentence and tint was settled
    /// in `MCPRouterKit`, where a test can call it. What is left here is placement.
    ///
    /// Liquid Glass is legitimate here and only here in M8: §3.3 permits it on floating chrome and
    /// forbids it on content, so the window's panes stay opaque and this does not.
    public struct MenuBarPopover: View {
        @Bindable var shell: ShellModel

        public init(shell: ShellModel) {
            self.shell = shell
        }

        @State private var records: [CallRecord] = []
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        private var content: PopoverContent {
            PopoverContent.make(
                trackerState: shell.trackerState,
                records: records,
                inbox: shell.inboxBoard.bandZone(),
                now: Date()
            )
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: PopoverMetrics.gap) {
                header
                if let stale = content.stale { staleRow(stale) }
                // Above the attention band, and structurally rather than by taste: the attention
                // band's length is unbounded — one row per server wanting a decision — so an inbox
                // band placed after it can be pushed below the fold on a Mac with several held
                // changes. `PopoverContent.zones` states this order as a value so it is a unit test.
                if let inbox = content.inbox { MenuBarInboxBand(zone: inbox, shell: shell) }
                if let band = content.band { bandView(band) }
                if let message = content.message {
                    messageView(message)
                } else {
                    ForEach(content.calls) { CallRowView(row: $0) }
                }
                footer
            }
            .padding(PopoverMetrics.padding)
            .frame(width: PopoverMetrics.width)
            .background(background)
            .task { await loadCalls() }
        }

        @ViewBuilder
        private var background: some View {
            if reduceTransparency {
                ColorToken.panel.color
            } else {
                // The only glass in M8. §3.3: floating chrome only, never on content.
                Rectangle().fill(.regularMaterial)
            }
        }

        // MARK: - Header

        private var header: some View {
            HStack(spacing: PopoverMetrics.gap) {
                if let counts = content.counts {
                    Text("\(counts.running) running")
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t1.color)
                    separator
                    Text("\(counts.idle) idle")
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t2.color)
                    separator
                    Text("\(counts.tools) tools")
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t2.color)
                } else {
                    // Nobody answered, and zero is an answer. A skeleton rather than three noughts.
                    RoundedRectangle(cornerRadius: PopoverMetrics.hairline * 4, style: .continuous)
                        .fill(ColorToken.f2.color)
                        .frame(width: PopoverMetrics.serverColumn, height: TypeToken.callout.size)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PopoverMetrics.rowPadding)
            .padding(.top, PopoverMetrics.gap)
        }

        private var separator: some View {
            Text("·").typeRole(.callout).foregroundStyle(ColorToken.t4.color)
        }

        // MARK: - Stale, band, message

        private func staleRow(_ stale: PopoverContent.StaleNotice) -> some View {
            // Its own row, above the band. A refresh that did not complete is not the servers
            // failing, so the band's rows keep the tints their own causes give them (§2).
            HStack(alignment: .top, spacing: PopoverMetrics.gap) {
                IconView(.warn, size: TypeToken.callout.size)
                    .foregroundStyle(ColorToken.fail.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(stale.title)
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t1.color)
                    Text(stale.detail)
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t2.color)
                }
                Spacer(minLength: 0)
            }
            .padding(PopoverMetrics.rowPadding)
            .background(
                RoundedRectangle(cornerRadius: PopoverMetrics.childRadius, style: .continuous)
                    .fill(ColorToken.f3.color)
            )
        }

        private func bandView(_ band: [MenuBarPresentation.AttentionRow]) -> some View {
            VStack(spacing: 0) {
                ForEach(band) { row in
                    Button { MenuBarRouter.reveal(row, on: shell) } label: {
                        HStack(spacing: PopoverMetrics.gap) {
                            IconView(
                                Icon(rawValue: row.cause.iconName) ?? .warn,
                                size: TypeToken.callout.size
                            )
                            .foregroundStyle(row.cause.tintToken.color)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(row.server)
                                    .typeRole(.callout)
                                    .foregroundStyle(ColorToken.t1.color)
                                    .lineLimit(1)
                                Text(row.sentence)
                                    .typeRole(.subheadline)
                                    .foregroundStyle(ColorToken.t2.color)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            IconView(.chev, size: TypeToken.caption.size)
                                .foregroundStyle(ColorToken.t4.color)
                        }
                        .padding(.horizontal, PopoverMetrics.rowPadding)
                        .frame(minHeight: PopoverMetrics.bandRow)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.server), \(row.sentence)")
                }
            }
            .background(
                RoundedRectangle(cornerRadius: PopoverMetrics.childRadius, style: .continuous)
                    .fill(ColorToken.f3.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PopoverMetrics.childRadius, style: .continuous)
                    .strokeBorder(
                        ColorToken.attention.color.opacity(PopoverMetrics.bandEdgeAlpha),
                        lineWidth: PopoverMetrics.hairline
                    )
            )
        }

        private func messageView(_ message: PopoverContent.Message) -> some View {
            VStack(spacing: PopoverMetrics.gap) {
                Text(message.title)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                Text(message.detail)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t2.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PopoverMetrics.rowPadding * 2)
            .padding(.horizontal, PopoverMetrics.rowPadding)
        }

        // MARK: - Footer

        private var footer: some View {
            HStack(spacing: PopoverMetrics.gap) {
                Button(MenuBarPresentation.openWindowLabel) { MenuBarRouter.openWindow() }
                    .buttonStyle(ProminentButtonStyle())
                Spacer(minLength: 0)
                Button(MenuBarPresentation.quitLabel) { MenuBarRouter.quit() }
                    .buttonStyle(StandardButtonStyle())
                    .help(MenuBarPresentation.quitHelp)
                    .accessibilityHint(MenuBarPresentation.quitHelp)
            }
            .padding(.horizontal, PopoverMetrics.rowPadding)
            .padding(.bottom, PopoverMetrics.gap)
        }

        // MARK: - The calls

        /// The popover's own small read. The servers come from the shell's poll; the call log does
        /// not, because nothing else in the shell needs it.
        ///
        /// `usage` has no defaulted arguments on the protocol, so the two filters are named
        /// explicitly rather than relying on a convenience that does not exist.
        private func loadCalls() async {
            do {
                let response = try await shell.client.usage(
                    limit: MenuBarPresentation.recentCallLimit,
                    server: nil,
                    cwd: nil
                )
                records = response.records
            } catch {
                // The tracker already renders the connection's condition, and this surface shows it
                // through `PopoverContent`. Failing to fetch the log is not a second error to
                // report; the log simply stays as it was.
                records = []
            }
        }
    }

    /// One call. Every column is instrument data and reads in mono, except the server's name.
    struct CallRowView: View {
        let row: PopoverContent.CallRow

        var body: some View {
            HStack(spacing: PopoverMetrics.gap) {
                Circle()
                    .fill((row.failed ? ColorToken.fail : ColorToken.live).color)
                    .frame(width: PopoverMetrics.dot, height: PopoverMetrics.dot)
                Text(row.age)
                    .typeRole(.subheadline, monospaced: true)
                    .foregroundStyle(ColorToken.t3.color)
                    .frame(width: PopoverMetrics.ageColumn, alignment: .leading)
                Text(row.server)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t1.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: PopoverMetrics.serverColumn, alignment: .leading)
                Text(row.tool)
                    .typeRole(.subheadline, monospaced: true)
                    .foregroundStyle(ColorToken.t2.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: PopoverMetrics.hairline * 2) {
                    if row.cold {
                        IconView(.frost, size: TypeToken.caption.size)
                            .foregroundStyle(ColorToken.t3.color)
                    }
                    Text(row.duration)
                        .typeRole(.subheadline, monospaced: true)
                        .foregroundStyle(ColorToken.t3.color)
                }
                .frame(width: PopoverMetrics.durationColumn, alignment: .trailing)
            }
            .padding(.horizontal, PopoverMetrics.rowPadding)
            .frame(height: PopoverMetrics.callRow)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(row.server) \(row.tool), \(row.duration)\(row.cold ? ", cold start" : "")"
                    + (row.failed ? ", failed" : "")
            )
        }
    }
#endif
