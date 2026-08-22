#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Cleanup's three sheets: two named-consequence dialogs, both with Cancel leading, and one
    /// that asks for nothing at all.
    ///
    /// `DESIGN.md` §8 says removal is "undoable, never confirmed" — and §9's escalation clause
    /// governs here instead, because neither of these is undoable and M3 already measured why for the
    /// first: `describe()` in `src/control.ts` sends `envKeys: Object.keys(u.env).sort()` — key
    /// *names*, never values. An app that cannot read a secret cannot restore an entry carrying one.
    struct CleanupSheetHost: View {
        @Bindable var board: CleanupBoardModel
        let sheet: RouterSheet.Cleanup

        var body: some View {
            switch sheet {
            case let .removeCandidate(name):
                RemoveServerSheet(board: board, name: name)
            case .resetHistory:
                ResetHistorySheet(board: board)
            case let .provenance(skillPath):
                SkillProvenanceSheet(board: board, skillPath: skillPath)
            }
        }
    }

    /// Removing a server, with the consequence M3 already wrote.
    ///
    /// **The two strings come from `ServersBoardModel` by call, never by copy.** One wording per state
    /// across the app (§6): duplicating the literals here would be the Servers board and this board
    /// telling the user different things about the same act.
    struct RemoveServerSheet: View {
        @Bindable var board: CleanupBoardModel
        let name: String
        @State private var keepHistory = false

        private var candidate: CleanupBoardModel.Candidate? {
            board.candidates.first { $0.kind == .server && $0.key.id == name }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.gap * 2) {
                Text("Remove \(name)?")
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)

                if let candidate {
                    Text(
                        ServersBoardModel.removeToolsConsequence(
                            tools: candidate.tools,
                            isScoped: candidate.isScoped
                        )
                    )
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(
                        ServersBoardModel.removeConsequence(
                            envKeys: candidate.envKeys,
                            headerKeys: candidate.headerKeys
                        )
                    )
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    // The row left the list while its dialog was open — a poll landed and the server
                    // is no longer a candidate. Without a candidate there are no tools and no key
                    // names to state, so there is no consequence to disclose, and §9 does not allow
                    // an irreversible act to be offered without one. The dialog says why instead of
                    // silently dropping the two paragraphs and leaving Remove live.
                    Text(CleanupPresentation.consequenceUnavailable)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Keep its recorded calls", isOn: $keepHistory)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)

                if let error = board.writeError {
                    Text(error.userFacingDescription)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.fail.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer(minLength: 0)
                    // **Escape dismisses, and no key reaches Remove.**
                    //
                    // M18 shipped this row with the two keys swapped: `.cancelAction` on the
                    // destructive button and `.defaultAction` on Cancel, so Escape performed the
                    // removal and Return dismissed — against the spec's *"Return activates the
                    // default; Escape cancels"*, against §9's *"never the default button"*, and
                    // against the comment that used to sit on this line. It is measured rather
                    // than reasoned: `planning/evidence/M18-gapfix-2/escape-shortcut-probe.swift`
                    // builds both shapes and posts a keycode 53, and the shipped one reports
                    // `REMOVE` where the shape below reports `CANCEL`.
                    //
                    // Cancel keeps the filled primary M18 gave it — §3.4's one prominent action
                    // per view, and the disagreement with `RemoveServerDialog` that M18 set out to
                    // close — and carries Escape rather than Return, which is the shape every
                    // other dismissing control in this tree already uses.
                    //
                    // **Nothing here is the default, deliberately.** The same probe measures that
                    // one control cannot hold both shortcuts: SwiftUI keeps the innermost
                    // `.keyboardShortcut` and silently drops the other, both ways round. A sheet
                    // whose only affirmative act is destructive should have no default button, so
                    // Return doing nothing is the correct end of that trade rather than a
                    // casualty of it.
                    Button("Cancel") { board.sheet = nil }
                        .buttonStyle(ProminentButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Remove", role: .destructive) {
                        Task { await board.remove(name, keepHistory: keepHistory) }
                    }
                    .buttonStyle(StandardButtonStyle())
                    .disabled(candidate == nil)
                    .help(candidate == nil ? CleanupPresentation.consequenceUnavailable : "")
                }
            }
            .padding(M7BoardMetrics.panePadding)
            .frame(width: M7BoardMetrics.sheetWidth)
        }
    }

    /// Resetting the call history, which is the pane's own evidence.
    ///
    /// **Why this gets a dialog when it is one button on a toolbar.** `POST /usage/reset` has no
    /// restore endpoint, and pressing it immediately makes every server read as never-used,
    /// repopulates this very list with things in daily use, and trips its own weak-window banner. §9
    /// scales friction to blast radius, and the blast radius here is the whole judgement surface the
    /// pane rests on.
    struct ResetHistorySheet: View {
        @Bindable var board: CleanupBoardModel

        var body: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.gap * 2) {
                Text(CleanupPresentation.resetTitle)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)

                Text(
                    CleanupPresentation.resetConsequence(
                        calls: board.state.reading?.recordedCalls,
                        window: board.window
                    )
                )
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)

                if let error = board.writeError {
                    Text(error.userFacingDescription)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.fail.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer(minLength: 0)
                    Button("Cancel") { board.sheet = nil }
                        .buttonStyle(StandardButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(CleanupPresentation.resetConfirm) {
                        Task { await board.resetHistory() }
                    }
                    .buttonStyle(StandardButtonStyle())
                }
            }
            .padding(M7BoardMetrics.panePadding)
            .frame(width: M7BoardMetrics.sheetWidth)
        }
    }

    /// `Read first…` — what moved, before anything is decided about it.
    ///
    /// **The only sheet on this board that asks for nothing.** Both of the others end in an act
    /// with no undo; this one ends in the reader knowing something, which is why its dismiss button
    /// says "Leave it" rather than "Cancel" — there is nothing here to cancel.
    ///
    /// **It replaces Inspect and Remove on the row rather than joining them**, which is
    /// `prototype.html:961` making the same argument this pane makes everywhere else: a skill whose
    /// marketplace moved since the router first saw it is the one candidate where "never invoked"
    /// is the least interesting thing about it, and one click from that row to a removal dialog is
    /// the click nobody should have.
    ///
    /// **Removal is dimmed here, not absent.** The control API is read-only for skills, so this
    /// dialog could not remove one even if the reader decided to — and §3.4 dims a control in place
    /// with a discoverable reason rather than hiding it. The prototype's `Remove it` button would
    /// have been a control that does nothing.
    struct SkillProvenanceSheet: View {
        @Bindable var board: CleanupBoardModel
        let skillPath: String

        private var skill: Skill? { board.skill(atPath: skillPath) }

        var body: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.gap * 2) {
                Text(CleanupPresentation.provenanceTitle(name: skill?.name ?? skillPath))
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)

                Text(CleanupPresentation.provenanceLede)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)

                if let provenance = skill?.provenance {
                    observations(provenance)
                } else {
                    // The skill left the reading while its sheet was open, or the move was resolved
                    // by a poll that landed since. Either way there is no observation left to show,
                    // and inventing one is the defect this whole sheet exists to avoid.
                    Text(CleanupPresentation.consequenceUnavailable)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DisabledAction(label: "Remove", reason: CheckCopy.skillRemoveDisabled)

                HStack {
                    Spacer(minLength: 0)
                    if let path = skill?.path {
                        // The sheet cannot show the skill itself, and "read first" is not an
                        // instruction anyone can follow from a dialog that only names two URLs.
                        // Same label as the Skills inspector: one wording per action (§6).
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                        }
                        .buttonStyle(StandardButtonStyle())
                    }
                    Button(CleanupPresentation.provenanceDismiss) { board.sheet = nil }
                        .buttonStyle(StandardButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(M7BoardMetrics.panePadding)
            .frame(width: M7BoardMetrics.sheetWidth)
        }

        /// The three fields `SkillProvenance` carries, and nothing the router did not observe.
        private func observations(_ provenance: SkillProvenance) -> some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.gap) {
                VStack(alignment: .leading, spacing: M7BoardMetrics.tightGap) {
                    field(CleanupPresentation.provenanceFirstSeenLabel, provenance.firstSeenSource)
                    // The one value in fail colour, because it is the one that changed.
                    field(
                        CleanupPresentation.provenanceCurrentLabel,
                        provenance.currentSource,
                        tint: ColorToken.fail.color
                    )
                    field(CleanupPresentation.provenanceObservedLabel, provenance.firstSeenAt)
                }

                Text(
                    CheckCopy.ownerChanged(
                        firstSeen: provenance.firstSeenSource,
                        current: provenance.currentSource
                    )
                )
                .typeRole(.body)
                .foregroundStyle(ColorToken.attention.color)
                .fixedSize(horizontal: false, vertical: true)

                Text(CleanupPresentation.provenanceLimit)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func field(_ label: String, _ value: String, tint: Color? = nil) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: M7BoardMetrics.gap) {
                Text(label)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                Spacer(minLength: M7BoardMetrics.gap)
                Text(value)
                    .typeRole(.caption, monospaced: true)
                    .foregroundStyle(tint ?? ColorToken.t2.color)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// One candidate in full, with what can and cannot be done about it.
    struct CleanupInspector: View {
        @Bindable var board: CleanupBoardModel
        let candidate: CleanupBoardModel.Candidate

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: M7BoardMetrics.gap * 2) {
                    VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                        Text(candidate.name)
                            .typeRole(.title3)
                            .foregroundStyle(ColorToken.t1.color)
                        Text("\(candidate.kind.label) · \(candidate.detail)")
                            .typeRole(.caption)
                            .foregroundStyle(ColorToken.t3.color)
                    }

                    VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                        SectionLabel("Why it is here")
                        Text(candidate.reason)
                            .typeRole(.body)
                            .foregroundStyle(ColorToken.t2.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    actions
                }
                .padding(M7BoardMetrics.panePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: M7BoardMetrics.inspectorWidth)
        }

        private var actions: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.gap) {
                SectionLabel("Actions")
                switch candidate.kind {
                case .server:
                    Button("Remove…") {
                        board.request(.removeInstalledCapability, subject: candidate.key.id)
                    }
                    .buttonStyle(StandardButtonStyle())
                case .skill:
                    // Dimmed in place with its reason, never hidden and never offered (§3.4). There
                    // is no code path from this board to a skill write, because the control API has
                    // none.
                    DisabledAction(label: "Remove", reason: CheckCopy.skillRemoveDisabled)
                }
            }
        }
    }
#endif
