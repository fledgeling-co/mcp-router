#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Inbox — what a paired phone has queued, and the only place it can be acted on.
    ///
    /// **The one rule this board is shaped around: nothing arrives installed, and nothing installs
    /// from a list row.** A row opens the review sheet; only the sheet accepts. That is the Mac half
    /// of `DESIGN.md` §9's "the phone queues, it never installs" — the phone's restraint is worth
    /// nothing if the Mac's list has a one-click Install on every row.
    ///
    /// Every branch below reads `InboxCopy` or `RegistryCapability`, both testable without a host.
    /// This file draws answers and decides nothing, which matters most here because the decisions are
    /// security decisions and one buried in a `body` is one nobody can test.
    public struct InboxBoard: View {
        @Bindable private var board: InboxBoardModel

        public init(board: InboxBoardModel) {
            self.board = board
        }

        public var body: some View {
            boardColumn
                .task { await board.load() }
                .onDisappear { board.pairing.stopTicking() }
                .sheet(isPresented: reviewPresented) {
                    if let item = board.sheetItem() {
                        InboxReviewSheet(board: board, item: item)
                    }
                }
                .sheet(isPresented: pairingPresented) {
                    PairingSheet(session: board.pairing)
                }
                .onKeyPress(.escape) {
                    board.escape()
                    return .handled
                }
                .onKeyPress(.return) {
                    board.commitDefaultAction() ? .handled : .ignored
                }
                // `.ignored` when there is nothing to move, so an arrow key on an empty board
                // reaches the scroll view instead of being swallowed.
                .onKeyPress(.upArrow) { board.moveSelection(by: -1) ? .handled : .ignored }
                .onKeyPress(.downArrow) { board.moveSelection(by: 1) ? .handled : .ignored }
        }

        /// The pairing sheet's presentation.
        ///
        /// An explicit `Binding` rather than `$board.pairing.isOpen`: `pairing` is a `let`, so
        /// `@Bindable`'s projection cannot reach through it. Closing through `session.close()`
        /// rather than by writing the flag also stops the ticker, which a bare assignment would
        /// leave running against a sheet nobody is looking at.
        private var pairingPresented: Binding<Bool> {
            Binding(
                get: { board.pairing.isOpen },
                set: { if !$0 { board.pairing.close() } }
            )
        }

        /// Bound rather than stored: the model holds the sheet's item **by id**, so the sheet reads
        /// the same row the board does.
        private var reviewPresented: Binding<Bool> {
            Binding(
                get: { board.sheetItemID != nil },
                set: { if !$0 { board.sheetItemID = nil } }
            )
        }

        private var boardColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch board.state {
                case .loading:
                    // **No subtitle here, and that is the point.** Before an answer arrives there
                    // are no rows and no device, so the assembled subtitle would read "Nothing
                    // waiting · no phone paired" — two claims about a queue and a pairing nobody
                    // has observed yet. The badge already refuses exactly this (`waitingCount` is
                    // nil while loading); rendering the sentence anyway made the two derivations
                    // disagree, with the wrong one written out in words. `DESIGN.md` §6.
                    header(subtitle: nil)
                    InboxSkeletonRows()
                    Text(InboxCopy.loadingDetail)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .padding(.top, InboxBoardMetrics.gap)
                case .loaded:
                    populated(staleError: nil)
                case let .stale(_, error):
                    populated(staleError: error)
                case let .failed(error):
                    // Same rule: a failed read observed nothing, so it claims nothing.
                    header(subtitle: nil)
                    MessageState(
                        StateMessage(
                            title: failureTitle(error),
                            detail: failureDetail(error)
                        ),
                        icon: .tray
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(InboxBoardMetrics.panePadding)
            // Pinned to the top: a VStack handed more height than it needs centres itself, and a
            // board reads from its top edge.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        /// The headline for a read failure, derived from the failure rather than fixed.
        ///
        /// **It used to be `routerOfflineTitle` unconditionally**, which meant a queue file this Mac
        /// could not read was announced as "The router isn't running" — a cause the app had not
        /// observed and, for that error, had no reason to suspect. The two conditions have different
        /// recoveries, so they get different headlines; the router copy is kept for the one case
        /// that is actually the router being down.
        private func failureTitle(_ error: InboxServiceError) -> String {
            switch error {
            case .unreadable:
                InboxCopy.unreadableTitle
            case let .registryUnreadable(control):
                control == .routerNotRunning ? InboxCopy.routerOfflineTitle : control.headline
            }
        }

        private func failureDetail(_ error: InboxServiceError) -> String {
            switch error {
            case let .unreadable(detail):
                InboxCopy.readFailure(detail: detail)
            case let .registryUnreadable(control):
                control == .routerNotRunning
                    ? InboxCopy.routerOfflineDetail
                    : InboxCopy.registryFailureDetail
            }
        }

        @ViewBuilder
        private func populated(staleError: InboxServiceError?) -> some View {
            // Read **once** per render and threaded through. `rows` filters and sorts on every
            // access, and reading it separately for the header's count and for the list was work
            // done twice in a body for two values that must never disagree.
            let rows = board.rows

            header(
                subtitle: InboxCopy.subtitle(
                    waiting: rows.count,
                    device: board.pairedDeviceName
                )
            )

            if let staleError {
                Text(failureDetail(staleError))
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, InboxBoardMetrics.gap)
            }

            if rows.isEmpty {
                MessageState(
                    StateMessage(
                        title: InboxCopy.emptyTitle,
                        detail: InboxCopy.emptyDetail,
                        // The one action, and the only one that could change this state: an
                        // unpaired Mac has nothing that could ever arrive.
                        actionLabel: InboxCopy.pairingButton
                    ),
                    icon: .tray
                ) {
                    board.pairing.open()
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: InboxBoardMetrics.hairline) {
                    ForEach(rows) { item in
                        InboxBoardRow(
                            item: item,
                            isSelected: board.selection == item.id,
                            onOpen: {
                                board.selection = item.id
                                _ = board.commitDefaultAction()
                            },
                            onDecline: { board.decline(item) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { board.selection = item.id }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            board.selection = item.id
                            _ = board.commitDefaultAction()
                        })
                    }
                }
            }

            undoLine
        }

        /// The pane's heading. `subtitle` is optional because a state that has observed nothing
        /// says nothing about what is waiting or what is paired.
        private func header(subtitle: String?) -> some View {
            HStack(alignment: .top, spacing: InboxBoardMetrics.gap) {
                VStack(alignment: .leading, spacing: InboxBoardMetrics.labelGap) {
                    Text(InboxCopy.title)
                        .typeRole(.title1)
                        .foregroundStyle(ColorToken.t1.color)
                    // Every part comes from state. The prototype hardcodes a device name; a build
                    // with no pairing must not claim one.
                    if let subtitle {
                        Text(subtitle)
                            .typeRole(.subheadline)
                            .foregroundStyle(ColorToken.t2.color)
                    }
                }
                Spacer(minLength: 0)
                // Quiet, not prominent: §3.4 allows one prominent accent action per view and this
                // board's belongs to the review sheet's accept, not to a settings door.
                Button(InboxCopy.pairingButton) { board.pairing.open() }
                    .buttonStyle(StandardButtonStyle())
            }
            .padding(.bottom, InboxBoardMetrics.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// The report half of §9's reversible-and-reported. In place, never a toast — macOS does not
        /// toast a click (§5).
        ///
        /// The Undo control appears only where there is something to undo. An accept is reported
        /// with the same prominence and no control, because the sentence tells the user where the
        /// reversal actually lives (§8's remove, on Servers) — which is more use than a button that
        /// would return the row to the queue and leave the server installed.
        @ViewBuilder
        private var undoLine: some View {
            if let label = board.undoLabel() {
                HStack(spacing: InboxBoardMetrics.tightGap) {
                    Text(label)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                    if board.isUndoable {
                        Button(InboxCopy.undoAction) { board.undoLastDisposition() }
                            .buttonStyle(StandardButtonStyle())
                    }
                }
                .padding(.top, InboxBoardMetrics.gap)
            }
        }
    }
#endif
