#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Geometry the design authority documents as a range rather than a value.
    ///
    /// `MetricToken` tokenises only the **leading** scalar of each documented cell — `DESIGN.md`'s
    /// "card radius 10–14" yields 10 and "table rows 24–28" yields 24 — so the pane's 32pt rows and
    /// its 150pt label column have no token to read. `SWIFT_PRACTICES.md` §5 forbids scattering them
    /// as literals, so they are named once here and derived from the documented units, exactly as
    /// `ServersBoardMetrics` does for the Servers board.
    enum SettingsMetrics {
        private static var unit: Double { MetricToken.tableRows.leadingScalar }
        private static var inset: Double { MetricToken.selectionInset.leadingScalar }

        /// The shared label column. **One constant, used by every group**, which is what makes
        /// "label-left, control-right, on one axis across the whole pane" a property of the layout
        /// rather than a coincidence four cards happen to share.
        static var labelColumn: Double { SettingsPresentation.labelColumnWidth }

        /// A settings row. Taller than a dense table row because it holds a control rather than a
        /// glyph, and the loading skeleton uses the same value so the card cannot resize when the
        /// real values land.
        static var rowHeight: Double { unit + inset * 2 }

        static var tightGap: Double { inset }
        static var gap: Double { inset * 2 }
        static var groupGap: Double { inset * 5 }
        static var cardPadding: Double { inset * 3 }
        static var panePadding: Double { MetricToken.selectionRadius.leadingScalar * 2 }
        static var cardRadius: Double { MetricToken.selectionRadius.leadingScalar + inset / 2 }
        static var chipHeight: Double { unit - inset }
        static var hairline: Double { MetricToken.focusRing.leadingScalar / 2 }
    }

    /// The pane behind `⌘,`.
    ///
    /// Reads what the shell already polls and starts nothing of its own — every Router value comes
    /// from the one `GET /servers` the tracker is already making, so this pane adds no traffic and
    /// cannot disagree with the window about what the router said.
    struct SettingsBoard: View {
        @Bindable var shell: ShellModel
        @State private var model: SettingsBoardModel

        init(shell: ShellModel, store: (any ControlTokenStore)? = nil) {
            self.shell = shell
            _model = State(wrappedValue: SettingsBoardModel(store: store ?? KeychainTokenStore()))
        }

        private var facts: SettingsPresentation.RouterFacts? {
            guard let state = shell.trackerState,
                  let port = state.port,
                  let idleMs = state.idleMs,
                  let since = state.since
            else { return nil }
            return .init(port: port, idleMs: idleMs, since: since, home: model.routerHome)
        }

        /// The router failed to answer and nothing was ever loaded. Distinct from "still loading",
        /// which draws a skeleton and says nothing.
        private var offlineError: ControlAPIError? {
            guard let state = shell.trackerState else { return nil }
            if case let .failed(error) = state.load { return error }
            return nil
        }

        /// **This board does not install a `ScrollView` of its own, and that is a correction rather
        /// than an omission.** It used to wrap its four groups in one while sitting *inside* the
        /// shell's — measured over the accessibility plane, Settings published **three**
        /// `AXScrollArea`s where every other board published two, the inner one `716×699` nested in
        /// a `716×568` parent. An inner scroll view taller than its own viewport is not the thing
        /// that scrolls, so the outer one moved, and the header this arrangement existed to keep
        /// still travelled with it.
        ///
        /// `ShellWindow.boardsThatScrollThemselves` states the criterion for owning a scroll view:
        /// **sticky chrome** — a column header or filter bar that must not ride a five-hundred-row
        /// log off the top. That is Activity. Settings has a pane title and a subtitle, which is
        /// what Servers, Skills, Discover, Inbox, Checks and Cleanup all have, and all six of them
        /// scroll inside the shell. So the registry was right and this board was the anomaly.
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {
                    routerGroup
                    menuBarGroup
                    warmSetGroup
                    tokenGroup
                }
                .padding(.horizontal, SettingsMetrics.panePadding)
                .padding(.bottom, SettingsMetrics.panePadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task { await model.load(unauthorized: offlineError == .unauthorized) }
            .onChange(of: offlineError) { _, new in
                Task { await model.load(unauthorized: new == .unauthorized) }
            }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: SettingsMetrics.tightGap) {
                Text(SettingsPresentation.paneTitle)
                    .typeRole(.title1)
                    .foregroundStyle(ColorToken.t1.color)
                Text(SettingsPresentation.paneSubtitle)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t2.color)
            }
            .padding(.horizontal, SettingsMetrics.panePadding)
            .padding(.top, SettingsMetrics.panePadding)
            .padding(.bottom, SettingsMetrics.gap)
        }

        // MARK: - Router

        private var routerGroup: some View {
            SettingsGroup(.router) {
                if let error = offlineError {
                    // Verbatim from `ControlAPIError` — F3's wording, asserted by `ControlCopyTests`,
                    // and deliberately carrying no action: nothing in this tree can start a router,
                    // and a button that cannot act is worse than the sentence. Recorded as a
                    // deviation from `DESIGN.md` §5 in spec-M8.
                    Banner(icon: .bang, tint: .fail) {
                        Text("\(error.headline). \(error.advice)")
                    }
                    Text(
                        """
                        Its endpoint, reaper and counting window are the router's own and are \
                        only knowable while it is up.
                        """
                    )
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
                } else if let facts {
                    SettingsCard {
                        SettingsRow(label: "Endpoint", value: facts.endpoint)
                        SettingsRow(label: "Home", value: facts.homeDisplay(), truncatesFromLeft: true)
                        SettingsRow(label: "Idle reaper", value: facts.reaper)
                        SettingsRow(label: "Counting since", value: facts.sinceDisplay())
                    }
                    helper(SettingsPresentation.routerHelp)
                } else {
                    // Skeletons at the populated row's exact height, so nothing moves when the
                    // values land. Never a spinner over a blank card.
                    SettingsCard {
                        ForEach(["Endpoint", "Home", "Idle reaper", "Counting since"], id: \.self) { label in
                            SettingsRow(label: label, value: nil)
                        }
                    }
                }
            }
        }

        // MARK: - Menu bar

        private var menuBarGroup: some View {
            SettingsGroup(.menuBar) {
                HStack(spacing: SettingsMetrics.gap) {
                    Text("Status item")
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .frame(width: SettingsMetrics.labelColumn, alignment: .leading)
                    Spacer(minLength: 0)
                    Toggle(SettingsPresentation.menuBarToggleLabel, isOn: $shell.isMenuBarVisible)
                        .toggleStyle(.checkbox)
                        .typeRole(.body)
                }
                .frame(minHeight: SettingsMetrics.rowHeight)
                helper(SettingsPresentation.menuBarHelp)
            }
        }

        // MARK: - Warm set

        private var warmSetGroup: some View {
            SettingsGroup(.warmSet) {
                let warm = shell.servers.map(SettingsPresentation.WarmSet.init(servers:))
                SettingsCard {
                    SettingsRow(
                        label: SettingsPresentation.warmSetLabel,
                        value: warm?.summary ?? SettingsPresentation.warmSetUnknown,
                        dimmed: warm == nil
                    )
                }
                if let warm, !warm.isEmpty {
                    WarmChips(names: warm.names)
                }
                HStack {
                    Spacer(minLength: SettingsMetrics.labelColumn)
                    Button(SettingsPresentation.warmSetAction) { shell.select(.servers) }
                        .buttonStyle(StandardButtonStyle())
                }
                .padding(.top, SettingsMetrics.tightGap)
                helper(
                    (warm?.isEmpty ?? true)
                        ? SettingsPresentation.warmSetEmptyHelp
                        : SettingsPresentation.warmSetPopulatedHelp
                )
            }
        }

        // MARK: - Control token

        private var tokenGroup: some View {
            SettingsGroup(.controlToken) {
                SettingsCard {
                    SettingsRow(label: SettingsPresentation.tokenLabel, value: model.status.value)
                    SettingsRow(
                        label: SettingsPresentation.tokenSourceLabel,
                        value: model.tokenPath,
                        dimmed: true,
                        truncatesFromLeft: true
                    )
                }
                if let banner = model.status.banner {
                    Banner(icon: .warn, tint: .attention) { Text(banner) }
                }
                HStack {
                    Spacer(minLength: SettingsMetrics.labelColumn)
                    forgetButton
                }
                .padding(.top, SettingsMetrics.tightGap)
                helper(model.tokenHelp)
            }
        }

        @ViewBuilder
        private var forgetButton: some View {
            let button = Button(SettingsPresentation.forgetAction) {
                Task { await model.forget() }
            }
            .disabled(!model.status.canForget)
            .help(model.status.canForget ? "" : SettingsPresentation.forgetDisabledReason)
            .accessibilityHint(model.status.canForget ? "" : SettingsPresentation.forgetDisabledReason)

            // §3.4 allows one prominent accent-filled action per view. Forget is it only while the
            // router is rejecting the stored token — the one condition where it is the fix rather
            // than a maintenance chore.
            if model.status.forgetIsProminent {
                button.buttonStyle(ProminentButtonStyle())
            } else {
                button.buttonStyle(StandardButtonStyle())
            }
        }

        private func helper(_ text: String) -> some View {
            Text(text)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SettingsMetrics.tightGap)
        }
    }
#endif
