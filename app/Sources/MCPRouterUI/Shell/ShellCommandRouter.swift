#if os(macOS)
    import AppKit
    import MCPRouterKit

    /// What each menu command actually does, and the one place that decision is written.
    ///
    /// **Why this type exists at all.** `app/MCPRouter` is not a SwiftPM target, so nothing there
    /// can be reached by `swift test`. When each menu item carried its own closure — `{ model?
    /// .select(target) }` — the mapping from *command* to *operation* lived in the one module no
    /// test can see, and A23's second half ("⌘2 changes the selected destination") had no evidence
    /// lane except driving the running app.
    ///
    /// That lane turned out to be unavailable without taking the user's screen, and the measurement
    /// is worth recording because it is not obvious. A menu command reaches its window through
    /// `@FocusedValue`, and an **inactive** application has no focused scene — so the value is nil,
    /// the closure runs, and nothing happens. Measured on 2026-08-14 against this build: with the app
    /// launched by `open -g` and Ghostty frontmost, `AXUIElementPerformAction(item, AXPress)` returned
    /// `.success` and the selection did not move, and a `⌘2` posted with `CGEvent.postToPid` did the
    /// same. The dispatch path itself is live — a `⌘H` posted the same way hid the app — so the only
    /// broken link was the focused value. Exercising A23 through the menu therefore requires the app
    /// to be frontmost, and `planning/practices/UI_VERIFICATION.md` rules that out.
    ///
    /// So the decision moves here, where `ShellCommandRouterTests` can assert it directly, and the
    /// assembly layer keeps only the wiring: one generic line per item that names no operation. The
    /// lint gate holds that line in place by forbidding any direct model mutation in `app/MCPRouter`.
    public enum ShellCommandRouter {
        /// What a command does, as a value — so the mapping can be asserted rather than run.
        public enum Operation: Equatable, Sendable {
            /// Make this destination the selected one.
            case select(Destination)
            /// Show or hide the sidebar column.
            case toggleSidebar
            /// macOS's standard About panel.
            case aboutPanel
            /// Nothing, in this build.
            ///
            /// Two different reasons share this case deliberately, because the shell treats them
            /// identically: macOS contributes the item and performs it itself (Cut, Minimize, Quit),
            /// or the surface the command acts on is not installed and the item is disabled and
            /// unreachable. Either way the shell must not invent an operation for it, and A22 is
            /// what proves the disabled ones still appear and still say why.
            case none
            /// Open the Servers board's add sheet — `⌘N`.
            case addServer
            /// Open the Mac's pairing sheet — `Pair iPhone…`.
            ///
            /// M1 shipped the menu item routing to `.none`, which was right while nothing could
            /// answer it. M6 gives it a surface, and this is the moment the item stops being a
            /// disabled promise.
            case openPairing
            /// Put the keyboard in the board's search field — `⌘F`.
            case focusSearch
            /// Clear the selected server's placard, or re-index it — `⌘R`.
            case resetSelectedServer
            /// Open the remove dialog for the selected server — `⌘⌫`.
            case removeSelectedServer
            /// Show the Skills board's marketplaces sheet — `⌘⇧N`.
            case showMarketplaces
            /// Open the `Settings` scene — `⌘,` and `MCP Router ▸ Settings…`.
            ///
            /// **Not a no-op, and the distinction is the whole reason this case exists.** The menu
            /// item is the platform's — declaring the `Settings` scene contributes it, and macOS
            /// performs the actuation, so the app declares no item and no `SettingsLink` for it at
            /// all; a case whose `perform` arm did nothing would make the mapping grep-testable and
            /// nothing more, and would leave
            /// this router structurally unable to open Settings from anywhere else — the menu-bar
            /// popover, an error banner, a future onboarding path. So the arm calls an opener the
            /// window injects, and the clause is behaviourally testable.
            case openSettingsScene
            /// Keep the selected server resident — `Router ▸ Wake Selected Server`, `⌃W`.
            ///
            /// The one Router verb the control API can perform. `warm: true` is the only lever it
            /// offers over whether a child process stays up, and `ServersBoardWrites.setWarm`
            /// already owns the call and its asymmetry, so this routes there rather than issuing a
            /// second `patch` of its own.
            case wakeSelectedServer
            /// Open the held-change sheet for the selected server — `Router ▸ Review Held Changes…`.
            case reviewSelectedHeldChanges
            /// Show the router's log file in the Finder — `Router ▸ Reveal Router Log in Finder`.
            case revealRouterLog
        }

        /// The whole mapping, exhaustive over `MenuCommand` so a new command cannot be added
        /// without a decision being made about what it does.
        ///
        /// **Split into two exhaustive halves, and the shape of the split is the point.** M6's
        /// `pairPhone` pushed this past the linter's complexity limit. The obvious fix — moving the
        /// tail into a helper with a `default:` — was rejected when M4 hit the same wall, and is
        /// still wrong: a `default:` would silently route the next command anybody adds to `.none`,
        /// which is the exact failure this function's shape exists to prevent (a menu item that
        /// appears, does nothing, and explains nothing).
        ///
        /// So both halves stay **exhaustive over the whole enum** and return an optional instead.
        /// Neither carries a `default:`, so a new command fails to compile in *both* places until
        /// someone decides what it does — a slightly stronger guarantee than the single switch gave,
        /// for the same reason it is now two functions. No rule is waived and no limit is raised.
        public static func operation(for command: MenuCommand) -> Operation {
            boardOperation(for: command) ?? shellOperation(for: command)
        }

        /// The commands a board owns. M3's four, M4's one, M6's one.
        ///
        /// Each is a real operation rather than `.none`, which is what makes the menu bar the
        /// complete command surface (§3.9) rather than a list of items the mouse duplicates.
        private static func boardOperation(for command: MenuCommand) -> Operation? {
            switch command {
            case .addServer: .addServer
            case .find: .focusSearch
            case .resetServer: .resetSelectedServer
            case .removeServer: .removeSelectedServer
            case .addMarketplace: .showMarketplaces
            case .pairPhone: .openPairing
            case .wakeServer: .wakeSelectedServer
            case .reviewHeldChanges: .reviewSelectedHeldChanges
            case .selectDestination, .settings, .showSidebar, .about,
                 .hide, .hideOthers, .showAll, .quit, .closeWindow,
                 .undo, .redo, .cut, .copy, .paste, .selectAll,
                 .minimise, .zoom, .bringAllToFront,
                 .exportLibrary,
                 .reindexManifest, .restartRouter, .tripBreaker, .reapChildren,
                 .revealRouterLog, .stopRouter,
                 .updateAllSkills, .runDoctor, .runAllChecks,
                 .help, .whatTheRouterDoes, .reportIssue:
                nil
            }
        }

        /// The shell's own commands, and everything macOS performs for itself.
        private static func shellOperation(for command: MenuCommand) -> Operation {
            switch command {
            case let .selectDestination(destination): .select(destination)
            // macOS is what actuates this from the app menu — the item belongs to the `Settings`
            // scene and the app declares none of its own; the operation is what makes the
            // mapping assertable and what lets anything else in the app open the window. M8 shipped
            // this as `.select(.settings)`, when Settings was a sidebar destination, and named this
            // as the line that would change.
            case .settings: .openSettingsScene
            case .showSidebar: .toggleSidebar
            case .about: .aboutPanel
            case .revealRouterLog: .revealRouterLog
            // Seven of these are `.featureUnbuilt` in every context, so the item is dimmed and
            // unreachable and `.none` is the honest mapping rather than a placeholder: inventing an
            // operation for a route the control API does not serve is how a menu item comes to lie
            // about being available, which is the defect M14 was raised for.
            case .addServer, .find, .resetServer, .removeServer, .addMarketplace, .pairPhone,
                 .wakeServer, .reviewHeldChanges,
                 .hide, .hideOthers, .showAll, .quit, .closeWindow,
                 .undo, .redo, .cut, .copy, .paste, .selectAll,
                 .minimise, .zoom, .bringAllToFront,
                 .exportLibrary,
                 .reindexManifest, .restartRouter, .tripBreaker, .reapChildren, .stopRouter,
                 .updateAllSkills, .runDoctor, .runAllChecks,
                 .help, .whatTheRouterDoes, .reportIssue:
                .none
            }
        }

        /// Performs a command against the focused window's model.
        ///
        /// The model is optional because `@FocusedValue` is genuinely optional — there may be no
        /// focused shell window when a command fires. A command whose operation needs a model and
        /// has none does nothing, which is the honest outcome: acting on some other window's state
        /// would be worse than not acting.
        @MainActor
        public static func perform(_ command: MenuCommand, on model: ShellModel?) {
            switch operation(for: command) {
            case let .select(destination): model?.select(destination)
            case .toggleSidebar: model?.isSidebarVisible.toggle()
            case .aboutPanel: NSApplication.shared.orderFrontStandardAboutPanel(nil)
            case .addServer:
                // Selecting the destination first, so `⌘N` from any pane lands somewhere the sheet
                // makes sense rather than opening a Servers sheet over the Skills board.
                model?.select(.servers)
                model?.serversBoard.sheet = .addServer
            case .focusSearch:
                focusSearch(on: model)
            case .showMarketplaces:
                // Same rule as `addServer`: land on the board the sheet belongs to first, so the
                // sheet never opens over an unrelated pane.
                model?.select(.skills)
                model?.skillsBoard.sheet = .marketplaces
            case .resetSelectedServer, .removeSelectedServer,
                 .wakeSelectedServer, .reviewSelectedHeldChanges:
                performServerOperation(operation(for: command), on: model)
            case .openPairing:
                // Same rule as `addServer` and `showMarketplaces`: land on the board the sheet
                // belongs to first, so it never opens over an unrelated pane. Pairing is reachable
                // from the File menu from anywhere, which is what §3.9 asks for.
                model?.select(.inbox)
                model?.inboxBoard.pairing.open()
            // The two that reach neither the model nor a board, split out together to keep this
            // switch under the complexity limit after M20's three arms. Grouped by that fact
            // rather than by subject: both are things the *app* does, and neither can fail for
            // want of a focused window.
            case .revealRouterLog, .openSettingsScene:
                performAppOperation(operation(for: command))
            case .none: break
            }
        }

        /// The operations that need no window and no board.
        @MainActor
        private static func performAppOperation(_ operation: Operation) {
            switch operation {
            case .revealRouterLog: revealRouterLogInFinder()
            case .openSettingsScene: openSettings()
            default: break
            }
        }

        // MARK: - Opening the Settings scene

        /// How this router reaches a scene it cannot see.
        ///
        /// `EnvironmentValues.openSettings` needs a view *inside* a scene, and a menu command is
        /// outside every scene — the same `@FocusedValue` fact this type's own note measured. It is
        /// perfectly reachable from a view inside a scene, so `ShellWindow` installs it on appearance
        /// beside the `ShellMenuReasons.provideContext` line that solves the identical problem for
        /// menu reasons.
        ///
        /// The private `NSApp.sendAction(Selector(("showSettingsWindow:")))` route is deliberately
        /// **not** taken: it is an undocumented selector that was spelled `showPreferencesWindow:`
        /// two releases ago, and `SWIFT_PRACTICES.md` §6 forbids a symbol present in neither this
        /// repo nor a pinned dependency.
        @MainActor private static var settingsOpener: (() -> Void)?

        /// Installed by `ShellWindow` from `@Environment(\.openSettings)`.
        @MainActor
        public static func provideSettingsOpener(_ open: @escaping () -> Void) {
            settingsOpener = open
        }

        /// Opens the scene, or does nothing when no window has installed an opener yet — the same
        /// honest outcome a command with no focused model has.
        @MainActor
        private static func openSettings() {
            settingsOpener?()
        }

        /// `⌘F` on whichever board is showing, split out for the same reason
        /// `performServerOperation` is: a third board's case pushed `perform` past the complexity
        /// limit.
        ///
        /// Focuses the search on the board you are looking at. Before the Skills board existed this
        /// always selected Servers, which was right when Servers was the only board and becomes
        /// wrong the moment there are two: `⌘F` on Skills would have navigated away from the pane
        /// the user was filtering. Discover is the third, and its search is a *query to two
        /// third-party indexes* rather than a local filter — so `⌘F` navigating off it would not
        /// merely move the focus, it would abandon a search the user is composing.
        @MainActor
        private static func focusSearch(on model: ShellModel?) {
            switch model?.selection {
            case .skills:
                model?.skillsBoard.requestSearchFocus()
            case .discover:
                model?.discoverBoard.requestSearchFocus()
            default:
                model?.select(.servers)
                model?.serversBoard.focusSearch()
            }
        }

        /// The two commands that act on the *selected* server, split out to keep `perform` under the
        /// complexity limit.
        ///
        /// **Four since M20**, and the two Router verbs join here rather than getting a function of
        /// their own because they answer the same question: is there a selection to act on. Each
        /// routes to an operation the board already owns rather than issuing its own request —
        /// `setWarm` carries the `warm: true` asymmetry and `reveal` carries the activation the
        /// sheet needs, and a second implementation of either would be a second place for them to
        /// be wrong.
        @MainActor
        private static func performServerOperation(_ operation: Operation, on model: ShellModel?) {
            switch operation {
            case .resetSelectedServer:
                guard let model, let state = model.trackerState,
                      let selected = model.serversBoard.selectedServer(in: state)
                else { return }
                Task { await model.serversBoard.reset(selected) }
            case .removeSelectedServer:
                guard let model, let selection = model.serversBoard.selection else { return }
                model.serversBoard.sheet = .removeServer(server: selection)
            case .wakeSelectedServer:
                guard let model, let selection = model.serversBoard.selection else { return }
                Task { await model.serversBoard.setWarm(selection, to: true) }
            case .reviewSelectedHeldChanges:
                guard let model, let selection = model.serversBoard.selection else { return }
                Task { await model.reveal(server: selection, openingHeldChange: true) }
            default: break
            }
        }

        /// Show the router's log in the Finder.
        ///
        /// The directory is the one `RouterTokenFile` resolves, which is the same directory the
        /// client already resolves to find its token — so the file revealed is the file used rather
        /// than a second guess at where the router keeps things. `SettingsPresentation.RouterFiles`
        /// owns the file name, so the Advanced pane's row and this command cannot name two
        /// different logs.
        ///
        /// **It reveals rather than opens**, and that is the honest verb: the app does not read the
        /// log, has no viewer for it, and handing a possibly-large text file to whatever is
        /// registered for `.log` is a decision belonging to the user's own Finder rather than to
        /// this menu item. `selectFile` also succeeds visibly when the file does not exist yet — it
        /// opens the containing directory — which is the right outcome for a router that has not
        /// written a line yet.
        @MainActor
        private static func revealRouterLogInFinder() {
            let home = RouterTokenFile().url.deletingLastPathComponent()
            let log = home.appendingPathComponent(SettingsPresentation.RouterFiles.logFileName)
            NSWorkspace.shared.selectFile(log.path, inFileViewerRootedAtPath: home.path)
        }
    }
#endif
