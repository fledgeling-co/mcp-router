#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The trailing detail panel for one skill.
    ///
    /// Inside the content zone rather than a third `NavigationSplitView` column, matching the
    /// Servers board: M1 pinned the split view to two columns and a third would change the shell's
    /// chrome, which belongs to another item.
    ///
    /// This is also where the truncated values in the table are readable in full (§5, Overflow), and
    /// where **all six clients are named** — including the two with no skills mechanism, so their
    /// absence from the four-slot column is explained rather than merely observed.
    struct SkillInspector: View {
        let skill: Skill
        let response: SkillsResponse
        @Bindable var board: SkillsBoardModel

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: SkillsBoardMetrics.gap) {
                    identity
                    if let description = skill.description, !description.isEmpty {
                        section("Description") {
                            Text(description)
                                .typeRole(.body)
                                .foregroundStyle(ColorToken.t1.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    section("Installed into") {
                        VStack(alignment: .leading, spacing: SkillsBoardMetrics.labelGap) {
                            ForEach(
                                Array(SkillPresentation.clientSentences(for: skill, in: response)
                                    .enumerated()),
                                id: \.offset
                            ) { index, line in
                                Text(line)
                                    .typeRole(.body)
                                    // The first line is what it IS in; the rest are what it is not,
                                    // which are quieter facts and are tiered accordingly.
                                    .foregroundStyle(index == 0 ? ColorToken.t1.color : ColorToken.t3.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    versionSection
                    sourceSection
                    provenanceSection
                    autoUpdateSection
                    actions
                }
                .padding(SkillsBoardMetrics.rowPadding * 2)
            }
            .frame(width: SkillsBoardMetrics.inspectorWidth)
        }

        private var identity: some View {
            HStack(spacing: SkillsBoardMetrics.rowPadding) {
                SkillTile(skill: skill)
                    .scaleEffect(1.5)
                    .frame(width: SkillsBoardMetrics.tile * 1.5, height: SkillsBoardMetrics.tile * 1.5)
                VStack(alignment: .leading, spacing: SkillsBoardMetrics.hairline) {
                    Text(skill.name)
                        .typeRole(.title3)
                        .foregroundStyle(ColorToken.t1.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(SkillPresentation.sourceLine(for: skill))
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        @ViewBuilder
        private var versionSection: some View {
            if let origin = skill.source.pluginOrigin {
                section("Plugin version") {
                    VStack(alignment: .leading, spacing: SkillsBoardMetrics.labelGap) {
                        Text(origin.pluginVersion)
                            .typeRole(.body, monospaced: true)
                            .foregroundStyle(ColorToken.t1.color)
                        if origin.siblingSkillCount > 1 {
                            // Says out loud why thirty rows share one number.
                            Text("Shared with \(origin.siblingSkillCount - 1) other skills from this plugin")
                                .typeRole(.caption)
                                .foregroundStyle(ColorToken.t3.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let held = skill.held, held.wantsMore {
                            Text("\(held.pluginVersion) held for review")
                                .typeRole(.caption)
                                .foregroundStyle(ColorToken.attention.color)
                        }
                    }
                }
            } else {
                section("Version") {
                    VStack(alignment: .leading, spacing: SkillsBoardMetrics.labelGap) {
                        Text("unversioned")
                            .typeRole(.body)
                            .foregroundStyle(ColorToken.t2.color)
                        Text(
                            """
                            Added by hand rather than by a marketplace, so there is no version \
                            recorded anywhere.
                            """
                        )
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        @ViewBuilder
        private var sourceSection: some View {
            if let origin = skill.source.pluginOrigin {
                section("Source") {
                    VStack(alignment: .leading, spacing: SkillsBoardMetrics.labelGap) {
                        Text("\(origin.plugin) · \(origin.marketplace)")
                            .typeRole(.callout, monospaced: true)
                            .foregroundStyle(ColorToken.t2.color)
                            .fixedSize(horizontal: false, vertical: true)
                        if let installed = origin.installedAt {
                            // The date portion of the record's own ISO timestamp. Not reformatted
                            // into a locale style: the value is a reading off a file and trimming
                            // it to its day is the most that can be done without restating it.
                            Text("Installed \(installed.prefix(10))")
                                .typeRole(.caption, monospaced: true)
                                .foregroundStyle(ColorToken.t3.color)
                        }
                        if let commit = origin.commit {
                            Text("commit \(String(commit.prefix(7)))")
                                .typeRole(.caption, monospaced: true)
                                .foregroundStyle(ColorToken.t3.color)
                        }
                    }
                }
            } else {
                section("Path") {
                    Text(skill.path)
                        .typeRole(.caption, monospaced: true)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        @ViewBuilder
        private var provenanceSection: some View {
            if let provenance = skill.provenance {
                section("Owner changed") {
                    // States what is still true before what is worrying. The failure mode of a
                    // supply-chain banner is panic, and the code on disk genuinely has not moved.
                    Text(
                        """
                        When this Mac first saw this marketplace it resolved to \
                        \(provenance.firstSeenSource). It now resolves to \(provenance.currentSource). \
                        The code you have has not changed.
                        """
                    )
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.attention.color)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        /// Item 7 — the marketplace's auto-update setting, with its toggle.
        ///
        /// The setting belongs to the **marketplace**, not to the skill, so it is looked up by the
        /// origin's marketplace name and omitted entirely for a hand-placed skill, which has no
        /// marketplace to have a setting. The toggle ships dimmed: the plan cut P6's writes, and a
        /// control that cannot act dims in place with a discoverable reason rather than vanishing
        /// (§3.4). For a local directory the reason is not "not yet" but "there is nothing to
        /// fetch", which is a permanent fact about that marketplace rather than a temporary one
        /// about this release.
        @ViewBuilder
        private var autoUpdateSection: some View {
            switch SkillPresentation.autoUpdateItem(for: skill, in: board.marketplaces) {
            case .notApplicable:
                EmptyView()
            case let .unread(sentence):
                section("Auto-update") {
                    Text(sentence)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case let .setting(line, reason, isOn):
                section("Auto-update") {
                    ToggleRow(title: line, help: reason, isOn: isOn, disabledReason: reason, set: { _ in })
                }
            }
        }

        private var actions: some View {
            VStack(alignment: .leading, spacing: SkillsBoardMetrics.tightGap) {
                if let held = skill.held, held.wantsMore {
                    Button("Review \(held.pluginVersion)…") {
                        board.sheet = .heldVersion(skillID: skill.id)
                    }
                    .buttonStyle(ProminentButtonStyle())
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(skill.path, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(StandardButtonStyle())
            }
            .padding(.top, SkillsBoardMetrics.tightGap)
        }

        private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: SkillsBoardMetrics.tightGap) {
                // Sentence case, secondary colour — never tracked uppercase (§3.2).
                Text(title)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
