#if os(macOS)
    import AppKit
    import Foundation
    import MCPRouterKit
    import Observation

    /// The Servers board's own state, and the one place it writes to the router.
    ///
    /// **It holds no server data.** The servers, the load state, the reap horizon and the pending
    /// authorisation all come from the shell's `ServerStateTracker` and are passed in to the
    /// functions below. That is deliberate: a copy here would be a second version of the truth, and
    /// the moment a write succeeded the two would disagree until the next poll. What this type owns
    /// is what the *user* has done — the selection, the search, the filter, the open sheet — plus
    /// the in-flight bookkeeping for its own writes.
    ///
    /// **Nothing is guessed.** A write calls the router and then applies **the server the router
    /// sent back**, through `ServerStateTracker.apply(updated:)` — so the change is visible in place
    /// (`DESIGN.md` §5: macOS does not toast a click) without this type ever writing the value it
    /// merely *expects*. That distinction is the whole product: an optimistic local write would show
    /// a lever rising for a start that failed, which is the same class of lie the feature exists to
    /// remove. A later poll supersedes it, exactly as it supersedes a call record.
    @MainActor
    @Observable
    public final class ServersBoardModel {
        /// Which further view is open, if any.
        ///
        /// `Identifiable` so `.sheet(item:)` can drive it: SwiftUI needs an identity to know that
        /// one sheet has been replaced by another rather than merely changed.
        public enum Sheet: Equatable, Sendable, Identifiable {
            case addServer
            case heldChange(server: String)
            case removeServer(server: String)

            public var id: String {
                switch self {
                case .addServer: "add"
                case let .heldChange(server): "held:\(server)"
                case let .removeServer(server): "remove:\(server)"
                }
            }
        }

        @ObservationIgnored public let client: any ControlAPIClient
        /// The shell's tracker — the one reader of the control API, and now also the place a write's
        /// answer is handed back to. A `PATCH` reply is the router's own statement about that server,
        /// so feeding it in makes the change visible immediately without this type inventing a value
        /// or keeping a second copy of the truth.
        @ObservationIgnored let tracker: ServerStateTracker
        /// Opens a URL. Injected so the authorisation path is exercisable without a browser opening
        /// on whoever is running the tests.
        @ObservationIgnored let openURL: @MainActor (String) -> Void
        /// Asks the user for a directory, returning nil when they cancel.
        ///
        /// Injected for the same reason: scoping a server to a project needs a real path, and there
        /// is no honest default — a path invented here would restrict the server to somewhere the
        /// user never named. A test supplies one; the app opens a panel.
        @ObservationIgnored public let chooseDirectory: @MainActor () -> String?

        public var selection: String?
        public var searchQuery: String = ""
        public var filter: ServerFilter = .all
        public var sheet: Sheet?

        /// Bumped by `⌘F`. A counter rather than a flag, because two consecutive requests to focus
        /// the search field must both be observable — a `Bool` set true twice changes nothing the
        /// second time and the field would not re-take focus.
        public internal(set) var focusSearchRequests = 0

        /// Servers with a write in flight. Their Behaviour controls dim in place with a reason
        /// (`DESIGN.md` §3.4) rather than disappearing or silently accepting a second click.
        public internal(set) var writesInFlight: Set<String> = []

        /// The last failure per server, shown **against that row** rather than as a pane.
        /// `DESIGN.md` §5: errors sit next to the thing that failed.
        public internal(set) var rowErrors: [String: ControlAPIError] = [:]

        /// What the add sheet is currently reporting, including the router's own hint.
        public internal(set) var addFailure: ControlAPIError?
        /// Set when the router refused an add with advice for getting past it — this is what turns
        /// `Add it anyway` on. Never inferred from a status code; only from a hint the router sent.
        public internal(set) var addCanForce = false

        /// The held-change sheet's own load, which is a second request and fails on its own.
        public internal(set) var heldChanges: HeldChanges?
        public internal(set) var heldChangesError: ControlAPIError?
        public internal(set) var isLoadingHeldChanges = false

        public init(
            client: any ControlAPIClient,
            tracker: ServerStateTracker,
            openURL: @escaping @MainActor (String) -> Void = { _ in },
            chooseDirectory: @escaping @MainActor () -> String? = { nil }
        ) {
            self.client = client
            self.tracker = tracker
            self.openURL = openURL
            self.chooseDirectory = chooseDirectory
        }

        /// Requests focus for the search field — the operation `⌘F` performs.
        public func focusSearch() {
            focusSearchRequests += 1
        }

        /// The model the running app uses, with its two system-facing closures.
        ///
        /// **Neither is a second channel to the router**, which is the constraint that matters here:
        /// `NSWorkspace.open` hands a URL the *router* supplied to the user's browser, and
        /// `NSOpenPanel` returns a directory the *user* picked, which is then sent to the router
        /// through `ServerPatch`. Nothing is read from disk and nothing is spoken to but the control
        /// API — which is why neither appears in A36's forbidden set even though this file is
        /// scanned by it.
        @MainActor
        public static func forApp(
            client: any ControlAPIClient,
            tracker: ServerStateTracker
        ) -> ServersBoardModel {
            ServersBoardModel(
                client: client,
                tracker: tracker,
                openURL: { string in
                    // A URL that will not parse is not opened, and nothing is substituted for it. A
                    // fallback path here would send the user somewhere the router never named.
                    guard let url = URL(string: string) else { return }
                    NSWorkspace.shared.open(url)
                },
                chooseDirectory: {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Scope to this project"
                    guard panel.runModal() == .OK else { return nil }
                    return panel.url?.path
                }
            )
        }

        // MARK: - Reading

        /// The rows to draw: the tracker's servers, filtered, searched, in the router's order.
        ///
        /// The router's order is kept rather than sorted. It is the order the config declares, which
        /// is the order the user wrote — and a list that reorders itself as servers start and stop
        /// is a list nobody can point at.
        public func rows(from state: ServerStateTracker.TrackerState) -> [ServerRowModel] {
            state.servers
                .filter { filter.matches($0) && ServerSearch.matches($0, query: searchQuery) }
                .map {
                    ServerRowModel(
                        server: $0,
                        // Passed through, never defaulted. This briefly read `state.idleMs ?? 300_000`
                        // with a comment arguing the fallback was unreachable — but "unreachable in
                        // practice" is not a guarantee, and 300_000 is precisely the prototype's
                        // hardcoded horizon, which `DESIGN.md` §6 forbids this app from displaying as
                        // an observation. `nil` now reaches `ServerSubtitle`, which drops the
                        // countdown rather than counting down to a number nothing sent.
                        idleMs: state.idleMs,
                        pendingAuth: state.pendingAuth
                    )
                }
        }

        /// The Signal Path's rows: **every declared server**, in the router's order, unfiltered.
        ///
        /// Deliberately not `rows(from:)`. The band is the whole signal path — what is wired to the
        /// router right now — and a band that shrank with the segmented control would contradict the
        /// topology line drawn beside it, which counts what is declared. Selecting a jack whose row
        /// the filter hides still opens the inspector, because `selectedServer(in:)` reads the
        /// servers rather than the rows.
        public func bandRows(from state: ServerStateTracker.TrackerState) -> [ServerRowModel] {
            state.servers.map {
                ServerRowModel(server: $0, idleMs: state.idleMs, pendingAuth: state.pendingAuth)
            }
        }

        /// Counts for the segmented control. Taken before the search, so switching filters while
        /// searching does not show a count that contradicts the rows.
        ///
        /// **The live counts are withheld on a reading that is not current, for exactly the reason
        /// the header withholds "1 running".** They were not, and that was the fourth figure this
        /// board displayed without observing: `controls` is rendered inside `populated(staleError:)`,
        /// which serves `.stale` as well as `.loaded`, so a router that had gone quiet still showed
        /// `Running 1` — a present-tense claim about a live child process — roughly thirty points
        /// below a header deliberately refusing to make it. The board broke its own stated rule
        /// twice in one screen.
        ///
        /// The split is the header's split, not a new one. `All` is a count of *declared* servers,
        /// which is configuration and survives a failure to refresh, and `Needs you` is a count of
        /// conditions the router reported — held descriptions, placards, failed indexes, waiting
        /// authorisations — which is the same kind of fact as the header's `unindexed` and does not
        /// evaporate when a poll stops answering. `Running` and `Idle` are claims about what a
        /// process is doing *now*, and nothing that is not answering can support one.
        ///
        /// A withheld count is **absent from the dictionary**, not zero: `ServerFilterBar.label(for:)`
        /// already renders the bare title when there is no count, so the segment reads `Running`
        /// rather than `Running 0`. A zero here would be a fabricated figure, which is the defect
        /// rather than the fix.
        public func counts(from state: ServerStateTracker.TrackerState) -> [ServerFilter: Int] {
            let current = reading(for: state) == .current
            var counts: [ServerFilter: Int] = [:]
            for filter in ServerFilter.allCases where current || !filter.isPresentTense {
                counts[filter] = state.servers.filter { filter.matches($0) }.count
            }
            return counts
        }

        /// How much any figure on this board may claim, derived in **one** place.
        ///
        /// The header and the filter bar disagreed because each decided this for itself. They now
        /// read the same function, so a future load state cannot be honest in one and not the other.
        func reading(for state: ServerStateTracker.TrackerState) -> ServersBoardHeader.Reading {
            switch state.load {
            case .loaded: .current
            case .stale: .stale
            case .loading, .failed: .none
            }
        }

        /// The three figures under the title, and how much they are allowed to claim.
        ///
        /// **Three cases, not a boolean.** The earlier `isCurrent: Bool` collapsed "no poll has
        /// answered yet" into "the reading is not current", so a cold start rendered
        /// `0 tools from 0 servers · last reading, not current` — a fabricated zero *and* a claim
        /// that an earlier reading existed. Both were false, and both were on screen before the
        /// first poll returned.
        ///
        /// `.loaded` is the only load that is a statement about now. `.stale` is real data from a
        /// router that has since gone quiet, so its present-tense figure is withheld but its totals
        /// stand. `.loading` and `.failed` have both never had a poll answer — `LoadState` documents
        /// `.failed` as "none has ever succeeded" — so neither may claim anything at all.
        public func header(from state: ServerStateTracker.TrackerState) -> ServersBoardHeader {
            ServersBoardHeader(servers: state.servers, reading: reading(for: state))
        }

        public func server(named name: String, in state: ServerStateTracker.TrackerState) -> MCPServer? {
            state.servers.first { $0.name == name }
        }

        public func selectedServer(in state: ServerStateTracker.TrackerState) -> MCPServer? {
            guard let selection else { return nil }
            return server(named: selection, in: state)
        }

        /// Whether the Behaviour section may be written to at all.
        ///
        /// A router that is not answering cannot be told anything, and offering a control that will
        /// fail is worse than dimming one that explains itself.
        public func canWrite(to state: ServerStateTracker.TrackerState) -> Bool {
            if case .loaded = state.load { return true }
            return false
        }

        public static let cannotWriteReason =
            "The router isn't answering, so this can't be changed right now."
        public static let applyingReason = "Applying…"
        public static let resetDisabledReason = "Only a tripped server can be reset."

        /// Why the offer to start the router is shown dimmed rather than as a live button.        ///
        /// `ControlAPIError.routerNotRunning` advertises "Start the router" and `DESIGN.md` §5 asks
        /// the offline state to offer it — and nothing in this repository starts a daemon yet; that
        /// is R2R's item. A button that looks live and does nothing is worse than one that dims and
        /// says why (§3.4), and naming a launch command this app does not own would be inventing a
        /// fact about the user's machine. So the offer stands, disabled, with the honest reason.
        public static let cannotStartRouterReason = """
        MCP Router can't start the daemon itself yet. Start it the way you normally do \
        and this fills in on its own.
        """

        /// What removing this server does to the tool lists, which depends on whether it is scoped.
        ///
        /// **The footer was corrected for exactly this claim and the dialog kept making it.** The
        /// old wording was *"Its N tools leave every session's tool list"*, and `visibleTo(u,
        /// opts.cwd)` in `src/manifest.ts` filters a scoped server by the calling session's
        /// directory — so a scoped server was never in every session's list, and saying it leaves
        /// one overstates the consequence of the single irreversible action on this surface. The
        /// footer already carries the honest version two views away.
        ///
        /// A function rather than a branch in the view, so the wording is testable without a host.
        public static func removeToolsConsequence(tools: Int, isScoped: Bool) -> String {
            let noun = tools == 1 ? "tool" : "tools"
            guard isScoped else {
                return "Its \(tools) \(noun) leave every session's tool list."
            }
            return "It is scoped, so its \(tools) \(noun) leave the sessions it is scoped to."
        }

        /// The named consequence of removing a server, which branches on whether the app could ever
        /// put the entry back.
        ///
        /// `DELETE /servers/:name` edits the user's config file, and the control API sends key
        /// *names* only — never values. So a server carrying environment or header values cannot be
        /// restored by this app at all, and a server carrying none can be re-declared exactly. Those
        /// are genuinely different consequences and the dialog says which one applies rather than
        /// warning generically in both cases.
        ///
        /// A function on the model rather than a branch inside the view, so the wording is testable
        /// without a host — which is the difference between a copy rule and a copy hope.
        public static func removeConsequence(envKeys: [String]?, headerKeys: [String]?) -> String {
            let count = (envKeys?.count ?? 0) + (headerKeys?.count ?? 0)
            guard count > 0 else {
                return """
                Nothing secret is stored on this entry, so re-declaring it in your config \
                restores it exactly.
                """
            }
            let noun = count == 1 ? "value is" : "values are"
            return """
            \(count) \(noun) set on this entry — MCP Router can see their names but not their \
            contents, so it cannot put this back. Copy the entry first if you might want it.
            """
        }

        // MARK: - Selection and keys

        /// `Esc`: dismisses the sheet first, then clears the selection (`DESIGN.md` §8).
        public func escape() {
            if sheet != nil {
                sheet = nil
                return
            }
            selection = nil
        }

        public func clearSearch() {
            searchQuery = ""
        }

        public func showAll() {
            filter = .all
            searchQuery = ""
        }
    }
#endif
