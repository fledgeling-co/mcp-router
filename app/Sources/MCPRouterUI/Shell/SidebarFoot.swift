#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The foot line's geometry, derived rather than picked, like everything else in the shell.
    enum SidebarFootGeometry {
        /// One dense row plus the card's padding above and below it, so the foot is visibly the
        /// same rhythm as the readout sitting on it.
        static let height =
            MetricToken.tableRows.leadingScalar + MetricToken.selectionInset.leadingScalar * 2

        /// The address starts where the readout's label starts: the card's margin plus the card's
        /// own padding. `prototype.html` sets the two independently and they do not line up; one
        /// left edge down the whole sidebar foot is the better reading of the same design.
        static let leading = ReadoutGeometry.cardMargin + ReadoutGeometry.cardPadding
    }

    /// The last line of the sidebar: **where this app is pointed**.
    ///
    /// `design/mocks/prototype.html:681` draws it inside the shared sidebar wrapper, so it belongs
    /// to every board rather than to one — and the build drew it on none of the nine. Restored here,
    /// with two deliberate differences from the mock, both settled against out-of-family review:
    ///
    /// 1. **The port is the observed one, never a constant.** The mock's literal `:8879` is the
    ///    honesty rule pointed outward — the fixture router answers on 8971, and a user who moved
    ///    the port would be told to reach for the wrong one. It comes from the same
    ///    `LoopbackAddress` composition the Settings `Endpoint` row uses, so the two cannot drift.
    /// 2. **There is no status dot.** The mock paints a `--live` one. `DESIGN.md` §2 gives `--live`
    ///    exactly one meaning — *a child process is running* — and it is already spent, correctly,
    ///    on the count in the card directly above. A green dot there while that card reads
    ///    `0 of 4` would paint `--live` where nothing is running, which is the decorative use §2
    ///    forbids. Both reviewing families reached that independently. A dot in a neutral tier was
    ///    the remaining option and it fails the other rule: a signal that means "answering" needs a
    ///    word for the state, and `ControlAPIError` already owns that word (§6). The router's
    ///    condition is the readout's job; this line's job is the address.
    struct SidebarFoot: View {
        let reading: LoopbackFoot

        var body: some View {
            // The presence decision is applied HERE as well as at the call site, rather than only
            // there. The frame is fixed, so an `.absent` reading rendered through this view without
            // the caller's guard draws a blank band the height of a dense row — a component that
            // leaks space when it has nothing to say, which is the trap `EmptyView` inside a fixed
            // frame always sets. The caller still guards, because it owns the divider that travels
            // with the line.
            if SidebarFootPresence.isDrawn(reading) {
                HStack(spacing: 0) {
                    content
                    Spacer(minLength: 0)
                }
                .frame(height: SidebarFootGeometry.height)
                .padding(.horizontal, SidebarFootGeometry.leading)
            }
        }

        @ViewBuilder
        private var content: some View {
            switch reading {
            case let .address(address):
                // Instrument data (§2): an address is a value the router reported, so it is
                // monospaced, and tertiary because it is chrome rather than a reading.
                Text(address)
                    .typeRole(.subheadline, monospaced: true)
                    .foregroundStyle(ColorToken.t3.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(LoopbackFootCopy.accessibilityLabel(address: address))
            case .awaitingFirstAnswer:
                // §5: a skeleton at the real line's geometry, so the sidebar does not move when the
                // first poll answers. Hidden from a screen reader — the readout above is already
                // saying that the app is waiting, and saying it twice is not more accessible.
                RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar)
                    .fill(ColorToken.f2.color)
                    .frame(
                        maxWidth: MetricToken.sidebar.leadingScalar / 3,
                        maxHeight: MetricToken.tableRows.leadingScalar / 3
                    )
                    .accessibilityHidden(true)
            case .absent:
                // Nothing was ever observed, so there is no address. `SidebarFootPresence` keeps
                // this arm from ever being reached — the divider goes with the line — and it is
                // written out rather than left to a default so the case is decided rather than
                // fallen through.
                EmptyView()
            }
        }
    }

    /// Whether the foot and its divider are drawn at all, as a decision a test can call.
    ///
    /// The two travel together on purpose: a divider with nothing under it is a rule ruling off the
    /// bottom of the window, which reads as a surface that failed to load rather than as one that
    /// has nothing to say.
    enum SidebarFootPresence {
        static func isDrawn(_ reading: LoopbackFoot) -> Bool {
            switch reading {
            case .address, .awaitingFirstAnswer: true
            case .absent: false
            }
        }
    }
#endif
