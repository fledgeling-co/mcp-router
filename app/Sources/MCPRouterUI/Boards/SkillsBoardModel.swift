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

        @ObservationIgnored public let client: any ControlAPIClient

        public private(set) var state: LoadState = .loading
        public private(set) var marketplaces: [Marketplace] = []
        /// Why the marketplace list is missing, when it is.
        ///
        /// Kept rather than discarded: a `try?` here would leave the sheet unable to tell "you
        /// follow none" from "the router would not say", and those two want different words.
        /// `SWIFT_PRACTICES.md` §3 — never swallow an error to keep a surface tidy.
        public private(set) var marketplacesError: ControlAPIError?
        public var selection: String?
        public var filter: SkillPresentation.Filter = .all
        public var search: String = ""
        public var sheet: RouterSheet.Skills?
        public private(set) var focusSearchRequests: Int = 0
        /// The last held-version write's refusal, in the router's own words. Shown beside the control that
        /// made it, and cleared when the next write starts.
        public private(set) var writeFailure: ControlAPIError?
        /// Whether a held-version write is in flight, so its controls can say so and not start a second one.
        public private(set) var writing = false
        /// What the last write did, in a sentence the sheet reads. Nil until a write succeeds.
        public private(set) var notice: String?
        /// The promotion the board can take back. A promote sets it and its undo clears it.
        public private(set) var lastPromotion: PromotedEntry?

        /// A promotion this board made: the store entry it changed, and the reference its undo needs.
        public struct PromotedEntry: Sendable, Hashable {
            /// The plugin's own name, as the sentence reads it.
            public let plugin: String
            /// The name the router holds the entry under, `<plugin>@<marketplace>`.
            public let name: String
            public let restore: String
        }

        public init(client: any ControlAPIClient) {
            self.client = client
        }

        /// One read. Called from `.task`, so it is cancelled with the view rather than outliving it.
        public func load() async {
            do {
                let response = try await client.skills()
                guard !Task.isCancelled else { return }
                state = .loaded(response)
            } catch {
                // A cancelled `.task` — the view went away — is not a router failure, and must not
                // leave an error banner behind for the next appearance to render.
                guard !Task.isCancelled else { return }
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
            // skills board, so it is caught here rather than allowed to fail the whole load — but
            // it is *kept*, not dropped, so the sheet can say which of the two happened.
            guard !Task.isCancelled else { return }
            do {
                marketplaces = try await client.marketplaces().marketplaces
                marketplacesError = nil
            } catch {
                guard !Task.isCancelled else { return }
                marketplaces = []
                marketplacesError = error
            }
        }

        /// Keep a held version: the router records that it was declined. Plugin-held versions only, because a
        /// standalone skill has no version to hold, so there is nothing to keep.
        public func keepHeldVersion(_ skill: Skill) async {
            guard let origin = skill.source.pluginOrigin, let held = skill.held, beginWrite() else { return }
            defer { writing = false }
            do throws(ControlAPIError) {
                let ack = try await client.keepHeldVersion(
                    origin.storeName, kind: .plugins, pluginVersion: held.pluginVersion
                )
                notice = SkillPresentation.kept(ack.pluginVersion)
            } catch {
                writeFailure = error
            }
        }

        /// Promote a held version over the installed one. The router keeps the copy it replaces, so the
        /// promotion is reversible and needs no confirmation first (`DESIGN.md` §9).
        public func promoteHeldVersion(_ skill: Skill, files: [ExtensionFileBody]) async {
            guard let origin = skill.source.pluginOrigin, let held = skill.held, beginWrite() else { return }
            defer { writing = false }
            do throws(ControlAPIError) {
                let ack = try await client.promote(
                    origin.storeName, kind: .plugins, pluginVersion: held.pluginVersion, files: files
                )
                lastPromotion = PromotedEntry(
                    plugin: origin.plugin,
                    name: origin.storeName,
                    restore: ack.restore
                )
                notice = SkillPresentation.promoted(name: origin.plugin, version: ack.pluginVersion)
                await load()
            } catch {
                writeFailure = error
            }
        }

        /// Put back what the last promotion replaced. A refusal leaves the promotion in place, so the reason
        /// can be read against it.
        public func undoLastPromotion() async {
            guard let promoted = lastPromotion, beginWrite() else { return }
            defer { writing = false }
            do throws(ControlAPIError) {
                let ack = try await client.undoPromotion(
                    promoted.name,
                    kind: .plugins,
                    restore: promoted.restore
                )
                lastPromotion = nil
                notice = SkillPresentation.undone(name: promoted.plugin, version: ack.version)
                await load()
            } catch {
                writeFailure = error
            }
        }

        /// Starts one held-version write, and returns false when one is already in flight so a second press
        /// is
        /// ignored. The previous refusal and notice are cleared first, so a stale one never sits beside a new
        /// outcome.
        private func beginWrite() -> Bool {
            guard !writing else { return false }
            writing = true
            writeFailure = nil
            notice = nil
            return true
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
    }
#endif
