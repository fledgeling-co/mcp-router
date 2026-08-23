#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The Evals board's state, its two reads, and its one write.
    ///
    /// **The rule this type is built around: no verdict it publishes is ever read from the store.**
    /// `subjects` is computed from `state.response` — the reading the board just fetched — every
    /// time. The store is consulted only for `history(for:)`, which the inspector renders in its own
    /// section, clearly labelled as evidence gathered earlier. That separation is what makes "a stale
    /// verdict cannot render as current" a property of the architecture rather than a promise, and
    /// `M7SourceGuardTests` asserts the row type never reaches the store.
    @MainActor
    @Observable
    public final class EvalsBoardModel {
        /// M4's four shapes, for the same reasons: `stale` is the case that earns its keep, because a
        /// board that has rows and then loses the router must neither throw the rows away nor hide
        /// the failure.
        public enum LoadState: Sendable {
            case loading
            case loaded(Reading)
            case stale(Reading, ControlAPIError)
            case failed(ControlAPIError)

            public var reading: Reading? {
                switch self {
                case let .loaded(reading), let .stale(reading, _): reading
                case .loading, .failed: nil
                }
            }

            public var error: ControlAPIError? {
                switch self {
                case let .stale(_, error), let .failed(error): error
                case .loading, .loaded: nil
                }
            }
        }

        /// One fetch of both endpoints.
        ///
        /// Skills are optional and servers are not: a router too old to serve `/skills` answers 404,
        /// which F3 maps to `malformedResponse`. That must not blank a board whose servers loaded
        /// fine — so the skills half is allowed to be absent and the pane says so, rather than the
        /// whole surface failing over one endpoint.
        public struct Reading: Sendable {
            public var servers: [MCPServer]
            public var skills: SkillsResponse?
            public var skillsError: ControlAPIError?
        }

        @ObservationIgnored public let client: any ControlAPIClient
        @ObservationIgnored public let store: CheckHistoryStore

        public private(set) var state: LoadState = .loading
        public var selection: String?
        public var filter: CheckPresentation.Filter = .all
        public var search: String = ""
        public private(set) var focusSearchRequests: Int = 0
        /// Set while a re-check is in flight, so the control can say so rather than looking inert.
        public private(set) var recheckingSubject: String?
        /// A refused write, reported against the row rather than as a toast.
        public private(set) var writeError: ControlAPIError?

        public init(client: any ControlAPIClient, store: CheckHistoryStore) {
            self.client = client
            self.store = store
        }

        // MARK: - Reading

        public func load() async {
            do {
                let servers = try await client.servers().servers
                guard !Task.isCancelled else { return }
                var reading = Reading(servers: servers, skills: nil, skillsError: nil)
                do {
                    reading.skills = try await client.skills()
                } catch {
                    // Kept, not swallowed: the pane must be able to say the skills half is missing
                    // rather than silently listing servers only (`SWIFT_PRACTICES.md` §3).
                    guard !Task.isCancelled else { return }
                    reading.skillsError = error
                }
                state = .loaded(reading)
            } catch {
                guard !Task.isCancelled else { return }
                if let previous = state.reading {
                    state = .stale(previous, error)
                } else {
                    state = .failed(error)
                }
            }
        }

        /// Every subject, verdicts computed live from the reading just fetched.
        public var subjects: [CheckPresentation.Subject] {
            guard let reading = state.reading else { return [] }
            return CheckPresentation.subjects(servers: reading.servers, skills: reading.skills)
        }

        public var rows: [CheckPresentation.Subject] {
            CheckPresentation.rows(subjects, filter: filter, search: search)
        }

        public func selectedSubject() -> CheckPresentation.Subject? {
            guard let selection else { return nil }
            return subjects.first { $0.id == selection }
        }

        /// The history for one subject. **The only call into the store from this type**, and the
        /// inspector renders what it returns in a section of its own.
        public func history(for subject: CheckPresentation.Subject) -> [StoredRun] {
            store.history(for: subject.key)
        }

        // MARK: - Writing

        /// Re-checks one subject: refresh the observation, then record the run.
        ///
        /// **A server's refresh is `reindex`, which genuinely re-performs the handshake; a skill's is
        /// `skills()`, which re-reads directories.** Exactly one call either way, and no other write
        /// — a skill re-check performs no write at all, because the control API is read-only for
        /// skills.
        public func recheck(_ subject: CheckPresentation.Subject) async {
            recheckingSubject = subject.id
            writeError = nil
            defer { recheckingSubject = nil }

            do {
                switch subject.kind {
                case .server:
                    _ = try await client.reindex(subject.key.id)
                case .skill:
                    break // the reload below is the whole of a skill's re-check
                }
                await load()
            } catch {
                writeError = error
                return
            }

            // Record against the LIVE stamp of the subject as it is after the refresh — and record
            // nothing at all when there is no stamp, which the store enforces structurally.
            guard let refreshed = subjects.first(where: { $0.id == subject.id }) else { return }
            store.record(subject: refreshed.key, stamp: refreshed.stamp, results: refreshed.results)
        }

        public func recheckAll() async {
            for subject in subjects {
                await recheck(subject)
            }
        }

        // MARK: - Keys

        /// `Return` re-checks the selection. Nothing is destructive on this board, so the default
        /// action is the one the pane exists for.
        public func commitDefaultAction() -> Bool {
            selectedSubject() != nil
        }

        /// `Esc` clears the selection.
        ///
        /// **No sheet branch, because this board presents no sheet.** It used to carry a
        /// `Sheet.recheckAll` case that was never assigned and never presented — `EvalsBoard` has
        /// no `.sheet(` modifier at all — so the first arm of this method was unreachable and the
        /// board advertised a sheet it did not have. M18 deleted the enum; this is the reader that
        /// went with it.
        public func escape() {
            selection = nil
        }

        public func requestSearchFocus() {
            focusSearchRequests += 1
        }

        public func moveSelection(by offset: Int) {
            let visible = rows
            guard !visible.isEmpty else { return }
            guard let current = selection, let index = visible.firstIndex(where: { $0.id == current })
            else {
                selection = visible[offset >= 0 ? 0 : visible.count - 1].id
                return
            }
            selection = visible[min(max(index + offset, 0), visible.count - 1)].id
        }

        // MARK: - Enablement reasons

        /// Why re-check is unavailable, when it is. `nil` means available.
        ///
        /// One function, read by both the in-pane control and the menu item, so §3.9's "the menu bar
        /// dims with the same reason" is structural rather than two strings kept in step by hand.
        public var recheckDisabledReason: String? {
            if state.reading == nil { return CheckCopy.runChecksNeedsSelection }
            if selectedSubject() == nil { return CheckCopy.runChecksNeedsSelection }
            return nil
        }
    }
#endif
