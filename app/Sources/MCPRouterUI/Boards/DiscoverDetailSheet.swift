#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The detail sheet — the whole point of detail-then-install.
    ///
    /// Opening a row never installs. This is the only surface in the product that can declare a
    /// server from a third-party index, and it is reached deliberately: by click, by `Return` on a
    /// selected row. Everything above the action bar exists so the press is informed.
    ///
    /// **Every string here is attacker-controlled** — `displayName`, `description`, the argv, the
    /// requirement names — so every one of them arrives through `RegistryPresentation.sanitized`
    /// before it is drawn, and the argv is rendered as separate tokens rather than joined into
    /// something that reads as a shell line.
    struct DiscoverDetailSheet: View {
        @Bindable var board: DiscoverBoardModel
        let entry: RegistryEntry

        /// Held for the life of the sheet and handed to the router with the declaration. This app
        /// writes them nowhere, which is what `RegistryCapability.secretDestination` says out loud.
        @State private var values: [String: String] = [:]
        @State private var requirementsRevealed = false

        private var statement: RegistryCapability.Statement {
            RegistryCapability.statement(for: entry)
        }

        private var action: RegistryCapability.Action {
            RegistryCapability.action(
                for: entry,
                isInstalling: board.installState == .installing,
                requirementsRevealed: requirementsRevealed
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DiscoverBoardMetrics.gap * 2) {
                        identity
                        description
                        capability
                        if requirementsRevealed { requirements }
                        repository
                    }
                    .padding(DiscoverBoardMetrics.panePadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                actionBar
            }
            .frame(width: DiscoverBoardMetrics.sheetWidth)
            .background(ColorToken.panel.color)
        }

        // MARK: - Identity

        private var identity: some View {
            HStack(alignment: .top, spacing: DiscoverBoardMetrics.gap) {
                RegistryTile(
                    entry: entry,
                    side: DiscoverBoardMetrics.detailTile,
                    radius: DiscoverBoardMetrics.detailTileRadius
                )
                VStack(alignment: .leading, spacing: DiscoverBoardMetrics.labelGap) {
                    Text(RegistryPresentation.sanitized(entry.displayName, cap: 120))
                        .typeRole(.title2)
                        .foregroundStyle(ColorToken.t1.color)
                    Text(RegistryPresentation.sanitized(entry.name, cap: 120))
                        .typeRole(.callout, monospaced: true)
                        .foregroundStyle(ColorToken.t3.color)
                    // The row's mark, expanded to the words it stands for — the same sentence the
                    // row's accessibility label says, so the two cannot drift apart.
                    Text(ProvenanceMark.spokenLabel(for: entry))
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t2.color)
                    if let version = entry.version, !version.isEmpty {
                        Text("version \(RegistryPresentation.sanitized(version, cap: 40))")
                            .typeRole(.caption, monospaced: true)
                            .foregroundStyle(ColorToken.t3.color)
                    }
                }
                Spacer(minLength: 0)
            }
        }

        /// The index's own text, in full — this is the surface the row truncated toward.
        ///
        /// Capped only against a denial of the sheet: `description` is unbounded on the wire, and a
        /// megabyte of text here is a sheet nobody can use.
        @ViewBuilder
        private var description: some View {
            let text = RegistryPresentation.sanitized(entry.description, cap: 4000)
            if !text.isEmpty {
                Text(text)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // MARK: - What this will do

        private var capability: some View {
            VStack(alignment: .leading, spacing: DiscoverBoardMetrics.tightGap) {
                Text("What this will do")
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)

                Text(statement.headline)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)

                // The claim that it "runs shell" is answered by showing the actual argv rather than
                // by a boolean, because the argv is what is true. Monospace is the instrument voice
                // (§2), and a command line is the most literal instrument datum in the product.
                if !statement.argv.isEmpty {
                    FlowingTokens(tokens: statement.argv)
                        .padding(DiscoverBoardMetrics.rowPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(
                                cornerRadius: DiscoverBoardMetrics.tileRadius,
                                style: .continuous
                            )
                            .fill(ColorToken.f2.color)
                        }
                }

                Text(statement.detail)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)

                // Labelled as a reading, so it is not mistaken for something the entry's author
                // declared and stands behind.
                Text(RegistryCapability.derivationNote)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // MARK: - What it asks you for

        private var requirements: some View {
            VStack(alignment: .leading, spacing: DiscoverBoardMetrics.tightGap) {
                Text("What it asks you for")
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)

                if let summary = RegistryCapability.requirementSummary(for: entry) {
                    Text(summary)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(entry.install?.requires ?? [], id: \.name) { requirement in
                    field(for: requirement)
                }

                // Deliberately unflattering and deliberately accurate: the router writes it into its
                // own config, and a sentence implying a keychain would be false.
                Text(RegistryCapability.secretDestination)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        @ViewBuilder
        private func field(for requirement: RegistryRequirement) -> some View {
            let isSecret = requirement.isSecret ?? false
            let name = RegistryPresentation.sanitized(requirement.name, cap: 80)
            VStack(alignment: .leading, spacing: DiscoverBoardMetrics.labelGap) {
                HStack(spacing: DiscoverBoardMetrics.labelGap) {
                    Text(name)
                        .typeRole(.callout, monospaced: true)
                        .foregroundStyle(ColorToken.t1.color)
                    if isSecret {
                        // The word carries the meaning, so this is never colour alone (§2).
                        Text("secret")
                            .typeRole(.caption)
                            .foregroundStyle(ColorToken.t3.color)
                    }
                }
                if let detail = requirement.description, !detail.isEmpty {
                    Text(RegistryPresentation.sanitized(detail, cap: 400))
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    if isSecret {
                        SecureField(name, text: binding(for: requirement.name))
                    } else {
                        TextField(name, text: binding(for: requirement.name))
                    }
                }
                .textFieldStyle(.roundedBorder)
                .typeRole(.body)
            }
        }

        private func binding(for key: String) -> Binding<String> {
            Binding(
                get: { values[key] ?? "" },
                set: { values[key] = $0 }
            )
        }

        // MARK: - Repository

        /// A link only where the URL is one this app is willing to open.
        ///
        /// `repository` is a third-party string, so an unvalidated `Link` would hand a registry
        /// author the ability to put a `file:` or custom-scheme URL in front of the user on a
        /// surface they are already trusting. Anything that is not `https` renders as plain text.
        @ViewBuilder
        private var repository: some View {
            let raw = entry.repository ?? ""
            let url = URL(string: raw)
            let isWeb = url?.scheme?.lowercased() == "https"
            if !raw.isEmpty {
                VStack(alignment: .leading, spacing: DiscoverBoardMetrics.labelGap) {
                    Text("Repository")
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                    if isWeb, let url {
                        Link(RegistryPresentation.sanitized(raw, cap: 200), destination: url)
                            .typeRole(.callout)
                    } else {
                        Text(RegistryPresentation.sanitized(raw, cap: 200))
                            .typeRole(.callout, monospaced: true)
                            .foregroundStyle(ColorToken.t2.color)
                    }
                    if let archived = RegistryPresentation.archivedNote(for: entry) {
                        HStack(spacing: DiscoverBoardMetrics.labelGap) {
                            IconView(.warn, size: TypeToken.caption.size)
                            Text(archived)
                        }
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.attention.color)
                    }
                    if let pushed = RegistryPresentation.lastPushed(for: entry) {
                        Text(pushed)
                            .typeRole(.caption)
                            .foregroundStyle(ColorToken.t3.color)
                    }
                }
            }
        }

        // MARK: - The action bar

        /// Cancel leads, one prominent accent-filled action trails (§3.4). Failure renders adjacent
        /// to the action rather than in a banner, and success is an in-place state change — macOS
        /// does not toast a click, so the sheet stays open and the action becomes `Added`.
        private var actionBar: some View {
            VStack(alignment: .leading, spacing: DiscoverBoardMetrics.tightGap) {
                if case let .failed(error) = board.installState {
                    HStack(alignment: .top, spacing: DiscoverBoardMetrics.labelGap) {
                        IconView(.bang, size: TypeToken.caption.size)
                        Text("\(error.headline) \(error.advice)")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.fail.color)
                }

                if let reason = action.disabledReason {
                    // Dimmed in place with the reason readable beside it — never hidden (§3.4).
                    Text(reason)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: DiscoverBoardMetrics.tightGap) {
                    Button("Cancel") { board.escape() }
                        .buttonStyle(StandardButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Spacer(minLength: 0)
                    Button(action.label) { press() }
                        .buttonStyle(ProminentButtonStyle())
                        .disabled(!action.isEnabled)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(DiscoverBoardMetrics.panePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// The `…` rule as behaviour: the first press of an entry with requirements reveals the
        /// fields, and the second commits. Without requirements there is only ever one press.
        private func press() {
            board.clearInstallFailure()
            if action.revealsRequirements {
                requirementsRevealed = true
                return
            }
            let captured = values
            Task { await board.install(entry, values: captured) }
        }
    }

    /// The argv, one token per cell.
    ///
    /// Kept as separate cells rather than joined into a line on purpose: a joined line reads as a
    /// shell command, an entry whose args contain spaces or quotes would render as a *different*
    /// command from the one that will run, and an entry could smuggle what looks like a second
    /// command into the block. Each token is visibly its own thing.
    struct FlowingTokens: View {
        let tokens: [String]

        var body: some View {
            VStack(alignment: .leading, spacing: DiscoverBoardMetrics.labelGap) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    Text(token)
                        .typeRole(.callout, monospaced: true)
                        .foregroundStyle(ColorToken.t1.color)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Command: \(tokens.joined(separator: " "))")
        }
    }
#endif
