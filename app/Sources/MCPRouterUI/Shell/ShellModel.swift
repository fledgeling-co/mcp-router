#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The shell's state, and the one place it talks to the router.
    ///
    /// **The router's state comes from `ServerStateTracker`, which is now the only thing here that
    /// reads a poll.** An earlier revision polled `ControlAPIClient` directly, because the tracker's
    /// `pollLoop()` was `if let response = try? await client.servers()` — every typed
    /// `ControlAPIError` discarded — and with no event stream its phase never left `.disconnected`.
    /// A shell built on that could not tell loading from a successful zero-server poll from offline
    /// from unauthorised, which is precisely what A18, A26 and A28 require it to tell apart.
    ///
    /// F4 fixed both. `LoadState` is now `.loading` / `.loaded` / `.failed` / `.stale`, the typed
    /// error survives the catch, and a stream-less tracker reports `.notConfigured` rather than
    /// claiming a stream that dropped. The reason for the bypass is gone, and the bypass with it:
    /// two independent poll loops against one router is the duplication the tracker exists to
    /// remove, and the boards that come next have to agree with the shell about what is running.
    ///
    /// **What this type adds on top of the tracker is one judgment**, and it is the product's
    /// central honesty rule rather than a detail. On `.stale` the tracker holds real servers behind
    /// a live error, and the two halves are treated differently:
    ///
    /// - the **badges keep those servers** — "needs attention" and "never used" are properties of
    ///   the declared configuration, and they were genuinely observed;
    /// - the **readout counts go absent**, because "3 running" is a present-tense claim about a
    ///   router that is not currently answering. Showing the last known figure as though it were
    ///   current is a quieter lie than a zero, but the same kind, and A18 forbids it.
    ///
    /// This stays inside A36: the tracker speaks the same loopback control API through F3's client,
    /// and this type opens no socket, no file and no process of its own.
    ///
    /// The clock is injected for the same reason `ReadoutModel`'s is — the 60-second trace window has
    /// a boundary, and a boundary tested against wall-clock time is a test that sleeps for a minute
    /// or proves nothing.
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
            clock: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.client = client
            self.eventSource = eventSource
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

        /// This destination's badge, or nil where it may not have one.
        public func badge(for destination: Destination) -> Int? {
            destination.badgeCount(from: servers)
        }

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

        /// What the menu bar needs to know to enable or dim its items.
        ///
        /// Computed rather than stored, so it cannot disagree with the board it describes. The
        /// tripped question is asked of the selected server's own placard, which is the same fact
        /// the row's Reset action branches on — one source, two readers.
        public var menuContext: MenuCommand.CommandContext {
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

    /// Where the shell's restorable state is kept, and why it is not `@SceneStorage`.
    ///
    /// Apple documents no persistence timing for `@SceneStorage` and states its contents are
    /// destroyed with the scene, so "the selection survives quit and relaunch" is not a promise it
    /// makes. A32 asks for restoration across a *process* boundary, which is `UserDefaults` — written
    /// on change rather than at termination, because a process that is killed rather than quit never
    /// reaches a termination hook.
    ///
    /// The suite is injectable so a test can drive real restoration against a scratch domain instead
    /// of the developer's own preferences, which is the difference between testing this and
    /// corrupting the machine it runs on.
    ///
    /// `@unchecked Sendable` is a promise, and this one is honest and narrow: the struct holds no
    /// mutable state of its own, and `UserDefaults` is documented by Apple as thread-safe — "the
    /// UserDefaults class is thread-safe". `SWIFT_PRACTICES.md` §1 permits the annotation exactly
    /// where the type has no mutable state or guards it with its own lock, and asks for which one
    /// to be said. It is the first.
    public struct ShellRestoration: @unchecked Sendable {
        public static let destinationKey = "shell.selectedDestination"
        public static let sidebarVisibleKey = "shell.sidebarVisible"
        public static let windowFrameKey = "shell.windowFrame"

        private let defaults: UserDefaults

        public init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        public static let standard = ShellRestoration()

        public func restoredDestination() -> Destination {
            // A stored value this build no longer has falls back rather than rendering nothing.
            Destination.restoring(defaults.string(forKey: Self.destinationKey))
        }

        /// The sidebar shows by default, so an absent key must read as `true` rather than as
        /// `Bool`'s zero value — `bool(forKey:)` returns `false` for a key nobody has written, which
        /// would hide the sidebar on every first launch.
        public func restoredSidebarVisible() -> Bool {
            defaults.object(forKey: Self.sidebarVisibleKey) as? Bool ?? true
        }

        public func save(destination: Destination) {
            defaults.set(destination.rawValue, forKey: Self.destinationKey)
        }

        public func save(sidebarVisible: Bool) {
            defaults.set(sidebarVisible, forKey: Self.sidebarVisibleKey)
        }

        /// The window frame this app last had, or nil if it has never stored a usable one.
        ///
        /// Stored as four numbers rather than as an archived `NSRect`, so the value is readable in
        /// `defaults read` and cannot fail to decode across an OS release. A partial, mistyped or
        /// zero-sized entry reads as nil, which falls back to macOS's own placement — a window is
        /// better placed by AppKit than by half a stored frame.
        public func restoredFrame() -> CGRect? {
            guard let numbers = defaults.array(forKey: Self.windowFrameKey) as? [Double],
                  numbers.count == 4,
                  numbers[2] > 0, numbers[3] > 0 else { return nil }
            return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }

        public func save(frame: CGRect) {
            defaults.set(
                [frame.origin.x, frame.origin.y, frame.width, frame.height],
                forKey: Self.windowFrameKey
            )
        }
    }
#endif
