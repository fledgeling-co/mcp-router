#if os(macOS)
    import MCPRouterKit

    /// The Inbox board's sheet, split out because `InboxBoardModel.swift` reached SwiftLint's
    /// 400-line ceiling when M18 added it — the same reason `InboxBoardModel+Arrivals.swift` exists.
    /// The rule is doing its job: this model already carries the queue, the pairing session, the
    /// dispositions and the keyboard, and the sheet is a fifth concern.
    public extension InboxBoardModel {
        /// The board's one open sheet, as the inventory's own type.
        ///
        /// **Computed rather than stored, and that is the point.** This board had two
        /// presentations on two `Bool`-shaped bindings — `sheetItemID != nil` for the review sheet
        /// and `pairing.isOpen` for pairing — and the naive conversion to `.sheet(item:)` is to
        /// store a third flag beside them, which is one more thing that can disagree with the
        /// other two. Deriving instead means there is still exactly one place each answer lives:
        /// the id for the review sheet, and the session for pairing.
        ///
        /// The id also has to keep travelling rather than a captured `InboxItem`. M5's lesson, and
        /// `sheetItem()` below is what honours it: a copy taken when the sheet opened goes stale
        /// the moment a poll changes the row, and the sheet's action then disagrees with the board
        /// about what has already happened.
        ///
        /// Closing routes through `pairing.close()`, never a bare flag write: a code is alive for
        /// five minutes whether or not the inbox is on screen, and `close()` is what stops the
        /// ticker. Writing `isOpen = false` would leave it running against a sheet nobody is
        /// looking at.
        var sheet: RouterSheet.Inbox? {
            get {
                if pairing.isOpen { return .pairPhone }
                if let sheetItemID { return .queuedItem(id: sheetItemID) }
                return nil
            }
            set {
                switch newValue {
                case .pairPhone:
                    pairing.open()
                case let .queuedItem(id):
                    sheetItemID = id
                case nil:
                    if pairing.isOpen { pairing.close() }
                    sheetItemID = nil
                }
            }
        }

        /// Opens the gate `SheetGate` declares for an action rather than a sheet chosen by hand.
        ///
        /// One row of the gate table lands here and it is the widest-radius row in it: approving a
        /// phone-queued install puts executable code on this Mac. `DESIGN.md` §9 — the phone
        /// queues, it never installs — is the reason the decision is taken on this side at all,
        /// and routing it through the table is what keeps a one-click install off a list row.
        @discardableResult
        func request(_ action: SheetGate.Action, subject: String = "") -> RouterSheet.Inbox? {
            guard case .sheet(.queuedDetail) = SheetGate.gate(for: action) else { return nil }
            sheet = .queuedItem(id: subject)
            return sheet
        }

        var selection: String?
    }
#endif
