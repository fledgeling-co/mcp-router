#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The shell's state, and the one place it talks to the router via `ServerStateTracker`.
    ///
    /// On `.stale` the tracker holds real servers behind a live error:
    /// - badges keep declared servers;
    /// - readout counts go absent to prevent presenting stale counts as live.
    @MainActor
    @Observable
    public final class ShellModel {
        /// How often the shell asks the router where things stand.
        ///
        /// A16 requires the cadence to be *stated* rather than implied, because a readout with no
        /// declared refresh rate is a readout whose staleness nobody can reason about. Two seconds
        /// is fast enough that a server starting under an agent's call is visible about when it
        /// happens, and slow enough that an idle app is not a busy loop against loopback.
        public static let pollInterval: Duration = .seconds(2)

        @ObservationIgnored public let client: any ControlAPIClient
        /// The retained poll loop. See ``startPolling()`` for why it is not owned by a scene.
        @ObservationIgnored private var pollTask: Task<Void, Never>?
        /// The inbox's own loop, retained for the same reason and started from the same place.
        @ObservationIgnored var inboxTask: Task<Void, Never>?
        /// The one reader of the control API, and the authority on what is running.
        ///
        /// Constructed **poll-only** — `stream` is nil, so the tracker reports `.notConfigured`
        /// rather than a dropped stream. The readout needs running counts, which the poll carries;
        /// the call stream is what M2's Activity board is for, and attaching it here would put a
        /// second subscription behind a surface that renders nothing from it.
        @ObservationIgnored public let tracker: ServerStateTracker
        @ObservationIgnored private let clock: @MainActor () -> Date
        /// Where the shell's restorable state lives. Exposed so the window's frame bridge writes to
        /// the same store the destination does, rather than opening a second one.
        @ObservationIgnored public let store: ShellRestoration

        /// The Servers board's own state.
        ///
        /// Owned here rather than by the view for one reason: a menu command reaches a window
        /// through `@FocusedValue`, and the value it reaches is this model. A board model held in
        /// the content zone's `@State` would be unreachable from `⌘N`, `⌘F`, `⌘R` and `⌘⌫` — which
        /// `DESIGN.md` §3.9 requires to work, because the menu bar is the complete command surface.
        /// It also survives a re-render, so the selection does not reset on every poll.
        @ObservationIgnored public private(set) lazy var serversBoard: ServersBoardModel =
            .forApp(client: client, tracker: tracker)

        /// The Skills board's own state, created once and kept, for the same reason `serversBoard`
        /// is: a menu command has to reach a live board, and a board rebuilt on every render would
        /// drop the user's selection and filter on every poll.
        @ObservationIgnored public private(set) lazy var skillsBoard: SkillsBoardModel =
            .init(client: client)

        /// The Discover board's own state, for the same two reasons as the boards above — and one
        /// more that is specific to it: it owns a debounced search task, and a model rebuilt on
        /// every render would leave that task running against a model nobody reads.
        @ObservationIgnored public private(set) lazy var discoverBoard: DiscoverBoardModel =
            .init(client: client)

        /// The Evals board's state, and the store behind its history.
        ///
        /// The store is created once here rather than per-view for the same reason the board models
        /// are: a store rebuilt on every render would re-read the file on every poll, and the history
        /// section would flicker between "none yet" and its rows.
        @ObservationIgnored public private(set) lazy var evalsBoard: EvalsBoardModel =
            .init(
                client: client,
                store: CheckHistoryStore(directory: CheckHistoryStore.defaultDirectory())
            )

        /// The Cleanup board's state.
        @ObservationIgnored public private(set) lazy var cleanupBoard: CleanupBoardModel =
            .init(client: client)

        /// The Harnesses board's state. `forApp` rather than `init` because this one has a
        /// system-facing closure — revealing a config path the *router* supplied, which is not a
        /// second channel to anything.
        @ObservationIgnored public private(set) lazy var harnessesBoard: HarnessesBoardModel =
            .forApp(client: client)

        /// The Insights board's state.
        @ObservationIgnored public private(set) lazy var insightsBoard: InsightsBoardModel =
            .init(client: client)

        /// The Inbox board's state, and the pairing session hanging off it.
        ///
        /// Owned here for the reasons every board model is — a menu command reaches a window through
        /// `@FocusedValue`, and `Pair iPhone…` is a File-menu command that has to reach a live
        /// session. There is one more reason specific to this board: the pairing session runs a
        /// one-second ticker while a code is alive, and a model rebuilt on every render would leave
        /// that ticker running against a model nobody reads.
        ///
        /// **Stored rather than `lazy`, and that difference is a bug fix rather than a style
        /// choice.** Every other board here is `lazy` and gets away with it because it is touched
        /// only by `ContentZone`, for the *selected* destination. This one is different:
        /// `badge(for:)` asks it for a count and the sidebar calls `badge(for:)` for all eight
        /// destinations on every render, so a `lazy var` here initialises *during* a view's body —
        /// and initialising lazy storage **mutates** this `@Observable` object, which invalidates
        /// the view currently being evaluated.
        ///
        /// Measured on 2026-08-15 against this build: with `inboxBoard` lazy the window came up
        /// **0 × 0** and the accessibility tree reported no window at all, while the same launch on
        /// `main` gave the expected 980 × 620. The app was running and its `CGWindowList` entry was
        /// present and correctly titled — only its bounds were zero, which is what an unfinished
        /// layout pass looks like from outside. Every unit test passed throughout, and `make
        /// build-mac` succeeded: only the rendered lane could see it.
        ///
        /// Constructing it here costs nothing. Both services are trivial values, and the host name
        /// is no longer resolved at init. The service comes from `ShellPairingFactory`, which is
        /// where the Release-never-renders-a-fixture rule lives.
        @ObservationIgnored public let inboxBoard: InboxBoardModel

        /// The readout's numbers and the condition it is in.
        public private(set) var readout = ReadoutModel()

        /// The servers the last successful poll reported, for the badge derivations.
        ///
        /// **`nil` is not `[]`.** Empty means the router answered and declares nothing; nil means it
        /// did not answer, and A18 turns on the difference — a badge derived from an empty array
        /// would render a considered zero for a router nobody reached.
        public private(set) var servers: [MCPServer]?

        /// The whole of what the tracker last published.
        ///
        /// The shell itself needs only `servers` and the readout, but a board needs the load *kind*
        /// — loading is not an empty result, and stale is not a failure — plus the router-level
        /// facts the response carries. Kept here rather than re-read by each board, so there stays
        /// exactly one reader of the control API however many surfaces render it.
        ///
        /// `nil` only before the first publication.
        public private(set) var trackerState: ServerStateTracker.TrackerState?

        /// The selected destination. Persisted, and restored on the next launch.
        public var selection: Destination {
            didSet {
                guard oldValue != selection else { return }
                // A new surface brings its own insets, so the old resting offset means nothing here.
                scrollEdge.reset()
                store.save(destination: selection)
            }
        }

        /// Whether the sidebar column is showing. Persisted alongside the destination.
        public var isSidebarVisible: Bool {
            didSet {
                guard oldValue != isSidebarVisible else { return }
                store.save(sidebarVisible: isSidebarVisible)
            }
        }

        /// Whether the menu-bar status item is showing. Persisted alongside the destination.
        ///
        /// Observable on the model rather than read from `UserDefaults` by the scene, so the
        /// `MenuBarExtra`'s `isInserted` binding reacts the instant the checkbox changes, and so the
        /// preference has a place a test can reach.
        public var isMenuBarVisible: Bool {
            didSet {
                guard oldValue != isMenuBarVisible else { return }
                store.save(menuBarVisible: isMenuBarVisible)
            }
        }

        /// Whether the popover's queued-item band may install. Persisted the same way.
        ///
        /// Observable on the model rather than read from `UserDefaults` where it is used, so the band
        /// loses its `Approve` the instant the checkbox changes rather than on the next poll — and so
        /// the one preference in this app that opens an install path has a place a test can set.
        public var isApproveFromPopoverEnabled: Bool {
            didSet {
                guard oldValue != isApproveFromPopoverEnabled else { return }
                store.save(approveFromPopover: isApproveFromPopoverEnabled)
            }
        }

        /// The scroll-edge separator's state, and the resting baseline it is measured against.
        public private(set) var scrollEdge = ScrollEdgeState()

        /// The Activity board's state, built on first use and kept for the life of the window.
        ///
        /// It lives here rather than in the content zone's `@State` for one reason: a `@State`
        /// property cannot be initialised from another view's value, and building it inside `body`
        /// would construct a new model — and a new subscription — on every evaluation. `lazy` gives
        /// the one thing both need: nothing is built for a destination the reader never selects, and
        /// what is built is built once.
        ///
        /// The event source is decided by `ShellClientFactory` by exactly the same rule as the
        /// client, so a Debug fixture run never opens a socket to a port with nothing behind it.
        @ObservationIgnored public private(set) lazy var activity = ActivityModel(
            client: client,
            source: eventSource()
        )

        @ObservationIgnored private let eventSource: @MainActor () -> (any ActivityEventSource)?

        public init(
            client: any ControlAPIClient,
            store: ShellRestoration = .standard,
            eventSource: @escaping @MainActor () -> (any ActivityEventSource)? = {
                ShellClientFactory.makeEventSource()
            },
            // Silence by default, and the app passes the real one. The choice needs the process's
            // own bundle identifier, which A36 forbids these files from reading — see
            // `ArrivalNotifierFactory` for why that gate is satisfied rather than amended.
            notifier: any ArrivalNotifier = SilentArrivalNotifier(),
            // `nil` takes the factory's; `makeInboxBoard` carries why this is injectable at all.
            inboxService: (any InboxService)? = nil,
            clock: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.client = client
            self.eventSource = eventSource
            inboxBoard = Self.makeInboxBoard(client: client, notifier: notifier, service: inboxService)
            // Poll-only, and at the shell's own stated cadence rather than the tracker's default —
            // A16 requires the refresh rate the surface actually runs at to be the one named.
            tracker = ServerStateTracker(
                client: client,
                stream: nil,
                pollInterval: Self.pollInterval
            )
            self.store = store
            self.clock = clock
            selection = store.restoredDestination()
            isSidebarVisible = store.restoredSidebarVisible()
            isMenuBarVisible = store.restoredMenuBarVisible()
            isApproveFromPopoverEnabled = store.restoredApproveFromPopover()
        }

        // MARK: - Talking to the router

        /// One poll, taken through the tracker so there is exactly one reader of the control API.
        ///
        /// The tracker owns no single-shot poll — `run()` is a loop — so the call is made here and
        /// handed straight to it. The typed error is passed through rather than caught and
        /// interpreted: `apply(pollFailure:)` is what decides whether this is `.failed` or `.stale`,
        /// and that decision must not exist in two places.
        public func refresh(at now: Date) async {
            do {
                let response = try await client.servers()
                await tracker.apply(poll: response)
            } catch {
                await tracker.apply(pollFailure: error)
            }
            await adopt(tracker.state(), at: now)
        }

        /// The poll loop, driven from `.task` so it is cancelled with the view.
        ///
        /// The tracker polls and publishes; this renders what it publishes. Iterating `updates()`
        /// ends when the tracker's stream finishes, which is what cancellation produces — a sleep
        /// that is interrupted means the window went away, and continuing to poll for it is how a
        /// closed window keeps working.
        public func run() async {
            let updates = await tracker.updates()
            async let polling: Void = tracker.run()
            for await state in updates {
                adopt(state, at: clock())
            }
            await polling
        }

        /// Renders whatever the tracker currently holds, without asking the router anything.
        ///
        /// This is the step `run()` performs on each published update, exposed so a test can drive
        /// the tracker into a state directly — `.stale` in particular, which needs a success and
        /// then a failure and cannot be reached by choosing a fixture.
        public func refreshFromTracker(at now: Date) async {
            await adopt(tracker.state(), at: now)
        }

        /// Renders one tracker state, and holds the line A18 draws.
        ///
        /// `.stale` is the case worth reading twice: the servers are real and keep their badges,
        /// and the counts still go absent, because a count is a claim about now.
        private func adopt(_ state: ServerStateTracker.TrackerState, at now: Date) {
            trackerState = state
            switch state.load {
            case .loading:
                // No answer yet is not an answer of zero. Nothing is written, so the readout stays
                // in its initial loading condition rather than being told something.
                servers = nil
            case let .loaded(list):
                servers = list
                readout = readout.applying(list, at: now)
            case let .failed(error):
                // Nothing has ever loaded, so there are no servers to keep and no badge has a
                // source. A retained array here would keep drawing badges for a router nobody
                // reached.
                servers = nil
                readout = readout.applying(error, at: now)
            case let .stale(list, error):
                servers = list
                readout = readout.applying(error, at: now)
            }
        }

        // MARK: - What the views ask it

        /// The footer's trace line, at the current instant.
        public func traceLabel() -> String? {
            readout.traceLabel(at: clock())
        }

        /// The trace's points, at the current instant.
        public func tracePoints() -> [(x: Double, y: Double)] {
            readout.normalisedPoints(at: clock())
        }

        /// Feeds one scroll-geometry reading in, with the offset it moved from.
        public func observeScroll(previous: Double, offset: Double) {
            scrollEdge.observe(previous: previous, offset: offset)
        }

        /// Selects a destination — the operation `⌘1`–`⌘7` and `⌘,` perform.
        public func select(_ destination: Destination) {
            selection = destination
        }

        /// Puts a server in front of the user, from a surface that is not the window.
        ///
        /// The menu-bar popover's whole job is to be the shortest path to a decision, and the
        /// decision lives on the Servers board. This is that path, expressed as one operation on the
        /// model rather than as three statements in a scene — so a test can assert the resulting
        /// state instead of a sequence of calls, and so `MCPRouterApp.swift`, which no test can
        /// reach, keeps deciding nothing.
        ///
        /// **`openingHeldChange` awaits the diff, and that `await` is the point.** Opening the sheet
        /// takes two operations — setting `sheet` and loading the change — and an implementation
        /// that sets the sheet alone renders "Reading the held descriptions…" forever with the
        /// accept button dimmed. The one press this whole surface exists for would land on a dead
        /// sheet, and a criterion asserting only the sheet case would pass it.
        ///
        /// Only a held change opens a sheet. A server that needs authorising and one that failed to
        /// index land on the board with the row selected and nothing modal in front of them: their
        /// next action is in the inspector, and a sheet the user did not ask for is a sheet that
        /// gets dismissed rather than read.
        public func reveal(server name: String, openingHeldChange: Bool) async {
            selection = .servers
            serversBoard.selection = name
            guard openingHeldChange else {
                serversBoard.sheet = nil
                return
            }
            serversBoard.request(.acceptHeldChanges, subject: name)
            await serversBoard.loadHeldChanges(name)
        }

        /// Starts the poll loop, once.
        ///
        /// **Why the model owns this rather than a scene.** `run()` used to be driven by
        /// `ShellWindow`'s `.task`, which cancels when the window goes away — correct while the
        /// window was the only surface, and the reasoning was written down as such. M8 adds a
        /// menu-bar item whose normal operating state is *window-closed*, and a status item whose
        /// dot froze the moment you closed the window would be a glanceable instrument that
        /// silently stops being true.
        ///
        /// So the task is retained here, where the lifetime is the app's, and no scene cancels it.
        /// The cost is a two-second poll against loopback for as long as the app runs, which for an
        /// app whose entire subject is live status is the feature rather than a leak.
        ///
        /// Idempotent, and that matters: `ShellWindow` is its only caller today, but the guard is
        /// what makes a second surface calling it safe — two loops would overlap their requests, so
        /// an older response could land after a newer one. (An earlier version of this comment said
        /// the menu bar called it too. It does not: `MenuBarExtra` renders from the model rather than
        /// driving it, and `LSUIElement` is false, so a window scene exists at launch and starts the
        /// poll.)
        public func startPolling() {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                await self?.run()
            }
            startInboxPolling()
        }

        /// Stops it. Not called by any scene — it exists so a test can end the loop it started, and
        /// so the model does not outlive its own task in a fixture.
        public func stopPolling() {
            pollTask?.cancel()
            pollTask = nil
            stopInboxPolling()
        }
    }

#endif
