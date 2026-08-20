#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The shell's motion decisions, as functions a test can call.
    ///
    /// `DESIGN.md` §7 gives two moments the shell owns: "Row selection — immediate; no transition on
    /// the selection fill" and "Badge count change — a small scale bump, never a colour flash". Both
    /// are decisions about *whether and which* animation runs, and a decision buried inside a view
    /// body is a decision no test can reach — which is how "honours Reduce Motion" becomes a claim
    /// rather than a fact.
    ///
    /// The spring values are the breaker's documented rise, read from `BreakerGeometry` rather than
    /// invented here. A badge ticking up and a breaker snapping up are the same event — something
    /// just happened — and inventing a second spring for it would put an undocumented number in the
    /// design system.
    public enum ShellMotion {
        /// Row selection. **Always nil**, and not merely under Reduce Motion: §7 says the selection
        /// fill has no transition at all, because a selection that fades is a selection you have to
        /// wait for.
        public static func selectionAnimation() -> Animation? {
            nil
        }

        /// A badge whose count changed. Transform only — a scale bump, never a colour flash.
        public static func badgeBump(reduceMotion: Bool) -> Animation? {
            guard !reduceMotion else { return nil }
            let spring = BreakerGeometry.standard
            return .spring(response: spring.riseResponse, dampingFraction: spring.riseDamping)
        }

        /// How much a badge grows at the peak of its bump.
        ///
        /// Small, per §7. Derived from the focus ring against a control rung so it is a ratio of two
        /// documented values rather than a number chosen by eye.
        public static let badgeBumpScale =
            1 + MetricToken.focusRing.leadingScalar / MetricToken.controlRegular.leadingScalar

        /// How long the badge stays at its peak before settling.
        ///
        /// The breaker's documented rise, again: holding for the length of the spring that got it
        /// there is what makes the bump read as one movement rather than two.
        public static let badgeBumpHold = Duration.milliseconds(
            Int(BreakerGeometry.standard.riseResponse * 1000)
        )
    }

    /// The accessibility responses, likewise as testable decisions.
    ///
    /// A31's requirement is precise and easy to fail in the flattering direction: each setting must
    /// remove the *effect* without removing the state change or the information. A implementation
    /// that hides the badge under Reduce Motion would pass "honours the setting" and lose the fact.
    public enum ShellAccessibilityRules {
        /// Reduce Transparency: the sidebar stops being a system material and becomes the opaque
        /// panel token. The sidebar is still visibly a separate zone — the tonal step remains — so
        /// the information (where the sidebar ends) survives the effect being removed.
        public static func sidebarIsOpaque(reduceTransparency: Bool) -> Bool {
            reduceTransparency
        }

        /// Differentiate Without Colour: the Servers badge is amber because it means "wants a human
        /// decision", and the Cleanup badge is neutral. Told apart by hue alone, those two are
        /// indistinguishable to a viewer who cannot separate them — so the attention badge gains a
        /// glyph. The count itself is unchanged, which is the information.
        public static func badgeNeedsGlyph(
            differentiateWithoutColor: Bool,
            source: BadgeSource?
        ) -> Bool {
            differentiateWithoutColor && source == .serversNeedingAttention
        }

        /// Reduce Motion removes the bump and never the new number.
        public static func badgeAnimates(reduceMotion: Bool) -> Bool {
            !reduceMotion
        }
    }

    /// The sidebar: two named groups, an ungrouped tail, and the at-rest readout beneath them.
    /// When the sidebar shows a focus ring, as a decision rather than a modifier chain.
    ///
    /// **A24 was measured unmet before this existed.** Driven on 2026-08-14: keyboard focus was moved
    /// to the sidebar over the accessibility API — the outline's `AXFocused` went 0 → 1 — and a
    /// window-scoped capture before and after was **byte-identical**. Zero pixels changed. The
    /// selected row was already accent-tinted whether focused or not, so there was nothing on screen
    /// that said where the keyboard was, and "keyboard focus is visible" was false.
    ///
    /// `DESIGN.md` §8 says focus rings are visible, accent-bound and 2px, and F2 already ships
    /// exactly that as `focusRing(_:radius:)` reading `MetricToken.focusRing` and `ColorToken.accent`
    /// — so this needs no new design value and no change to the shared system. What it needs is
    /// somewhere to make the decision that a test can reach.
    public enum SidebarFocusRules {
        /// The ring appears on the selected row, and only while the sidebar holds the keyboard.
        ///
        /// Both halves matter and each is asserted. A ring on an unselected row would point at
        /// nothing; a ring that persists after focus leaves would claim the keyboard is somewhere it
        /// is not, which is worse than showing nothing at all.
        public static func showsFocusRing(isSelected: Bool, isSidebarFocused: Bool) -> Bool {
            isSelected && isSidebarFocused
        }
    }

    struct Sidebar: View {
        @Bindable var model: ShellModel
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        /// Whether the list holds the keyboard. Drives A24's ring, and nothing else.
        @FocusState private var isListFocused: Bool

        var body: some View {
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    ForEach(DestinationGroup.allCases, id: \.self) { group in
                        Section(group.rawValue) {
                            ForEach(Destination.inGroup(group)) { destination in
                                row(destination)
                            }
                        }
                    }
                    // The ungrouped tail: Settings, with no header above it.
                    Section {
                        ForEach(Destination.inGroup(nil)) { destination in
                            row(destination)
                        }
                    }
                }
                .listStyle(.sidebar)
                .focused($isListFocused)
                // §3.2: sentence case, and the headers are stored that way — there is no case
                // transform here to remove, which is what A12 asserts.
                .environment(\.defaultMinListRowHeight, MetricToken.tableRows.leadingScalar)

                // M27: no divider above the readout any more. It has a card of its own now — the
                // one `prototype.html` draws — and a full-bleed rule above a bordered plate is two
                // separations doing one job.
                Readout(
                    state: model.readout.state,
                    tracePoints: model.tracePoints(),
                    traceLabel: model.traceLabel()
                )
                .frame(height: readoutHeight)
                // All four edges. The top one was missing and the card sat flush against the last
                // nav row — the divider that used to separate them went with the card, so nothing
                // was left holding them apart. `DESIGN.md` §2 says the card's margins are its own,
                // which means the same margin on every side.
                .padding(ReadoutGeometry.cardMargin)

                if SidebarFootPresence.isDrawn(foot) {
                    Divider()
                    SidebarFoot(reading: foot)
                }
            }
            .background(sidebarBackground)
            .focusSection()
        }

        /// Where the app is pointed, from the same poll everything else in this shell renders.
        ///
        /// Read from `trackerState` rather than from a second source: the port is the one the
        /// router answered on, which is what makes the line an observation instead of a constant.
        private var foot: LoopbackFoot {
            LoopbackFoot.reading(for: model.trackerState)
        }

        /// The failure and empty forms carry wrapped prose, so they are allowed to be taller than the
        /// counts form. A29's claim is about the *skeleton and the populated readout* being one
        /// height, which is what this preserves.
        private var readoutHeight: CGFloat? {
            switch model.readout.state {
            case .loading, .populated, .partial: ReadoutGeometry.height
            case .empty, .failed: nil
            }
        }

        @ViewBuilder
        private var sidebarBackground: some View {
            if ShellAccessibilityRules.sidebarIsOpaque(reduceTransparency: reduceTransparency) {
                ShellChrome.sidebarBackground.color
            } else {
                Color.clear
            }
        }

        private func row(_ destination: Destination) -> some View {
            SidebarRow(
                destination: destination,
                isSelected: model.selection == destination,
                showsFocusRing: SidebarFocusRules.showsFocusRing(
                    isSelected: model.selection == destination,
                    isSidebarFocused: isListFocused
                ),
                badge: model.badge(for: destination)
            )
            .tag(destination)
        }
    }

    /// One destination row.
    ///
    /// The height is `MetricToken.tableRows` — the documented 24pt dense-list row — and M1 uses
    /// exactly one row size (A4). The label is the only element permitted to truncate; the badge
    /// keeps its natural width whatever the count, which is what stops a four-digit badge from
    /// moving the icon or growing the row (A14).
    struct SidebarRow: View {
        let destination: Destination
        let isSelected: Bool
        /// A24: drawn only where `SidebarFocusRules` says, so the condition is not re-derived here.
        let showsFocusRing: Bool
        let badge: Int?

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

        var body: some View {
            HStack(spacing: MetricToken.selectionInset.leadingScalar * 2) {
                IconView(icon)
                    .frame(width: MetricToken.controlMini.leadingScalar)
                Text(destination.title)
                    .typeRole(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if let badge {
                    BadgeView(
                        count: badge,
                        source: destination.badgeSource,
                        showsGlyph: ShellAccessibilityRules.badgeNeedsGlyph(
                            differentiateWithoutColor: differentiateWithoutColor,
                            source: destination.badgeSource
                        ),
                        animates: ShellAccessibilityRules.badgeAnimates(reduceMotion: reduceMotion)
                    )
                    // A14: the badge never gives up width, so the label truncates instead of it.
                    .layoutPriority(1)
                }
            }
            .frame(height: MetricToken.tableRows.leadingScalar)
            .foregroundStyle(isSelected ? ColorToken.accent.color : ColorToken.t2.color)
            // A24: F2's ring, at the selection's own radius so it sits on the fill rather than
            // around a rectangle nothing else draws. Its width and colour are the design system's —
            // `MetricToken.focusRing` and `ColorToken.accent` — which is why this item adds no
            // number of its own here.
            .focusRing(showsFocusRing, radius: MetricToken.selectionRadius.leadingScalar)
            // §7: the selection fill has no transition. Not "a fast one" — none.
            .animation(ShellMotion.selectionAnimation(), value: isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        }

        private var icon: Icon {
            Icon(rawValue: destination.iconName) ?? .conduit
        }

        /// A35: what a screen reader reads. The badge is spoken as what it counts rather than as a
        /// loose number — "Servers, 2 need attention" rather than "Servers, 2".
        private var accessibilityLabel: String {
            guard let badge, let source = destination.badgeSource else { return destination.title }
            return switch source {
            case .serversNeedingAttention: "\(destination.title), \(badge) need attention"
            case .serversNeverUsed: "\(destination.title), \(badge) never used"
            // Spoken as what it counts, like the other two. "Inbox, 2" would make a reader ask
            // two of what, on the one row whose number is about something a person sent them.
            case .queuedFromPhone: "\(destination.title), \(badge) waiting from your phone"
            }
        }
    }

    /// A count on a row.
    ///
    /// Monospaced because it is instrument data (§2), and tabular so the width does not jitter as
    /// the digits change. Amber only where amber means "wants a human decision"; everything else is
    /// a neutral fill, because an indicator colour used for emphasis is an indicator colour that
    /// stops meaning anything.
    struct BadgeView: View {
        let count: Int
        let source: BadgeSource?
        let showsGlyph: Bool
        let animates: Bool

        var body: some View {
            HStack(spacing: MetricToken.selectionInset.leadingScalar / 2) {
                if showsGlyph {
                    IconView(.warn, size: TypeToken.caption.size)
                }
                Text("\(count)")
                    .typeRole(.caption, monospaced: true)
                    .monospacedDigit()
            }
            .foregroundStyle(foreground.color)
            .padding(.horizontal, MetricToken.selectionInset.leadingScalar)
            .frame(height: MetricToken.controlMini.leadingScalar)
            .background(
                Capsule().fill(background.color)
            )
            // §7: a scale bump, never a colour flash — so the transform is what is keyed on the
            // count, and no colour is animated anywhere here.
            .modifier(BadgeBump(count: count, animates: animates))
        }

        private var foreground: ColorToken {
            source == .serversNeedingAttention ? .attention : .t2
        }

        private var background: ColorToken { .f1 }
    }

    /// The bump itself, factored out so the animation is applied to the transform and to nothing
    /// else — a `.animation(_, value:)` on the whole badge would animate its colour too the first
    /// time someone made the tint conditional.
    struct BadgeBump: ViewModifier {
        let count: Int
        let animates: Bool
        @State private var bumped = false

        func body(content: Content) -> some View {
            content
                .scaleEffect(bumped ? ShellMotion.badgeBumpScale : 1)
                // Keyed on the transform's own state, so nothing else on this view can be swept
                // into the animation. Nil under Reduce Motion: the new number still appears, and
                // only the movement is removed (A31).
                .animation(ShellMotion.badgeBump(reduceMotion: !animates), value: bumped)
                .onChange(of: count) {
                    guard animates else { return }
                    bumped = true
                    Task { @MainActor in
                        do {
                            try await Task.sleep(for: ShellMotion.badgeBumpHold)
                        } catch {
                            // The view went away mid-bump; there is nothing left to un-bump.
                            return
                        }
                        bumped = false
                    }
                }
        }
    }
#endif
