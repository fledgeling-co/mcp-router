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

        /// What the menu bar needs to know to enable or dim its items.
        ///
        /// Computed rather than stored, so it cannot disagree with the board it describes.
        ///
        /// **"One source, two readers" is what this comment used to claim, and M29 ended it.** The
        /// tripped question is still asked of the selected server's own placard alone, while
        /// `ServerRowAction.forServer` now short-circuits on the switch above the placard
        /// (`spec-M29.md` 11), so a tripped server the user has disabled offers `Reset Server` in
        /// the menu bar while its own row offers `Enable`. Recorded rather than closed here, and
        /// deliberately: `spec-M29.md` D3 decides that `MenuCommand` is untouched by that item
        /// because the design of record draws the Router menu without a disable command and
        /// changing it would redden M20's counted menu assertions on a surface M29 does not own;
        /// `DEF-M29-b` carries the menu half. Dimming this one predicate would also close the
        /// user-asked reindex route that oracle 5 deliberately keeps open for a disabled server —
        /// `.reset` resolves to `.reindex` whenever `indexError` is set — while leaving
        /// `Review Held Changes` live on the same selection, which `forServer` calls a dead end.
        /// The menu bar's whole disabled behaviour is one decision, and it is not this one's.
        var menuContext: MenuCommand.CommandContext {
            let selected: Bool? = serversBoard.selection.flatMap { name in
                guard let state = trackerState,
                      let server = state.servers.first(where: { $0.name == name })
                else { return nil }
                return server.placard != nil
            }
            return MenuCommand.CommandContext(
                installedDestinations: BoardRegistry.installed,
                selectedServerIsTripped: selected
            )
        }
    }
#endif
