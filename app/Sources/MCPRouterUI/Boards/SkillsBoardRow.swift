#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// One skill.
    ///
    /// Every branch in here comes from `SkillPresentation`, which is testable without a host. This
    /// file draws the answers and decides nothing.
    struct SkillsBoardRow: View {
        let skill: Skill
        let response: SkillsResponse
        let isSelected: Bool
        let onReview: () -> Void

        private var version: SkillPresentation.VersionCell {
            SkillPresentation.version(for: skill)
        }

        var body: some View {
            HStack(spacing: SkillsBoardMetrics.rowPadding) {
                SkillTile(skill: skill)

                VStack(alignment: .leading, spacing: SkillsBoardMetrics.hairline) {
                    Text(skill.name)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t1.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    sourceLine
                }
                .frame(width: SkillsBoardMetrics.nameColumn, alignment: .leading)

                SlotRow(skill: skill, clients: response.slotClients)
                    .frame(width: SkillsBoardMetrics.slotsColumn, alignment: .leading)

                Text(version.text)
                    // Monospace is the instrument voice (§2). `unversioned` is deliberately NOT in
                    // it: a version is a value read off a file, and "unversioned" is this app saying
                    // there was no value to read. Setting a statement in the instrument face would
                    // dress it as a reading.
                    .typeRole(
                        version.isInstrument ? .callout : .subheadline,
                        monospaced: version.isInstrument
                    )
                    .foregroundStyle(version.isHeld ? ColorToken.attention.color : ColorToken.t2.color)
                    .lineLimit(1)
                    .frame(width: SkillsBoardMetrics.versionColumn, alignment: .leading)

                Spacer(minLength: 0)

                if skill.held?.wantsMore ?? false, let held = skill.held {
                    Button("Review \(held.pluginVersion)…") { onReview() }
                        .buttonStyle(StandardButtonStyle())
                }
            }
            .padding(.horizontal, SkillsBoardMetrics.rowPadding)
            // A fixed height in every state, so the skeleton and the populated row are the same
            // size and the board does not jump when data lands (§5, Overflow).
            .frame(height: SkillsBoardMetrics.rowHeight)
            .selectionFill(isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }

        @ViewBuilder
        private var sourceLine: some View {
            if let warning = SkillPresentation.provenanceLine(for: skill) {
                // Amber, because "wants a human decision" is exactly what a moved owner means. The
                // colour is never the only signal: the sentence says it too.
                HStack(spacing: SkillsBoardMetrics.labelGap) {
                    IconView(.warn, size: TypeToken.caption.size)
                    Text(warning).lineLimit(1).truncationMode(.tail)
                }
                .typeRole(.caption)
                .foregroundStyle(ColorToken.attention.color)
            } else {
                Text(SkillPresentation.sourceLine(for: skill))
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }

        private var accessibilityLabel: String {
            var parts = [skill.name, SkillPresentation.sourceLine(for: skill), version.text]
            let present = response.slotClients
                .filter { skill.presence[$0.id] == .present }
                .map(\.displayName)
            parts.append(present.isEmpty ? "In no client" : "In \(SkillPresentation.list(present))")
            if let warning = SkillPresentation.provenanceLine(for: skill) { parts.append(warning) }
            return parts.joined(separator: ", ")
        }
    }

    /// The row's artwork.
    ///
    /// `DESIGN.md` §4 forbids a gradient rectangle where authored art belongs, and calls it the
    /// loudest low-fidelity tell available. No marketplace art is fetched by this build — fetching
    /// it is a network read the router does not perform — so every tile here is the drawn monogram
    /// plate the same section prescribes for a marketplace that ships no icon. It is a flat token
    /// fill with the skill's initials, never a gradient.
    struct SkillTile: View {
        let skill: Skill

        private var monogram: String {
            let words = skill.name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            let letters = words.prefix(2).compactMap(\.first)
            return String(letters).uppercased()
        }

        var body: some View {
            RoundedRectangle(cornerRadius: SkillsBoardMetrics.tileRadius, style: .continuous)
                .fill(ColorToken.raised2.color)
                .overlay {
                    Text(monogram)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t2.color)
                }
                .frame(width: SkillsBoardMetrics.tile, height: SkillsBoardMetrics.tile)
                .accessibilityHidden(true)
        }
    }

    /// Which clients hold this skill.
    ///
    /// Driven by the clients the **router** reported as supporting skills, never a list written
    /// here — so a client that gains or loses a skills mechanism changes the board without this
    /// file being edited, and the two clients that have none get no slot rather than an empty one.
    struct SlotRow: View {
        let skill: Skill
        let clients: [SkillClient]

        var body: some View {
            HStack(spacing: SkillsBoardMetrics.labelGap) {
                ForEach(clients) { client in
                    slot(for: client)
                }
            }
        }

        @ViewBuilder
        private func slot(for client: SkillClient) -> some View {
            let state = SkillPresentation.slot(skill, client: client)
            Text(SkillPresentation.slotLabel(for: client))
                .typeRole(.caption, monospaced: true)
                .foregroundStyle(state == .on ? ColorToken.t1.color : ColorToken.t4.color)
                .frame(width: SkillsBoardMetrics.slotWidth, height: TypeToken.body.lineHeight)
                .background {
                    let radius = MetricToken.focusRing.leadingScalar
                    switch state {
                    case .on:
                        RoundedRectangle(cornerRadius: radius).fill(ColorToken.f1.color)
                    case .off:
                        RoundedRectangle(cornerRadius: radius).fill(ColorToken.f3.color)
                    case .unknown:
                        // Dashed, not filled: this client's directory could not be read, so whether
                        // the skill is there is unknown. An "off" pip would assert an absence
                        // nobody checked.
                        RoundedRectangle(cornerRadius: radius)
                            .strokeBorder(
                                ColorToken.lineStrong.color,
                                style: StrokeStyle(
                                    lineWidth: SkillsBoardMetrics.hairline,
                                    dash: [SkillsBoardMetrics.labelGap, SkillsBoardMetrics.labelGap]
                                )
                            )
                    }
                }
                .accessibilityLabel(accessibilityLabel(client: client, state: state))
        }

        private func accessibilityLabel(client: SkillClient, state: SkillPresentation.SlotState) -> String {
            switch state {
            case .on: "In \(client.displayName)"
            case .off: "Not in \(client.displayName)"
            case .unknown: "\(client.displayName) could not be read"
            }
        }
    }

    /// The loading state, at this board's row height.
    ///
    /// A separate type from the shared `SkeletonRows`, which is built on the breaker housing and so
    /// is the Servers board's 56pt row. A skeleton at the wrong height is worse than none: the board
    /// visibly jumps at the moment the data arrives, which reads as a glitch in the data.
    struct SkillSkeletonRows: View {
        var count: Int = 6

        var body: some View {
            VStack(spacing: SkillsBoardMetrics.hairline) {
                ForEach(0 ..< count, id: \.self) { _ in
                    HStack(spacing: SkillsBoardMetrics.rowPadding) {
                        RoundedRectangle(cornerRadius: SkillsBoardMetrics.tileRadius, style: .continuous)
                            .fill(ColorToken.f2.color)
                            .frame(width: SkillsBoardMetrics.tile, height: SkillsBoardMetrics.tile)
                        VStack(alignment: .leading, spacing: SkillsBoardMetrics.tightGap) {
                            bar(width: SkillsBoardMetrics.nameColumn * 0.7, height: TypeToken.body.size)
                            bar(width: SkillsBoardMetrics.nameColumn * 0.45, height: TypeToken.caption.size)
                        }
                        .frame(width: SkillsBoardMetrics.nameColumn, alignment: .leading)
                        bar(width: SkillsBoardMetrics.slotsColumn * 0.86, height: TypeToken.body.size)
                            .frame(width: SkillsBoardMetrics.slotsColumn, alignment: .leading)
                        bar(width: SkillsBoardMetrics.versionColumn * 0.6, height: TypeToken.body.size)
                            .frame(width: SkillsBoardMetrics.versionColumn, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, SkillsBoardMetrics.rowPadding)
                    .frame(height: SkillsBoardMetrics.rowHeight)
                }
            }
            .accessibilityLabel("Loading skills")
        }

        private func bar(width: Double, height: Double) -> some View {
            RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar)
                .fill(ColorToken.f2.color)
                .frame(width: width, height: height)
        }
    }
#endif
