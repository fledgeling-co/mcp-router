#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The Cleanup board's state, its proposal, and its two writes.
    ///
    /// **It proposes; the human decides.** Nothing here culls automatically, nothing is tallied as
    /// reclaimed, and no metaphor treats an unused capability as rubbish — a never-used server was
    /// never deleted, and an invocation count cannot tell "unused because worthless" from "unused
    /// because rare but critical".
    @MainActor
    @Observable
    public final class CleanupBoardModel {
        /// One proposed row.
        public struct Candidate: Identifiable, Sendable, Equatable {
            public let key: SubjectKey
            public let name: String
            public let detail: String
            public let reason: String
            /// Only a server carries these; a skill row's removal is disabled with its reason.
            public let tools: Int
            public let envKeys: [String]?
            public let headerKeys: [String]?
            public let isScoped: Bool

            /// Why this one has to be read before it is removed, or `nil` when nothing has moved.
            ///
            /// It carries the router's own sentence — `CheckCopy.originMoved`, the same string the
            /// Checks board publishes for `originUnchanged` — rather than a flag, because the row
            /// has to say what moved and a Bool cannot. Only a skill can carry one: a server has no
            /// marketplace to have moved away from.
            ///
            /// A row with one is a different row. `prototype.html:961` withholds Inspect and Remove
            /// from it and offers `Read first…` in their place, and that is the design making the
            /// same argument this board makes everywhere else — a skill whose origin changed since
            /// install is the one candidate where "never invoked" is the least interesting thing
            /// about it, and removing it without reading why is the decision nobody should be one
            /// click away from.
            public let provenance: String?

            public var id: String { "\(key.kind.rawValue):\(key.id)" }
            public var kind: CheckSubjectKind { key.kind }
        }

        public enum Filter: String, CaseIterable, Sendable, Identifiable {
            case all, servers, skills
            public var id: String { rawValue }
            public var title: String {
                switch self {
                case .all: "All"
                case .servers: "Servers"
                case .skills: "Skills"
                }
            }

            func matches(_ candidate: Candidate) -> Bool {
                switch self {
                case .all: true
                case .servers: candidate.kind == .server
                case .skills: candidate.kind == .skill
                }
            }
        }

        @ObservationIgnored public let client: any ControlAPIClient

        /// Injected for the reason `ActivityModel`'s is: every relative time this board states is
        /// measured from *now*, and a test that has to sleep to reach a boundary is a test that
        /// proves nothing.
        @ObservationIgnored public let clock: @MainActor () -> Date

        public private(set) var state: LoadState = .loading
        public var selection: String?
        public var filter: Filter = .all
        public var search: String = ""
        public var sheet: RouterSheet.Cleanup?

        /// Opens the gate `SheetGate` declares for an action rather than a sheet chosen by hand.
        ///
        /// Two of the gate table's rows land on this board and they are the two with the widest
        /// blast radius it can reach: removing an installed capability, and forgetting the call
        /// record that is this board's own evidence. Routing them through the table is what makes
        /// the table load-bearing — a direct `sheet =` here would be un-gated and would still
        /// compile.
        ///
        /// A capability's origin is not routed: reading where something came from is not an action
        /// and has no blast radius, so it has no row.
        @discardableResult
        public func request(_ action: SheetGate.Action, subject: String = "") -> RouterSheet.Cleanup? {
            guard case let .sheet(kind) = SheetGate.gate(for: action) else { return nil }
            switch kind {
            case .confirmRemove: sheet = .removeCandidate(name: subject)
            case .resetHistory: sheet = .resetHistory
            default: return nil
            }
            return sheet
        }

        public private(set) var focusSearchRequests: Int = 0
        public private(set) var writeError: ControlAPIError?

        public init(
            client: any ControlAPIClient,
            clock: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.client = client
            self.clock = clock
        }

        // MARK: - Reading

        public func load() async {
            do {
                let servers = try await client.servers().servers
                guard !Task.isCancelled else { return }
                var reading = Reading(
                    observedAt: clock(),
                    servers: servers,
                    skills: nil,
                    since: nil,
                    recordedCalls: nil
                )
                do {
                    reading.skills = try await client.skills()
                } catch {
                    guard !Task.isCancelled else { return }
                }
                do {
                    let summary = try await client.usageSummary()
                    reading.since = summary.since
                    reading.recordedCalls = summary.servers.reduce(0) { $0 + $1.calls }
                } catch {
                    // The window is what makes the proposal readable, so its absence is a real gap —
                    // but it must not blank a board whose servers loaded. The subtitle drops the
                    // clause instead, and no number is substituted.
                    guard !Task.isCancelled else { return }
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

        public var window: CleanupPresentation.Window? {
            guard let since = state.reading?.since else { return nil }
            return CleanupPresentation.window(since: since)
        }

        /// The proposal, servers then skills, in the router's own order.
        public var candidates: [Candidate] {
            guard let reading = state.reading else { return [] }
            var rows: [Candidate] = []

            for server in reading.servers {
                guard case let .candidate(reason) = CleanupPresentation.candidacy(for: server) else {
                    continue
                }
                rows.append(
                    Candidate(
                        key: .server(server.name),
                        name: server.name,
                        detail: server.transport.rawValue,
                        reason: reason,
                        tools: server.tools,
                        envKeys: server.envKeys,
                        headerKeys: server.headerKeys,
                        isScoped: !server.projects.isEmpty,
                        // A server has no marketplace, so there is nothing it could have moved from.
                        provenance: nil
                    )
                )
            }

            if let skills = reading.skills {
                for skill in skills.skills {
                    guard case let .candidate(reason) = CleanupPresentation.candidacy(
                        for: skill,
                        clients: skills.clients
                    ) else { continue }
                    rows.append(
                        Candidate(
                            key: .skill(path: skill.path),
                            name: skill.name,
                            detail: skill.source.pluginOrigin.map(\.plugin) ?? "standalone",
                            reason: reason,
                            tools: 0,
                            envKeys: nil,
                            headerKeys: nil,
                            isScoped: false,
                            provenance: Self.provenanceNote(for: skill)
                        )
                    )
                }
            }
            return rows
        }

        /// How many skills the unreadable-client rule held out, and which clients caused it.
        ///
        /// Counted rather than silently dropped: a suspended judgement that looks like an empty
        /// result is the failure this whole rule exists to prevent.
        ///
        /// A named type rather than a tuple so `isEmpty` can say what "nothing to report" means in
        /// one place. Both halves have to be non-empty for the banner to be true: no held-out
        /// skills means there is no suspended judgement to disclose even when a client is
        /// unreadable, and no unreadable client means the count could not have come from this rule.
        public struct HeldOut: Equatable, Sendable {
            public let skills: [Skill]
            public let clients: [String]

            public var count: Int { skills.count }
            public var isEmpty: Bool { skills.isEmpty || clients.isEmpty }
        }

        public var heldOut: HeldOut {
            guard let skills = state.reading?.skills else { return HeldOut(skills: [], clients: []) }
            let unreadable = skills.slotClients.filter { $0.status == .unreadable }
            guard !unreadable.isEmpty else { return HeldOut(skills: [], clients: []) }
            let held = skills.skills.filter {
                CleanupPresentation.candidacy(for: $0, clients: skills.clients).isHeldOut
            }
            return HeldOut(skills: held, clients: unreadable.map(\.displayName))
        }

        public var neverUsedServerCount: Int {
            state.reading?.servers.count(where: \.neverUsed) ?? 0
        }

        public var rows: [Candidate] {
            let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return candidates.filter { candidate in
                guard filter.matches(candidate) else { return false }
                guard !needle.isEmpty else { return true }
                return candidate.name.lowercased().contains(needle)
                    || candidate.detail.lowercased().contains(needle)
            }
        }

        public func count(for filter: Filter) -> Int? {
            let n = candidates.count(where: { filter.matches($0) })
            return n == 0 ? nil : n
        }

        /// The router's own sentence about a moved origin, or `nil`.
        ///
        /// Read through `SkillChecks.originUnchanged` rather than off `skill.provenance` directly,
        /// so this board and the Checks board cannot disagree about what counts as moved. That
        /// check is `.notApplicable` for a standalone skill — it has no marketplace, so an unmoved
        /// origin is not something that can be true of it — and `.passed` when the router recorded
        /// no move. Only `.failed` produces a note here, and its reason is the string the check
        /// already composed.
        static func provenanceNote(for skill: Skill) -> String? {
            let result = SkillChecks.originUnchanged(skill)
            guard result.verdict == .failed else { return nil }
            return result.reason
        }

        /// The skill behind a `Read first…` sheet, or `nil` when the row has left the reading.
        ///
        /// Looked up rather than carried on the sheet case, so the sheet renders what the router
        /// last said rather than a copy taken when the button was pressed — a poll can land while
        /// the sheet is open, and the removal dialog beside it already handles that disappearance
        /// rather than showing a stale claim.
        public func skill(atPath path: String) -> Skill? {
            state.reading?.skills?.skills.first { $0.path == path }
        }

        public func selectedCandidate() -> Candidate? {
            guard let selection else { return nil }
            return candidates.first { $0.id == selection }
        }

        // MARK: - Writing

        /// Removes a server, after its dialog. Never reached for a skill: the control API is
        /// read-only for skills and there is no code path from this board to a skill write.
        public func remove(_ name: String, keepHistory: Bool) async {
            writeError = nil
            do {
                _ = try await client.remove(name, keepHistory: keepHistory)
                sheet = nil
                selection = nil
                await load()
            } catch {
                // The row stays where it is, carrying the router's own message and hint (§5 Error).
                writeError = error
            }
        }

        public func resetHistory() async {
            writeError = nil
            do {
                _ = try await client.resetUsage()
                sheet = nil
                await load()
            } catch {
                writeError = error
            }
        }

        // MARK: - Keys

        /// `Return` opens the inspector — **it does not remove.** The one destructive action on this
        /// board is never the default key, and `DESIGN.md` §3.4 forbids destructive-as-default.
        public func commitDefaultAction() -> Bool {
            selectedCandidate() != nil
        }

        /// `⌘⌫` opens the removal sheet for a selected **server**, and is a no-op for a skill.
        public func requestRemoval() -> Bool {
            guard let candidate = selectedCandidate(), candidate.kind == .server else { return false }
            return request(.removeInstalledCapability, subject: candidate.key.id) != nil
        }

        public func escape() {
            if sheet != nil {
                sheet = nil
            } else {
                selection = nil
            }
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

        /// Why removal is unavailable, when it is. Read by the control and the menu item alike.
        public var removeDisabledReason: String? {
            guard let candidate = selectedCandidate() else { return CheckCopy.removeNeedsServer }
            return candidate.kind == .server ? nil : CheckCopy.skillRemoveDisabled
        }
    }
#endif
