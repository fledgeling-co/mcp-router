#if os(macOS)

    /// The file lists the source-level gates scan, split out of `ShellTestSupport.swift` on
    /// 2026-08-23 when merging M22's two boards took that file to 401 lines against
    /// `swiftlint --strict`'s inherited 400-line default. These four constants are one subject —
    /// what the gates read — and they are the part that grows every time a board is added, so the
    /// cut follows the thing that moves rather than the line count. No entry changed.
    extension ShellTestSupport {
        /// Every file this item added under `MCPRouterUI`, so the source-level gates cannot silently
        /// stop covering one. `shellFileListIsComplete` holds this list to what is on disk.
        static let shellFiles = [
            "app/Sources/MCPRouterUI/Shell/ShellModel.swift",
            "app/Sources/MCPRouterUI/Shell/ShellWindow.swift",
            "app/Sources/MCPRouterUI/Shell/Sidebar.swift",
            "app/Sources/MCPRouterUI/Shell/Readout.swift",
            // M27's foot line, enrolled here rather than merely added to the directory: it is the
            // one element in the shell drawn on every board, so a token or indicator-colour gate
            // that could not see it would be blind on all nine surfaces at once.
            "app/Sources/MCPRouterUI/Shell/SidebarFoot.swift",
            "app/Sources/MCPRouterUI/Shell/ScaffoldPane.swift",
            "app/Sources/MCPRouterUI/Shell/ScrollEdge.swift",
            "app/Sources/MCPRouterUI/Shell/ShellChrome.swift",
            "app/Sources/MCPRouterUI/Shell/ShellCommands.swift",
            "app/Sources/MCPRouterUI/Shell/ShellCommandRouter.swift",
            "app/Sources/MCPRouterUI/Shell/ShellClientFactory.swift",
            "app/Sources/MCPRouterUI/Shell/ShellWindowFrame.swift",
            "app/Sources/MCPRouterUI/Shell/ShellMenuReasons.swift",
            // M8's menu-bar surfaces. Enrolled here rather than merely added to the directory,
            // because these files are the ones a token or indicator-colour gate most needs to
            // scan: the status item is the app's most visible surface and its dot is the busiest
            // use of `--attn` in the product.
            "app/Sources/MCPRouterUI/Shell/MenuBarPopover.swift",
            "app/Sources/MCPRouterUI/Shell/MenuBarStatusItem.swift",
            "app/Sources/MCPRouterUI/Shell/MenuBarRouter.swift",
            // Split out of ShellModel.swift to keep it under the 400-line limit — the limit was
            // met by splitting rather than raised, per this repo's own lesson from R2R.
            "app/Sources/MCPRouterUI/Shell/ShellRestoration.swift",
            // M6's badge lookup, moved out of ShellModel so it cannot mutate the model.
            "app/Sources/MCPRouterUI/Shell/ShellModelBadges.swift",
            // M6's factory. Enrolled here rather than merely added to the directory, because it is
            // the file that decides whether a build may render a fixture — and a fixture reaching a
            // Release build of *this* seam draws a QR code for an endpoint nothing is listening on.
            "app/Sources/MCPRouterUI/Shell/ShellPairingFactory.swift",
            // I6's inbox reach. Enrolled for the same reason M8's menu-bar files are: the band is
            // drawn on the app's most visible surface, and the factory is the file that decides
            // whether a notification centre is talked to at all — `UNUserNotificationCenter.current()`
            // traps in a process with no bundle identifier, which is every `swift test` run.
            "app/Sources/MCPRouterUI/Shell/ShellModelInbox.swift",
            "app/Sources/MCPRouterUI/Shell/ArrivalNotifierFactory.swift",
            "app/Sources/MCPRouterUI/Shell/InboxNotificationDelegate.swift",
            "app/Sources/MCPRouterUI/Shell/MenuBarInboxBand.swift"
        ]

        /// The board files, held separately because a completeness test pins `shellFiles` to the
        /// contents of `Shell/` — a directory listing is the only thing that stops a new file
        /// escaping every source-level gate, and folding two directories into one list would break
        /// that check rather than extend it.
        ///
        /// The gates that read both are the ones about *boundaries* rather than about the shell:
        /// A36's one-channel grep and the indicator-colour declaration. A board is more likely to be
        /// tempted past the control API than the window frame is, because it is the surface with
        /// data to show.
        static let boardFiles = [
            // M6's inbox and pairing surfaces.
            "app/Sources/MCPRouterUI/Boards/InboxBoard.swift",
            "app/Sources/MCPRouterUI/Boards/InboxBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/InboxBoardModel.swift",
            // I6's arrival half, on the same board.
            "app/Sources/MCPRouterUI/Boards/InboxBoardModel+Arrivals.swift",
            "app/Sources/MCPRouterUI/Boards/InboxBoardMetrics.swift",
            "app/Sources/MCPRouterUI/Boards/InboxReviewSheet.swift",
            "app/Sources/MCPRouterUI/Boards/PairingSheet.swift",
            "app/Sources/MCPRouterUI/Boards/PairingSessionModel.swift",
            // M16's Signal Path — the signature element, enrolled in the boundary gates in the
            // same commit that created the files, because a board file nobody listed is a board
            // file every source-level gate is blind to. That is the escape the pin below is about.
            "app/Sources/MCPRouterUI/Boards/SignalPath.swift",
            "app/Sources/MCPRouterUI/Boards/Jack.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoard.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardTable.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardBanners.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardMetrics.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardWrites.swift",
            "app/Sources/MCPRouterUI/Boards/ServerInspector.swift",
            "app/Sources/MCPRouterUI/Boards/ServerInspectorSections.swift",
            "app/Sources/MCPRouterUI/Boards/ServerInspectorControls.swift",
            "app/Sources/MCPRouterUI/Boards/ServerSheets.swift",
            "app/Sources/MCPRouterUI/Boards/SkillsBoard.swift",
            "app/Sources/MCPRouterUI/Boards/SkillsBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/SkillsBoardMetrics.swift",
            "app/Sources/MCPRouterUI/Boards/SkillsBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/SkillInspector.swift",
            "app/Sources/MCPRouterUI/Boards/SkillSheets.swift",
            // Split out of ServerSheets.swift for the same reason. It is also the view M8
            // changed, so keeping it separately gated is the honest arrangement.
            "app/Sources/MCPRouterUI/Boards/ToolChangeCard.swift",
            // M5's Discover pane.
            "app/Sources/MCPRouterUI/Boards/DiscoverBoard.swift",
            "app/Sources/MCPRouterUI/Boards/DiscoverBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/DiscoverBoardMetrics.swift",
            "app/Sources/MCPRouterUI/Boards/DiscoverBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/DiscoverDetailSheet.swift",
            // M7's Evals and Cleanup panes. Enrolled with the rest rather than left in the
            // directory: `boardFileListIsComplete` caught all nine of these sitting outside every
            // source-level gate — the one-channel grep, the raw-design-value scan, the
            // indicator-hue declaration and the entry-motion guard — which is the same escape that
            // list's doc comment was written about after `ServerInspectorSections.swift`.
            "app/Sources/MCPRouterUI/Boards/EvalsBoard.swift",
            "app/Sources/MCPRouterUI/Boards/EvalsBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/EvalsBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/EvalsInspector.swift",
            "app/Sources/MCPRouterUI/Boards/CleanupBoard.swift",
            "app/Sources/MCPRouterUI/Boards/CleanupBoardModel+Provenance.swift",
            "app/Sources/MCPRouterUI/Boards/CleanupBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/CleanupBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/CleanupBoardState.swift",
            "app/Sources/MCPRouterUI/Boards/CleanupSheets.swift",
            "app/Sources/MCPRouterUI/Boards/M7BoardMetrics.swift",
            // M22's Harnesses and Insights. Enrolled in the same commit that created them, for
            // the reason this list exists: a board file nobody listed is a board file the
            // one-channel grep, the raw-design-value scan and the indicator-hue declaration are
            // all blind to, and `boardFileListIsComplete` is what turns that into a red.
            "app/Sources/MCPRouterUI/Boards/HarnessesBoard.swift",
            "app/Sources/MCPRouterUI/Boards/HarnessesBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/HarnessesBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/HarnessSheets.swift",
            "app/Sources/MCPRouterUI/Boards/InsightsBoard.swift",
            "app/Sources/MCPRouterUI/Boards/InsightsBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/InsightsBoardCharts.swift",
            "app/Sources/MCPRouterUI/Boards/M22BoardMetrics.swift"
        ]

        /// M15's Settings window, listed for the same reason `boardFiles` is — and enrolled in the
        /// boundary gates in the same commit that created the directory, because a directory nobody
        /// enrolled is a directory every source-level gate is blind to. That is the escape
        /// `boardFileListIsComplete`'s own docstring was written about after
        /// `ServerInspectorSections.swift`, and `settingsFileListIsComplete` is what stops it here.
        ///
        /// **It spans two directories**, because the seven panes have a subdirectory of their own,
        /// and the completeness pin reads both — `contentsOfDirectory` is not recursive, so a list
        /// pinned to `Settings/` alone would have left `Settings/Panes/` outside every gate while
        /// reporting the directory covered.
        static let settingsFiles = [
            "app/Sources/MCPRouterUI/Settings/SettingsWindow.swift",
            "app/Sources/MCPRouterUI/Settings/SettingsWindowModel.swift",
            "app/Sources/MCPRouterUI/Settings/SettingsMetrics.swift",
            "app/Sources/MCPRouterUI/Settings/SettingsParts.swift",
            "app/Sources/MCPRouterUI/Settings/SettingsPaneRow.swift",
            "app/Sources/MCPRouterUI/Settings/Panes/RouterPane.swift",
            "app/Sources/MCPRouterUI/Settings/Panes/GovernedElsewherePane.swift",
            "app/Sources/MCPRouterUI/Settings/Panes/SecurityPane.swift",
            "app/Sources/MCPRouterUI/Settings/Panes/MenuBarPane.swift",
            "app/Sources/MCPRouterUI/Settings/Panes/AdvancedPane.swift"
        ]

        /// M2's board, listed for the same reason `boardFiles` is.
        ///
        /// It is called out separately because its absence was a live defect rather than a tidiness
        /// point: `neverFadesInFromZero` iterated `shellFiles` only, so the one board whose list
        /// animates insertions was the one file the entry-motion guard could not see, and a row
        /// that faded in from zero passed every gate in the repository.
        static let activityFiles = [
            "app/Sources/MCPRouterUI/Activity/ActivityBoard.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityRow.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityChrome.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityCondition.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityCopy.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityFilterBar.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityInspector.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityModel.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityModel+Merge.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityModel+Presentation.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityResetHistorySheet.swift"
        ]
    }

#endif
