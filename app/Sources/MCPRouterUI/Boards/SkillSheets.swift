#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Routes the board's one open sheet to its surface.
    struct SkillSheetHost: View {
        @Bindable var board: SkillsBoardModel
        let sheet: RouterSheet.Skills

        var body: some View {
            switch sheet {
            case let .heldVersion(skillID):
                if let skill = board.state.response?.skills.first(where: { $0.id == skillID }) {
                    HeldVersionSheet(skill: skill, board: board)
                } else {
                    // The row went away between opening the sheet and rendering it. Says so rather
                    // than showing an empty sheet built from nothing.
                    MissingSubjectSheet(board: board)
                }
            case .marketplaces:
                MarketplacesSheet(board: board)
            }
        }
    }

    /// Trust decays per version — the surface that makes that real.
    ///
    /// The brief's rule: a new version promotes on its own when its capability surface is unchanged,
    /// and waits for a human when it wants more than the one before it. This sheet is what "waits
    /// for a human" looks like, and its title states the finding rather than asking a question.
    struct HeldVersionSheet: View {
        let skill: Skill
        @Bindable var board: SkillsBoardModel

        var body: some View {
            VStack(alignment: .leading, spacing: SkillsBoardMetrics.gap) {
                Text(SkillPresentation.heldTitle(skill))
                    .typeRole(.title2)
                    .foregroundStyle(ColorToken.t1.color)
                    .fixedSize(horizontal: false, vertical: true)

                Text(SkillPresentation.heldBody(skill))
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)

                if let held = skill.held {
                    VStack(alignment: .leading, spacing: SkillsBoardMetrics.tightGap) {
                        ForEach(held.addedCapabilities, id: \.self) { capability in
                            HStack(alignment: .firstTextBaseline, spacing: SkillsBoardMetrics.tightGap) {
                                Text("+")
                                    .typeRole(.callout, monospaced: true)
                                    .foregroundStyle(ColorToken.attention.color)
                                Text(capability)
                                    .typeRole(.callout, monospaced: true)
                                    .foregroundStyle(ColorToken.attention.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(SkillsBoardMetrics.rowPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(
                            cornerRadius: MetricToken.selectionRadius.leadingScalar,
                            style: .continuous
                        )
                        .fill(ColorToken.f3.color)
                    }
                }

                // Names how the list was derived, so it is not mistaken for something the plugin's
                // author declared.
                Text(SkillPresentation.capabilityDerivation)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                // Both offers are dimmed with the same reason: M4 reads, it does not write. They
                // stay visible rather than disappearing, so the user can see what this surface will
                // eventually let them do and why it cannot yet (§3.4).
                VStack(alignment: .leading, spacing: SkillsBoardMetrics.tightGap) {
                    DisabledAction(
                        label: "Keep \(skill.source.pluginOrigin?.pluginVersion ?? "the installed version")",
                        reason: SkillPresentation.writesNotYetAvailable
                    )
                    DisabledAction(
                        label: "Promote to \(skill.held?.pluginVersion ?? "")",
                        reason: SkillPresentation.writesNotYetAvailable
                    )
                }

                HStack {
                    Spacer(minLength: 0)
                    Button("Done") { board.sheet = nil }
                        .buttonStyle(ProminentButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(SkillsBoardMetrics.panePadding)
            .frame(width: SkillsBoardMetrics.sheetWidth)
        }
    }

    /// Add, remove, and see what each marketplace supplies.
    struct MarketplacesSheet: View {
        @Bindable var board: SkillsBoardModel

        var body: some View {
            VStack(alignment: .leading, spacing: SkillsBoardMetrics.gap) {
                VStack(alignment: .leading, spacing: SkillsBoardMetrics.labelGap) {
                    Text("Marketplaces")
                        .typeRole(.title2)
                        .foregroundStyle(ColorToken.t1.color)
                    Text(subtitle)
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t2.color)
                }

                if let error = board.marketplacesError {
                    // The router refused. Its own two strings, never a second wording, and never
                    // dressed up as "you follow none" — which would be a claim about the user's
                    // configuration that nobody actually read.
                    Banner(icon: error == .routerNotRunning ? .bolt : .warn, tint: .attention) {
                        Text("\(error.headline). \(error.advice)")
                    }
                } else if board.marketplaces.isEmpty {
                    Text(
                        """
                        No marketplaces are being followed yet. Following one is how skills arrive, \
                        across every client that supports them.
                        """
                    )
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(spacing: SkillsBoardMetrics.hairline) {
                            ForEach(board.marketplaces) { marketplace in
                                MarketplaceRow(marketplace: marketplace)
                            }
                        }
                    }
                    .frame(maxHeight: MetricToken.sidebar.leadingScalar)
                }

                DisabledAction(
                    label: "Add a marketplace…",
                    reason: SkillPresentation.writesNotYetAvailable
                )

                HStack {
                    Spacer(minLength: 0)
                    Button("Done") { board.sheet = nil }
                        .buttonStyle(ProminentButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(SkillsBoardMetrics.panePadding)
            .frame(width: SkillsBoardMetrics.sheetWidth)
        }

        private var subtitle: String {
            let followed = board.marketplaces.count
            let skills = board.marketplaces.reduce(0) { $0 + $1.suppliedSkillCount }
            return "\(followed) followed · \(skills) \(skills == 1 ? "skill" : "skills") supplied"
        }
    }

    struct MarketplaceRow: View {
        let marketplace: Marketplace

        var body: some View {
            HStack(spacing: SkillsBoardMetrics.rowPadding) {
                VStack(alignment: .leading, spacing: SkillsBoardMetrics.hairline) {
                    Text(marketplace.name)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t1.color)
                        .lineLimit(1)
                    Text(marketplace.source.label)
                        .typeRole(.caption, monospaced: true)
                        .foregroundStyle(ColorToken.t3.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // "Supplies nothing" is a real observation about a followed marketplace with nothing
                // installed from it, and is not an error.
                Text(SkillPresentation.supplyLine(for: marketplace))
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t2.color)
                    .frame(width: SkillsBoardMetrics.nameColumn * 0.8, alignment: .leading)

                Text(SkillPresentation.autoUpdateLine(for: marketplace))
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .frame(width: SkillsBoardMetrics.versionColumn * 1.4, alignment: .leading)

                // Dimmed in place with its reason, rather than absent with the reason hidden in a
                // tooltip. §3.4: a disabled control dims and never disappears — and a reason
                // attached to no control at all is a reason nobody can find.
                DisabledAction(
                    label: "Remove",
                    reason: SkillPresentation.removeReason(for: marketplace)
                )
            }
            .padding(SkillsBoardMetrics.rowPadding)
            .frame(minHeight: SkillsBoardMetrics.rowHeight)
            .accessibilityElement(children: .combine)
        }
    }

    /// The subject of an open sheet stopped existing — a reload dropped it, or it was removed
    /// elsewhere. Says that, rather than rendering an empty form.
    struct MissingSubjectSheet: View {
        @Bindable var board: SkillsBoardModel

        var body: some View {
            VStack(alignment: .leading, spacing: SkillsBoardMetrics.gap) {
                Text("That skill is no longer listed")
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                Text(
                    """
                    The reading this sheet was opened from no longer includes it. Nothing was \
                    changed.
                    """
                )
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer(minLength: 0)
                    Button("Done") { board.sheet = nil }
                        .buttonStyle(ProminentButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(SkillsBoardMetrics.panePadding)
            .frame(width: SkillsBoardMetrics.sheetWidth)
        }
    }
#endif
