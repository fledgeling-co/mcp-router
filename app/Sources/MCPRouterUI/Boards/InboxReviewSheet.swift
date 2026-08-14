#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The review sheet — the only surface in the product that can install something a phone asked
    /// for.
    ///
    /// It is M5's detail-then-install shape applied to a queued item, and it **calls** M5's
    /// `RegistryCapability` rather than reimplementing it: the same statement, the same requirement
    /// gating, the same argv-as-tokens rendering. Two things are added, and both are about
    /// provenance rather than about capability — where this came from, and that declining is a first
    /// -class outcome here in a way it is not on Discover.
    ///
    /// **Every string is attacker-controlled**, and doubly so: `displayName` and `description` come
    /// from a third-party index, and the item itself was chosen by a remote device. Everything
    /// arrives through `RegistryPresentation.sanitized` before it is drawn, and the argv is rendered
    /// token by token rather than joined into something that reads as a shell line.
    struct InboxReviewSheet: View {
        @Bindable var board: InboxBoardModel
        let item: InboxItem

        @State private var values: [String: String] = [:]
        @State private var requirementsRevealed = false

        /// Permission to install, which an unresolved item cannot obtain. The action bar reads this:
        /// nil means the entry could not be read, and there is nothing to accept.
        private var acceptable: AcceptableInboxItem? {
            AcceptableInboxItem(item)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: InboxBoardMetrics.gap * 2) {
                        identity
                        provenance
                        if let entry = item.resolved {
                            capability(entry)
                            if requirementsRevealed { requirements(entry) }
                        } else {
                            unresolved
                        }
                    }
                    .padding(InboxBoardMetrics.panePadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                actionBar
            }
            .frame(width: InboxBoardMetrics.sheetWidth)
            .background(ColorToken.panel.color)
        }

        // MARK: - Identity and provenance

        private var identity: some View {
            HStack(spacing: InboxBoardMetrics.gap) {
                if let entry = item.resolved {
                    RegistryTile(
                        entry: entry,
                        side: InboxBoardMetrics.detailTile,
                        radius: InboxBoardMetrics.detailTileRadius
                    )
                }
                VStack(alignment: .leading, spacing: InboxBoardMetrics.labelGap) {
                    Text(item.title)
                        .typeRole(.title2)
                        .foregroundStyle(ColorToken.t1.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let entry = item.resolved {
                        Text(RegistryPresentation.sanitized(entry.description, cap: 200))
                            .typeRole(.body)
                            .foregroundStyle(ColorToken.t2.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }

        /// Where this came from, and the tense that is the guarantee the whole queue exists to make:
        /// it has **not run**.
        ///
        /// `--attn`, and legitimately: this is the sentence asking for a human decision, which is
        /// exactly what that token means (§2). It is not decoration.
        private var provenance: some View {
            HStack(alignment: .top, spacing: InboxBoardMetrics.labelGap) {
                IconView(.tray, size: TypeToken.caption.size)
                VStack(alignment: .leading, spacing: InboxBoardMetrics.labelGap) {
                    Text(InboxCopy.provenanceNote)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        InboxCopy.provenance(
                            queued: shortAgo(item.envelope.queuedAt),
                            device: item.envelope.deviceName
                        )
                    )
                    .foregroundStyle(ColorToken.t3.color)
                }
            }
            .typeRole(.caption)
            .foregroundStyle(ColorToken.attention.color)
        }

        // MARK: - What it would do

        private func capability(_ entry: RegistryEntry) -> some View {
            let statement = RegistryCapability.statement(for: entry)
            return VStack(alignment: .leading, spacing: InboxBoardMetrics.tightGap) {
                Text(statement.headline)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                Text(statement.detail)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)

                if !statement.argv.isEmpty {
                    // Token by token, never joined: a joined line reads as a shell command, and an
                    // entry whose args contain spaces or quotes would render as a different command
                    // from the one that runs.
                    FlowTokens(tokens: statement.argv)
                }
                if let host = statement.host {
                    Text(host)
                        .typeRole(.callout)
                        .monospaced()
                        .foregroundStyle(ColorToken.t2.color)
                }
            }
        }

        /// The Partial state, stated about the item rather than about the pane.
        private var unresolved: some View {
            VStack(alignment: .leading, spacing: InboxBoardMetrics.tightGap) {
                Text(InboxCopy.partialTitle)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                Text(InboxCopy.partialDetail)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func requirements(_ entry: RegistryEntry) -> some View {
            VStack(alignment: .leading, spacing: InboxBoardMetrics.tightGap) {
                ForEach(entry.install?.requires ?? [], id: \.name) { requirement in
                    let key = RegistryPresentation.sanitized(requirement.name)
                    VStack(alignment: .leading, spacing: InboxBoardMetrics.labelGap) {
                        Text(key)
                            .typeRole(.callout)
                            .foregroundStyle(ColorToken.t2.color)
                        SecureField("", text: binding(for: key))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    }
                }
            }
        }

        private func binding(for key: String) -> Binding<String> {
            Binding(
                get: { values[key] ?? "" },
                set: { values[key] = $0 }
            )
        }

        // MARK: - The action bar

        /// Cancel leads, one prominent accent-filled action trails (§3.4). Decline sits between
        /// them: it is a real outcome here rather than a way of closing the sheet, and it is not the
        /// default button, because the destructive-feeling option never is.
        private var actionBar: some View {
            VStack(alignment: .leading, spacing: InboxBoardMetrics.tightGap) {
                if case let .failed(error) = board.acceptState {
                    HStack(alignment: .top, spacing: InboxBoardMetrics.labelGap) {
                        IconView(.bang, size: TypeToken.caption.size)
                        Text("\(error.headline) \(error.advice)")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.fail.color)
                }

                if let reason = disabledReason {
                    // Dimmed in place with its reason readable beside it, never hidden (§3.4).
                    Text(reason)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: InboxBoardMetrics.tightGap) {
                    Button("Cancel") { board.escape() }
                        .buttonStyle(StandardButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(InboxCopy.declineAction) { board.decline(item) }
                        .buttonStyle(StandardButtonStyle())
                    Spacer(minLength: 0)
                    Button(acceptLabel) { press() }
                        .buttonStyle(ProminentButtonStyle())
                        .disabled(!isAcceptEnabled)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(InboxBoardMetrics.panePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// The button's whole state machine comes from `RegistryCapability.action`, so this sheet
        /// and Discover's cannot drift on when an install may commit. Where the entry could not be
        /// read there is no action to derive, and the label says what it would have done.
        private var action: RegistryCapability.Action? {
            guard let entry = item.resolved else { return nil }
            return RegistryCapability.action(
                for: entry,
                isInstalling: board.acceptState == .accepting,
                requirementsRevealed: requirementsRevealed,
                values: values
            )
        }

        private var acceptLabel: String {
            action?.label ?? InboxCopy.acceptAction
        }

        private var isAcceptEnabled: Bool {
            acceptable != nil && (action?.isEnabled ?? false)
        }

        private var disabledReason: String? {
            guard acceptable != nil else { return InboxCopy.partialDetail }
            return action?.disabledReason
        }

        /// The `…` rule as behaviour: the first press of an entry with requirements reveals the
        /// fields, and the second commits.
        private func press() {
            board.clearAcceptFailure()
            if action?.revealsRequirements == true {
                requirementsRevealed = true
                return
            }
            guard let acceptable else { return }
            board.requirementValues = values
            Task { await board.accept(acceptable) }
        }
    }

    /// Argv tokens, wrapped, each drawn as its own chip.
    ///
    /// A `LazyVGrid` rather than a `Text` join, for the reason above: the separation has to survive
    /// a token that contains a space, a quote, or a line separator.
    struct FlowTokens: View {
        let tokens: [String]

        var body: some View {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: InboxBoardMetrics.nameColumn / 2),
                        spacing: InboxBoardMetrics.labelGap
                    )
                ],
                alignment: .leading,
                spacing: InboxBoardMetrics.labelGap
            ) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    Text(token)
                        .typeRole(.callout)
                        .monospaced()
                        .foregroundStyle(ColorToken.t1.color)
                        .padding(.horizontal, InboxBoardMetrics.tightGap)
                        .padding(.vertical, InboxBoardMetrics.labelGap)
                        .background {
                            RoundedRectangle(
                                cornerRadius: InboxBoardMetrics.tileRadius,
                                style: .continuous
                            )
                            .fill(ColorToken.f2.color)
                        }
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
#endif
