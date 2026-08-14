#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Cleanup's two dialogs, both named-consequence and both with Cancel leading.
    ///
    /// `DESIGN.md` §8 says removal is "undoable, never confirmed" — and §9's escalation clause
    /// governs here instead, because neither of these is undoable and M3 already measured why for the
    /// first: `describe()` in `src/control.ts` sends `envKeys: Object.keys(u.env).sort()` — key
    /// *names*, never values. An app that cannot read a secret cannot restore an entry carrying one.
    struct CleanupSheetHost: View {
        @Bindable var board: CleanupBoardModel
        let sheet: CleanupBoardModel.Sheet

        var body: some View {
            switch sheet {
            case let .removeServer(name):
                RemoveServerSheet(board: board, name: name)
            case .resetHistory:
                ResetHistorySheet(board: board)
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
                    // Cancel leads, and the destructive button is never the default (§9).
                    Button("Cancel") { board.sheet = nil }
                        .buttonStyle(StandardButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Remove") {
                        Task { await board.remove(name, keepHistory: keepHistory) }
                    }
                    .buttonStyle(StandardButtonStyle())
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
                        calls: board.state.reading?.recordedCalls ?? 0,
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

        @ViewBuilder
        private var actions: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.gap) {
                SectionLabel("Actions")
                switch candidate.kind {
                case .server:
                    Button("Remove…") {
                        board.sheet = .removeServer(name: candidate.key.id)
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
