#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The shell's state, and the one place it talks to the router.
    ///
    /// **This polls `ControlAPIClient` directly rather than using `ServerStateTracker`, deliberately.**
    /// The tracker's `pollLoop()` is `if let response = try? await client.servers()`, so every typed
    /// `ControlAPIError` is discarded, and with no event stream attached its phase never leaves
    /// `.disconnected`. A shell built on it cannot tell loading from a successful zero-server poll
    /// from offline from unauthorised — which is precisely what A18, A26 and A28 require it to tell
    /// apart. The tracker is left to the boards that want call-record merging, and the defect is
    /// reported rather than fixed here because it is F3's shared surface.
    ///
    /// This stays inside A36: `ControlAPIClient` is still the only channel, and this type opens no
    /// socket, no file and no process of its own.
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
        @ObservationIgnored private let clock: @MainActor () -> Date
        @ObservationIgnored private let store: ShellRestoration

        /// The readout's numbers and the condition it is in.
        public private(set) var readout = ReadoutModel()

        /// The servers the last successful poll reported, for the badge derivations.
        ///
        /// **`nil` is not `[]`.** Empty means the router answered and declares nothing; nil means it
        /// did not answer, and A18 turns on the difference — a badge derived from an empty array
        /// would render a considered zero for a router nobody reached.
        public private(set) var servers: [MCPServer]?

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

        public init(
            client: any ControlAPIClient,
            store: ShellRestoration = .standard,
            clock: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.client = client
            self.store = store
            self.clock = clock
            selection = store.restoredDestination()
            isSidebarVisible = store.restoredSidebarVisible()
        }

        // MARK: - Talking to the router

        /// One poll. The typed error is kept, which is the whole reason this is not the tracker.
        public func refresh(at now: Date) async {
            do {
                let response = try await client.servers()
                servers = response.servers
                readout = readout.applying(response, at: now)
            } catch {
                // A18: the counts go absent rather than to zero, and the badges lose their source
                // entirely. A retained array here would keep drawing badges for a router that is
                // no longer answering.
                servers = nil
                readout = readout.applying(error, at: now)
            }
        }

        /// The poll loop, driven from `.task` so it is cancelled with the view.
        ///
        /// Cancellation ends the loop rather than being swallowed: a sleep that is interrupted means
        /// the window went away, and continuing to poll for it is how a closed window keeps working.
        public func run() async {
            while !Task.isCancelled {
                await refresh(at: clock())
                do {
                    try await Task.sleep(for: Self.pollInterval)
                } catch {
                    return
                }
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

        /// Feeds one scroll-geometry reading in.
        public func observeScroll(offset: Double) {
            scrollEdge.observe(offset: offset)
        }

        /// Selects a destination — the operation `⌘1`–`⌘7` and `⌘,` perform.
        public func select(_ destination: Destination) {
            selection = destination
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
    }
#endif
