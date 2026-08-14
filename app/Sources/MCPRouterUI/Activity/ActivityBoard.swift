#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Activity board: what the agents on this machine are actually calling.
    ///
    /// Assembled from four parts that each answer for one thing — the header, the filter bar, the
    /// column header, and one exhaustive `switch` over `ActivityCondition`. The switch is the design:
    /// the order the conditions are tested in decides what a reader sees when two are true at once,
    /// and it lives in `ActivityModel` rather than in this body so it can be tested without a window
    /// and cannot be quietly re-ordered by an edit to the layout.
    public struct ActivityBoard: View {
        @Bindable private var model: ActivityModel
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @FocusState private var isListFocused: Bool

        /// Reports the list's scroll geometry to the shell, so the scroll-edge separator behaves
        /// the same over a board as it does over the placeholder.
        private let onScroll: ((Double, Double) -> Void)?

        public init(model: ActivityModel, onScroll: ((Double, Double) -> Void)? = nil) {
            self.model = model
            self.onScroll = onScroll
        }

        /// The identifiers the acceptance gate reads. Named constants rather than literals at the
        /// call site, so the script and the view cannot drift apart.
        public static let identifier = "activity-board"
        public static let listIdentifier = "activity-list"
        public static let subtitleIdentifier = "activity-subtitle"
        public static let stateIdentifier = "activity-state"

        public var body: some View {
            HStack(spacing: 0) {
                board
                if let record = model.selectedRecord {
                    Divider().overlay(ColorToken.line.color)
                    ActivityInspector(record: record, age: model.age(of: record))
                        .frame(width: MetricToken.sidebar.leadingScalar)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityIdentifier(Self.identifier)
            // Scoped to this board. Leaving Activity cancels both, so no socket is held open behind
            // a surface nobody is looking at, and coming back re-reads rather than showing a list
            // that stopped updating while it was away.
            .task { await model.start() }
            // Paired with the `.task` because a reconnect installs a subscription that the `.task`
            // does not own — see `ActivityModel.stopFeed()`.
            .onDisappear { model.stopFeed() }
        }

        // MARK: - The board's own column

        private var board: some View {
            VStack(alignment: .leading, spacing: 0) {
                header
                ActivityFilterBar(model: model)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: MetricToken.selectionInset.leadingScalar - 1) {
                Text(Destination.activity.title)
                    .typeRole(.title1)
                    .foregroundStyle(ColorToken.t1.color)
                if let subtitle = model.subtitle() {
                    Text(subtitle)
                        .typeRole(.subheadline, monospaced: true)
                        .foregroundStyle(ColorToken.t2.color)
                        .accessibilityIdentifier(Self.subtitleIdentifier)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ActivityColumn.inset)
            .padding(.vertical, MetricToken.selectionRadius.leadingScalar)
        }

        @ViewBuilder
        private var content: some View {
            let condition = model.condition
            switch condition {
            case .loading:
                ActivityColumnHeader()
                ActivitySkeletonRows()
                Spacer(minLength: 0)

            case .populated:
                ActivityColumnHeader()
                list

            case .partial, .historyUnavailable:
                // §5: say what arrived and what did not. The history stays on screen — replacing it
                // would throw away the half that did arrive.
                if let message = model.message(for: condition) {
                    FeedBanner(message: message) { await model.reconnect() }
                }
                ActivityColumnHeader()
                list

            case .empty, .filteredToNothing, .offline, .unauthorized, .error:
                if case .filteredToNothing = condition {
                    ActivityColumnHeader()
                }
                if let message = model.message(for: condition) {
                    VStack(spacing: MetricToken.selectionRadius.leadingScalar) {
                        MessageState(
                            actionable(condition) ? message : message.withoutAction,
                            icon: icon(for: condition),
                            tint: tint(for: condition)
                        ) {
                            act(on: condition)
                        }
                        // The refusal states name an action this item cannot perform — starting the
                        // router is R2R's, re-pairing is M8's. An **enabled** accent button wired to
                        // nothing is worse than the disabled placeholder §3.4 forbids: it reports a
                        // capability the app does not have and says nothing when pressed. §3.4's own
                        // answer is a control that dims in place with a discoverable reason, which
                        // is exactly what `DisabledAction` draws.
                        if !actionable(condition), let label = message.actionLabel {
                            DisabledAction(label: label, reason: Self.actionNotYetBuilt)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier(Self.stateIdentifier)
                }
            }
        }

        // MARK: - The list

        private var list: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Stable identity, which `SWIFT_PRACTICES.md` §4 requires for a list that
                        // reorders — and this one reorders on every arriving call.
                        ForEach(model.visible) { record in
                            Button {
                                model.selection = record.id
                            } label: {
                                ActivityRow(
                                    record: record,
                                    age: model.age(of: record),
                                    isSelected: model.selection == record.id
                                )
                            }
                            .buttonStyle(ActivityRowButtonStyle())
                            .id(record.id)
                            // Without this the row takes SwiftUI's default insertion transition,
                            // which is `.opacity` — an arriving call would fade in from nothing,
                            // against §7 and B35, with no opacity written anywhere in this file.
                            // Transform only, and `.identity` under Reduce Motion.
                            .transition(ActivityMotion.rowInsertion(reduceMotion: reduceMotion))
                        }
                    }
                }
                .onScrollGeometryChange(for: Double.self) { geometry in
                    geometry.contentOffset.y
                } action: { previous, offset in
                    // The same callback the placeholder's scroll view reports through, so the
                    // shell's scroll-edge separator is not a thing only the placeholder has.
                    onScroll?(previous, offset)
                }
                .accessibilityIdentifier(Self.listIdentifier)
                .focusable()
                .focused($isListFocused)
                .focusEffectDisabled(false)
                .onChange(of: model.selection) { _, new in
                    guard let new else { return }
                    withAnimation(reduceMotion ? nil : .easeOut) {
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
                // §8. `Space` is deliberately absent: it toggles a breaker, this board has none,
                // and claiming a key to do nothing is how a shortcut stops being learnable.
                .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                .onKeyPress(.return) {
                    // The view's one default action: open the inspector for the selected row. With
                    // nothing selected it selects the first, which is what Return means on a list
                    // that has never been touched.
                    if model.selection == nil { model.moveSelection(by: 1) }
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard model.selection != nil else { return .ignored }
                    model.clearSelection()
                    return .handled
                }
                // Transform only, and never opacity from zero (§7). Reduce Motion removes the
                // movement and keeps the insertion — the row still appears, it just does not slide.
                .animation(
                    reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.62),
                    value: model.visible.count
                )
            }
        }

        // MARK: - Which icon and tint a replaced-board state carries

        private func icon(for condition: ActivityCondition) -> Icon {
            switch condition {
            // `.partial` and `.historyUnavailable` never reach here — `content` routes both to the
            // banner — but the switch is exhaustive by design, so they are named with the icon they
            // would take rather than left to a `default` that would swallow a real new case.
            case .empty, .filteredToNothing, .loading, .populated, .partial: .activity
            case .offline: .bolt
            case .unauthorized: .shield
            case .error, .historyUnavailable: .bang
            }
        }

        /// The empty state is **not** an error, so it takes no warning tint. That is the brief's own
        /// instruction — "say that, it is not an error" — and a tint is the loudest way to disobey
        /// it while shipping the right words.
        private func tint(for condition: ActivityCondition) -> ColorToken {
            switch condition {
            case .empty, .filteredToNothing, .loading, .populated, .partial: .t3
            case .offline, .unauthorized: .attention
            case .error, .historyUnavailable: .fail
            }
        }

        /// The sentence under a control this build cannot yet perform. Names what is missing rather
        /// than apologising, in the same voice as the shell's scaffold copy.
        static let actionNotYetBuilt = "This arrives with the item that owns it."

        /// Whether the board can actually perform this state's offered action.
        ///
        /// Only one of them: clearing the filters is this board's own doing. Starting the router and
        /// re-pairing belong to items that have not shipped.
        private func actionable(_ condition: ActivityCondition) -> Bool {
            if case .filteredToNothing = condition { return true }
            return false
        }

        private func act(on condition: ActivityCondition) {
            switch condition {
            case .filteredToNothing:
                model.clearFilters()
            case .offline, .unauthorized, .error, .empty, .loading, .populated, .partial,
                 .historyUnavailable:
                break
            }
        }
    }

    /// The partial state's banner: adjacent to the list, never replacing it.
    struct FeedBanner: View {
        let message: StateMessage
        /// `async`, so the reconnect runs in the button's own task rather than in an unstructured
        /// `Task { }` that outlives the board it was pressed on.
        let reconnect: () async -> Void

        static let identifier = "activity-feed-banner"

        var body: some View {
            HStack(alignment: .top, spacing: MetricToken.selectionRadius.leadingScalar) {
                IconView(.warn, size: TypeToken.body.size)
                    .foregroundStyle(ColorToken.attention.color)
                VStack(alignment: .leading, spacing: MetricToken.focusRing.leadingScalar) {
                    Text(message.title)
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t1.color)
                    Text(message.detail)
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let label = message.actionLabel {
                    Button(label) { Task { await reconnect() } }
                        .buttonStyle(StandardButtonStyle())
                }
            }
            .padding(MetricToken.selectionRadius.leadingScalar)
            .background(
                RoundedRectangle(cornerRadius: MetricToken.selectionRadius.leadingScalar)
                    .fill(ColorToken.f3.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MetricToken.selectionRadius.leadingScalar)
                    .strokeBorder(ColorToken.lineStrong.color)
            )
            .padding(.horizontal, ActivityColumn.inset)
            .padding(.bottom, MetricToken.selectionRadius.leadingScalar)
            .accessibilityIdentifier(Self.identifier)
            // **Not** `.accessibilityElement(children: .combine)`. Combining folds the whole banner
            // into one static element and takes its button with it — the reconnect control stops
            // being reachable to assistive technology, and the only way back from a spent feed is
            // gone for anyone not using a mouse. The acceptance run caught this by looking for the
            // button and not finding it; a sighted pass would have seen it drawn and moved on.
        }
    }

    /// A row is a button, and a button on macOS must not look like a web link.
    ///
    /// §3.1 — selection is a flat inset rounded fill, drawn by the row itself. §3.8 — the arrow
    /// cursor throughout app chrome; nothing here sets a pointing hand. The style's whole job is to
    /// add the hover fill and take nothing else away.
    struct ActivityRowButtonStyle: ButtonStyle {
        @State private var isHovered = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(hoverFill(configuration.isPressed))
                .onHover { isHovered = $0 }
        }

        private func hoverFill(_ isPressed: Bool) -> Color {
            if isPressed { return ColorToken.f2.color }
            return isHovered ? ColorToken.f3.color : Color.clear
        }
    }
#endif
