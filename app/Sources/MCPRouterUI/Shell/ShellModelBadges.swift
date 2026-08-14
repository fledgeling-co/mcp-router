#if os(macOS)
    import MCPRouterKit

    /// The sidebar's badge lookup, kept where it cannot mutate the model.
    ///
    /// **Split out by M6 on the seam the bug was on**, though `ShellModel.swift`'s 400-line cap is
    /// what forced the question. The sidebar calls this for all eight destinations on every render,
    /// which makes it the one derivation most likely to be reached from inside a view's body — and
    /// M6 measured what a mutation there costs: initialising a `lazy var` from here left the window
    /// 0 × 0 with no window in the accessibility tree at all, while every unit test still passed.
    ///
    /// A Swift extension can hold methods but not stored properties, so putting it here means the
    /// compiler now refuses the specific mistake that caused that, rather than a comment asking
    /// nobody to make it.
    public extension ShellModel {
        /// This destination's badge, or nil where it may not have one.
        ///
        /// Switched over `BadgeSource` rather than delegating unconditionally, so a source added
        /// later forces a decision here instead of silently returning nil. Inbox is the one
        /// destination whose count is not derived from `servers`: the queue is held by the app, so
        /// the badge reads the board's own rows and cannot disagree with the list it sits beside.
        func badge(for destination: Destination) -> Int? {
            switch destination.badgeSource {
            case .queuedFromPhone: inboxBoard.waitingCount
            case .serversNeedingAttention, .serversNeverUsed, .none:
                destination.badgeCount(from: servers)
            }
        }
    }
#endif
