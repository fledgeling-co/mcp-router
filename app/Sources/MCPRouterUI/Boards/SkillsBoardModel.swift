#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The Skills board's own state, and its one read of the router.
    ///
    /// Unlike the Servers board there is no shared tracker to lean on: `ServerStateTracker` is about
    /// servers, and skills have no equivalent because nothing about them streams. So this type owns
    /// its own load state — and owns it in the same four shapes, because those four are what
    /// `DESIGN.md` §5 needs and the Servers board proved they are sufficient.
    ///
    /// **`stale` is the case that earns its keep.** A board that has rows and then loses the router
    /// must neither throw the rows away nor hide the failure; both are wrong, and the second is the
    /// one that ships. Keeping the last reading *and* the live error is what lets the surface say
    /// "these are the last answer, nothing about them is current".
    @MainActor
    @Observable
    public final class SkillsBoardModel {
        public enum LoadState: Sendable {
            /// No answer yet. Not the same as an answer of none.
            case loading
            case loaded(SkillsResponse)
            /// The last good reading, under a live failure.
            case stale(SkillsResponse, ControlAPIError)
            /// Nothing ever loaded.
            case failed(ControlAPIError)

            public var response: SkillsResponse? {
                switch self {
                case let .loaded(response), let .stale(response, _): response
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

        public enum Sheet: Equatable, Sendable, Identifiable {
            case heldVersion(skillID: String)
            case marketplaces

            public var id: String {
                switch self {
                case let .heldVersion(skillID): "held:\(skillID)"
                case .marketplaces: "marketplaces"
                }
            }
        }

        @ObservationIgnored public let client: any ControlAPIClient

        public private(set) var state: LoadState = .loading
        public private(set) var marketplaces: [Marketplace] = []
        public var selection: String?
        public var filter: SkillPresentation.Filter = .all
        public var search: String = ""
        public var sheet: Sheet?
        public private(set) var focusSearchRequests: Int = 0

        public init(client: any ControlAPIClient) {
            self.client = client
        }

        /// One read. Called from `.task`, so it is cancelled with the view rather than outliving it.
        public func load() async {
            do {
                let response = try await client.skills()
                state = .loaded(response)
            } catch {
                // A previous good reading is kept and labelled rather than discarded. Throwing it
                // away would replace a true-but-old board with an empty one, and an empty board is
                // a stronger claim than a stale one.
                if let previous = state.response {
                    state = .stale(previous, error)
                } else {
                    state = .failed(error)
                }
            }
            // The marketplace list is a second, independent read: its failure must not blank the
            // skills board, and the sheet that needs it says so itself if it is missing.
            marketplaces = await (try? client.marketplaces())?.marketplaces ?? []
        }

        public var rows: [Skill] {
            guard let response = state.response else { return [] }
            return SkillPresentation.rows(response.skills, filter: filter, search: search)
        }

        public func selectedSkill() -> Skill? {
            guard let selection, let response = state.response else { return nil }
            return response.skills.first { $0.id == selection }
        }

        /// `Return` commits the view's one default action: reviewing a held version, when the
        /// selection has one. When it does not, there is nothing to commit and the key is ignored
        /// rather than repurposed.
        public func commitDefaultAction() -> Bool {
            guard let skill = selectedSkill(), skill.held?.wantsMore ?? false else { return false }
            sheet = .heldVersion(skillID: skill.id)
            return true
        }

        /// `Esc` dismisses the sheet first, then clears the selection — never both at once.
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
            let next = min(max(index + offset, 0), visible.count - 1)
            selection = visible[next].id
        }

        /// Whether this board may write at all.
        ///
        /// Always false, and stated as a property rather than left implicit so the controls read it
        /// instead of each deciding for itself. M4 ships the board read-only: the writes land in
        /// files the client applications hold open while this app runs, and doing that safely needs
        /// preconditions and an undo that are their own item. Every offer stays visible and dimmed
        /// with `SkillPresentation.writesNotYetAvailable` as its reason (`DESIGN.md` §3.4).
        public var canWrite: Bool { false }
    }
#endif
