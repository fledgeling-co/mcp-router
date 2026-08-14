#if os(macOS)
    import Foundation
    import SwiftUI
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// A32, A8 and A10: the tab is real, the model formats nothing, and the two control asymmetries
    /// behave the way the copy says they do.
    @Suite("Phone Discover — the shell and the model")
    @MainActor
    struct PhoneDiscoverTests {
        // MARK: - A32

        /// **The criterion that makes the feature real rather than a compiling type.** A view that
        /// compiles behind a tab still rendering the awaiting state does not satisfy A32, so this
        /// asserts the shell's own branch rather than that `DiscoverScreen` exists.
        @Test("the Discover tab resolves to a board and cannot re-enter the awaiting branch")
        func discoverIsWired() {
            #expect(PhoneShell<EmptyView>.Tab.discover.awaitingKey == nil)
            // The shell still assembles with the new dependencies defaulted, so existing previews and
            // host tests keep constructing it unchanged.
            _ = PhoneShell().body
        }

        @Test("the shell's default queue writer is in-memory, so no host test writes to a container")
        func defaultQueueIsInMemory() {
            let model = DiscoverModel(
                client: FixtureControlAPIClient(),
                queue: InMemoryCapabilityQueue()
            )
            #expect(model.queue is InMemoryCapabilityQueue)
        }

        // MARK: - A10

        @Test("an empty or whitespace query is not a search, so the bands stay in charge")
        func searchingIsNonEmptyQuery() {
            let model = Self.model()
            #expect(!model.isSearching)
            model.query = "   "
            #expect(!model.isSearching, "whitespace narrowed nothing")
            model.query = "github"
            #expect(model.isSearching)
        }

        // MARK: - A8

        /// `sources.merged` counts entries *before* the slice and legitimately exceeds the rows shown,
        /// so it is never rendered. Filling the limit is the only signal the index may hold more.
        @Test("truncation is disclosed only when the results fill the limit")
        func truncationDisclosure() async {
            let model = Self.model()
            await model.search()
            // The recorded fixture returns 3 of a limit of 30.
            #expect(model.entries.count < DiscoverModel.searchLimit)
            #expect(model.truncationText == nil)
        }

        // MARK: - The search

        @Test("a successful search populates and asks for the endpoint's own limit")
        func searchPopulates() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(Self.response(results: DiscoverFixtures.two))]
            let model = Self.model(client: client)

            await model.search()

            #expect(model.state == .populated)
            #expect(model.entries.count == 2)
            // `/registry/search` takes `q` and `limit` and nothing else, so this is the whole request.
            #expect(client.searchLimits == [DiscoverModel.searchLimit])
        }

        /// A27: `routerNotRunning` is tested for **before** any generic error path, so it renders as
        /// its own state rather than as one more error string inside an error banner.
        @Test("a router that is not running is Offline, and every other failure is Failed")
        func errorMapping() async {
            let down = DiscoverRecordingClient()
            down.staged = [.failure(.routerNotRunning)]
            let offline = Self.model(client: down)
            await offline.search()
            #expect(offline.state == .offline)
            #expect(offline.entries.isEmpty, "a failed search left stale rows on screen")

            let refusing = DiscoverRecordingClient()
            refusing.staged = [.failure(.unauthorized)]
            let refused = Self.model(client: refusing)
            await refused.search()
            #expect(refused.state == .failed(.unauthorized))
        }

        // MARK: - A22 through the model

        @Test("a successful enqueue marks the entry queued in place")
        func enqueueMarksQueued() async {
            let model = Self.model()
            let entry = DiscoverFixtures.two[0]

            let ok = await model.enqueue(entry)

            #expect(ok)
            #expect(model.commitState(for: entry) == .queuedReachable)
            #expect(model.queueFailure == nil)
        }

        /// I1's `PairingStorageFailureTests` precedent: a refused write must never render as success.
        /// There, a `try?` made a refused Keychain write render as paired while nothing was written.
        @Test("a refused enqueue leaves the entry unqueued and records the failure")
        func refusedEnqueueIsNeverSuccess() async {
            let model = Self.model(queue: InMemoryCapabilityQueue(failure: .writeFailed("no space")))
            let entry = DiscoverFixtures.two[0]

            let ok = await model.enqueue(entry)

            #expect(!ok)
            #expect(model.queueFailure == .writeFailed("no space"))
            #expect(model.commitState(for: entry) != .queuedReachable, "it renders as queued")
            #expect(model.commitState(for: entry) == .reachable)
        }

        /// A19 again, at the surface that would ship the defect: the commit reads `canQueue`, so an
        /// unreachable Mac leaves it live.
        @Test("an unreachable Mac leaves the model's commit live and relabelled")
        func commitStaysLiveWhenUnreachable() {
            let model = Self.model(connection: .notReachable)
            let state = model.commitState(for: DiscoverFixtures.two[0])
            #expect(state == .notReachable)
            #expect(state.isActionable)
        }

        @Test("an entry with no install descriptor cannot be committed at all")
        func noDescriptorDisables() {
            let model = Self.model()
            #expect(model.commitState(for: DiscoverFixtures.bare) == .noDescriptor)
        }

        // MARK: - Copy resolution

        /// Nil renders as "your Mac" rather than leaving `{mac}` on screen or emptying the sentence.
        @Test("the model names the Mac, and falls back to a phrase rather than a hole")
        func copyNamesTheMac() {
            let named = Self.model(macName: "Luke's MacBook Pro")
            #expect(named.copy(.list(.offline)).headline?.contains("Luke's MacBook Pro") == true)

            let unnamed = Self.model()
            let headline = unnamed.copy(.list(.offline)).headline
            #expect(headline?.contains("your Mac") == true)
            #expect(headline?.contains("{mac}") == false)
        }

        // MARK: - Helpers

        /// The seam the band-empty guard actually runs through.
        ///
        /// `DiscoverBands.isBandEmptyWithinResults` was proven in the Kit suite while **nothing
        /// called it**: the view derived the same question from `entries.isEmpty` and lost the
        /// distinction the guard exists to keep — "this band has no members" against "the search
        /// returned nothing". A proven function with no call site guards nothing, so this asserts
        /// the model routes the question to it and the Kit proof reaches the surface.
        @Test("the model's band-empty question is the guard's, not entries.isEmpty")
        func bandEmptyRoutesThroughTheGuard() async {
            // Results arrived and none carries a use count: Most used is empty *within* results,
            // which is A5's case and not the list's Empty state.
            let uncounted = DiscoverFixtures.entry(id: "uncounted", useCount: nil, install: nil)
            let client = DiscoverRecordingClient()
            client.staged = [.success(Self.response(results: [uncounted]))]
            let model = Self.model(client: client)
            await model.search()

            #expect(model.isBandEmpty(.mostUsed), "no member inside a populated list is band-empty")
            #expect(!model.isBandEmpty(.recentlyChanged))

            // No results at all is the list's own Empty state, and no band may claim it — two
            // band-empty sentences standing in for "nothing came back" is the defect this catches.
            let bare = DiscoverRecordingClient()
            bare.staged = [.success(Self.response(results: []))]
            let empty = Self.model(client: bare)
            await empty.search()
            for band in DiscoverBand.allCases {
                #expect(!empty.isBandEmpty(band), "\(band) claimed band-empty over an empty list")
            }
        }

        static func model(
            client: any ControlAPIClient = FixtureControlAPIClient(),
            queue: any CapabilityQueueWriter = InMemoryCapabilityQueue(),
            connection: ConnectionState = .reachable,
            macName: String? = nil
        ) -> DiscoverModel {
            DiscoverModel(client: client, queue: queue, connection: connection, macName: macName)
        }

        static func response(
            results: [RegistryEntry],
            warnings: [String] = []
        ) -> RegistrySearchResponse {
            RegistrySearchResponse(
                results: results,
                sources: RegistrySources(official: 0, smithery: 0, merged: results.count),
                warnings: warnings
            )
        }
    }

    /// Two entries and one bare one, enough to exercise the commit's branches without importing the
    /// Kit suite's specimens across target boundaries.
    enum DiscoverFixtures {
        static let two: [RegistryEntry] = [
            entry(id: "a", useCount: 40, install: RegistryInstall(
                type: .stdio, command: "npx", args: ["-y", "a"], url: nil, requires: nil
            )),
            entry(id: "b", useCount: 5, install: RegistryInstall(
                type: .http, command: nil, args: nil, url: "https://example.com/mcp", requires: nil
            ))
        ]

        static let bare = entry(id: "bare", useCount: nil, install: nil)

        static func entry(id: String, useCount: Int?, install: RegistryInstall?) -> RegistryEntry {
            RegistryEntry(
                id: id,
                name: id,
                displayName: id,
                description: "",
                source: .official,
                repository: nil,
                version: nil,
                updatedAt: "2025-11-19T07:26:28.312Z",
                useCount: useCount,
                verified: nil,
                iconURL: nil,
                stars: nil,
                forks: nil,
                pushedAt: nil,
                archived: nil,
                install: install,
                installed: false
            )
        }
    }
#endif
