import Foundation

/// What a command can do right now, and how it explains itself when it cannot.
///
/// Split out of `MenuCommand.swift` at M20, when the Router and Library menus took that file past
/// its length limit. The split is along the seam the type already had: the cases, their titles and
/// their chords are what the menu *is*, and this is what it can *do* — which is the half that reads
/// the running app's context.
public extension MenuCommand {
    /// Whether this command is usable in the build M1 ships.
    ///
    /// **Kept exactly as it was, and that is deliberate.** This is the answer with no board
    /// installed and nothing selected, which is what `spec-M1.md`'s inventory table records and what
    /// `MenuCommandTests` parses out of it. M3 does not edit this — it adds `availability(in:)`
    /// below, and the live app passes a real context. An additive API leaves M1's contract intact
    /// rather than rewriting a merged spec table to accommodate a later item.
    var availability: CommandAvailability {
        availability(in: .none)
    }

    /// What the live app knows when it builds the menu.
    ///
    /// Two facts, because two are what the *context-dependent* refusals distinguish: whether the
    /// surface a command acts on exists in this build, and whether it has the selection it needs.
    /// `.featureUnbuilt` is deliberately **not** represented here — a feature nobody has written is
    /// not a fact about the running app's state, and giving it a context field would invite a
    /// caller to switch it off, which is the one thing that answer must not be able to do.
    struct CommandContext: Hashable, Sendable {
        public let installedDestinations: Set<Destination>
        /// `nil` when no server is selected; otherwise whether that server is tripped, which is the
        /// only per-server fact any command branches on.
        public let selectedServerIsTripped: Bool?

        public init(installedDestinations: Set<Destination>, selectedServerIsTripped: Bool?) {
            self.installedDestinations = installedDestinations
            self.selectedServerIsTripped = selectedServerIsTripped
        }

        /// No board installed, nothing selected — M1's world, and the default this type answers in.
        public static let none = CommandContext(installedDestinations: [], selectedServerIsTripped: nil)
    }

    /// Whether this command is usable, given what is installed and what is selected.
    ///
    /// **Split into two exhaustive halves, and the shape of the split is the point** — the same
    /// shape `ShellCommandRouter.operation` uses, for the same reason and after the same
    /// provocation. M20's twelve commands pushed the single switch past the complexity limit, and
    /// the obvious fix — a helper with a `default:` — would silently give the next command anybody
    /// adds whatever the last branch returned. Neither half below carries a `default:`, so a new
    /// command fails to compile in *both* until someone decides what it can do. No rule is waived
    /// and no limit is raised.
    func availability(in context: CommandContext) -> CommandAvailability {
        contextualAvailability(in: context) ?? unconditionalAvailability
    }

    /// The commands whose answer depends on what is installed or what is selected.
    ///
    /// - Returns: `nil` for a command no context can change, which the other half answers.
    private func contextualAvailability(in context: CommandContext) -> CommandAvailability? {
        let hasServers = context.installedDestinations.contains(.servers)
        switch self {
        // These two need the Servers board and nothing more.
        case .addServer, .find:
            return hasServers ? .enabled : .surfaceAbsent
        // These act on a selected server, so they need the board *and* a selection. The order
        // matters: with no board at all the honest reason is that the surface does not exist, not
        // that the user failed to select something that cannot be selected.
        case .resetServer:
            guard hasServers else { return .surfaceAbsent }
            // Resetting a server that is not tripped would be a request the router has nothing to
            // do with, so the command dims rather than sending one.
            return context.selectedServerIsTripped == true ? .enabled : .needsServerSelection
        case .removeServer:
            guard hasServers else { return .surfaceAbsent }
            return context.selectedServerIsTripped == nil ? .needsServerSelection : .enabled
        // The two Router verbs that act on a selected server, at M20. Same order as `resetServer`,
        // and the same rule: `Wake Selected Server` is `patch(warm: true)` and `Review Held
        // Changes…` opens the sheet the popover's own band opens, so both need a server to name.
        case .wakeServer, .reviewHeldChanges:
            guard hasServers else { return .surfaceAbsent }
            return context.selectedServerIsTripped == nil ? .needsServerSelection : .enabled
        // Marketplaces live on the Skills board, so this command goes live with that board — the
        // same rule `addServer` follows for Servers. Before M4 it read "this part of the app isn't
        // built yet", which stops being true the moment the board ships; a menu that keeps saying
        // it is the shell disagreeing with its own window.
        case .addMarketplace:
            return context.installedDestinations.contains(.skills) ? .enabled : .surfaceAbsent
        // Pairing's sheet is hosted by the Inbox board: `ShellCommandRouter` selects `.inbox` and
        // then calls `inboxBoard.pairing.open()` — the *same* call the board's own always-enabled
        // `Pairing…` button makes. So this follows `addServer`'s rule with `.inbox` in place of
        // `.servers`, and for the same reason: a menu that refuses what the board underneath it
        // offers is the shell disagreeing with its own window.
        //
        // What this claims is bounded, and deliberately so. `…` means "opens a further view"
        // (`DESIGN.md` §3.4), and the further view exists and ships. It does **not** claim a phone
        // can pair: `ShellPairingFactory` returns `NoTransportInboxService` in every Release build,
        // so the sheet reaches `.noEndpoint` and says "Pairing is not available in this build" —
        // adjacent to the thing, which is where §6 puts it. Were the board's button ever gated on
        // `PairingAvailability`, this would have to be gated the same way.
        case .pairPhone:
            return context.installedDestinations.contains(.inbox) ? .enabled : .surfaceAbsent
        case .about, .settings, .hide, .hideOthers, .showAll, .quit, .closeWindow,
             .undo, .redo, .cut, .copy, .paste, .selectAll,
             .selectDestination, .showSidebar,
             .exportLibrary, .reindexManifest, .restartRouter, .tripBreaker, .reapChildren,
             .revealRouterLog, .stopRouter,
             .updateAllSkills, .runDoctor, .runAllChecks,
             .minimise, .zoom, .bringAllToFront,
             .help, .whatTheRouterDoes, .reportIssue:
            nil
        }
    }

    /// The commands no context can change.
    private var unconditionalAvailability: CommandAvailability {
        switch self {
        // No context makes an unwritten feature exist, so this arm does not ask about one. There is
        // no export surface in either target; this is the product lacking the feature, not this
        // build lacking a board, and the two now have different answers.
        //
        // **M20 adds eight more to it**, and each one is a route the control API does not have
        // rather than a board that has not shipped. `AdvancedPane` already recorded the first:
        // *"Re-indexing is per-server on the control API and there is no bulk endpoint."* The same
        // is true of restarting, stopping and reaping — `src/control.ts` serves `/servers`,
        // `/usage`, `/registry/search` and the per-server verbs, and nothing else. `Trip Selected
        // Breaker` is a route that does not exist on an element M16 retires; `Update All Skills`,
        // `Run Doctor` and `Run All Checks` are bulk verbs over surfaces that only act one subject
        // at a time.
        case .exportLibrary, .reindexManifest, .restartRouter, .tripBreaker, .reapChildren,
             .stopRouter, .updateAllSkills, .runDoctor, .runAllChecks:
            .featureUnbuilt
        case .about, .settings, .hide, .hideOthers, .showAll, .quit, .closeWindow,
             .undo, .redo, .cut, .copy, .paste, .selectAll,
             .selectDestination, .showSidebar,
             // Needs no board and no selection: the path is derived from the same directory the
             // client resolves to find its token, and revealing a file is the Finder's job.
             .revealRouterLog,
             .minimise, .zoom, .bringAllToFront,
             .help, .whatTheRouterDoes, .reportIssue:
            .enabled
        // Every context-dependent command is answered by the other half; reaching this arm would
        // mean one of them started returning nil, which the compiler prevents.
        case .addServer, .find, .resetServer, .removeServer, .addMarketplace, .pairPhone,
             .wakeServer, .reviewHeldChanges:
            .enabled
        }
    }

    /// Why this command cannot be used right now, in words that name **this** command.
    ///
    /// `CommandAvailability.reason` answers generically and every existing reader keeps that
    /// answer; this is what the menu shows. The split is `D-m14-a`'s resolution and the reason for
    /// it is arithmetic: one command carried `.featureUnbuilt` when its sentence was written and
    /// nine carry it now, so *"This feature hasn't been built yet."* would appear nine times in two
    /// menus and tell a reader nothing about which nine features.
    ///
    /// Only `.featureUnbuilt` is specialised. `.surfaceAbsent` and `.needsServerSelection` are
    /// already about a condition rather than about a feature — *which* board is missing is visible
    /// from the item itself — and giving them per-command copy would be nine more strings saying
    /// what one already says.
    func reason(in context: CommandContext = .none) -> String? {
        let availability = availability(in: context)
        guard availability == .featureUnbuilt else { return availability.reason }
        return "\(unbuiltSubject) hasn't been built yet."
    }

    /// What is unbuilt, as the subject of `reason(in:)`'s sentence.
    ///
    /// A noun phrase rather than a whole sentence, so the cadence is stated once and cannot drift
    /// item by item — and so a new `.featureUnbuilt` command has to name its subject rather than
    /// inheriting a sentence that is about something else.
    internal var unbuiltSubject: String {
        switch self {
        case .exportLibrary: "Exporting your library"
        case .reindexManifest: "Re-indexing the whole manifest"
        case .restartRouter: "Restarting the router from here"
        case .tripBreaker: "Tripping a breaker by hand"
        case .reapChildren: "Reaping idle children on demand"
        case .stopRouter: "Stopping the router from here"
        case .updateAllSkills: "Updating every skill at once"
        case .runDoctor: "The doctor"
        case .runAllChecks: "Running every check at once"
        // Not reachable: `reason(in:)` only asks when the answer is `.featureUnbuilt`, and no other
        // command returns it in any context. Spelled as a fallback rather than a `fatalError`
        // because a menu that traps is worse than a menu that is vague, and spelled generically
        // rather than plausibly so a command that starts returning `.featureUnbuilt` without
        // naming its subject reads as unfinished instead of reading as finished.
        default: "This feature"
        }
    }
}
