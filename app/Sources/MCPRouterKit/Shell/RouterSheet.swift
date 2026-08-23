import Foundation

/// Every sheet this app can present, as one type.
///
/// The brief's clause is *"the twelve sheets are one enum, so the inventory is a compile-time
/// fact"*, and before this existed the inventory was five per-board enums plus two boards
/// presenting on a `Bool`. Nothing could count them, so nothing noticed that
/// `EvalsBoardModel.Sheet.recheckAll` had never been assigned or presented since it was written.
///
/// **The nesting is what keeps a board from holding another board's sheet.** Each board model
/// types its `sheet` as its own group — `RouterSheet.Servers?`, `RouterSheet.Inbox?` — so its host
/// switches exhaustively with no `default:` arm, and `inboxBoard.sheet = .addServer` fails to
/// compile rather than rendering something at runtime. A flat enum needs either a `default:` in
/// every host (which turns "this board cannot present that" from a compile error into a view) or
/// one shared host, which would have to thread `ShellModel` into the four boards that are
/// deliberately built without it.
///
/// The umbrella is not decoration: it is how the inventory is enumerated across boards, which is
/// what `Kind` is compared against the mock with.
public enum RouterSheet: Equatable, Sendable {
    case servers(Servers)
    case skills(Skills)
    case cleanup(Cleanup)
    case inbox(Inbox)
    case discover(Discover)
    case activity(Activity)
    case settings(Settings)

    /// Servers — adding an upstream, letting a held tool be callable again, removing one.
    public enum Servers: Equatable, Sendable, Identifiable {
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

    /// Skills — a version that asks for more, and the sources capabilities come from.
    public enum Skills: Equatable, Sendable, Identifiable {
        case heldVersion(skillID: String)
        case marketplaces

        public var id: String {
            switch self {
            case let .heldVersion(skillID): "held:\(skillID)"
            case .marketplaces: "marketplaces"
            }
        }
    }

    /// Cleanup — removing an unused capability, forgetting the evidence, a capability's origin.
    public enum Cleanup: Equatable, Sendable, Identifiable {
        case removeCandidate(name: String)
        case resetHistory
        /// Keyed by the skill's resolved **path**, not its name.
        ///
        /// Carried from `CleanupBoardModel.Sheet` with its reason intact: clients hold skills by
        /// symlink into a shared library, so a name is neither unique nor stable and two unrelated
        /// skills can share a directory name. The sheet renders the name it finds at that path.
        case provenance(skillPath: String)

        public var id: String {
            switch self {
            case let .removeCandidate(name): "remove:\(name)"
            case .resetHistory: "reset"
            case let .provenance(skillPath): "prov:\(skillPath)"
            }
        }
    }

    /// Inbox — what a phone queued, and trusting a phone in the first place.
    public enum Inbox: Equatable, Sendable, Identifiable {
        /// Held **by id**, never as a captured `InboxItem`.
        ///
        /// M5's lesson, and the reason converting these two presentations off `isPresented:` was
        /// not a rename: a copy taken when the sheet opened goes stale the moment the row does,
        /// and the sheet's action then disagrees with the board about what has already happened.
        /// The id travels; `InboxBoardModel.sheetItem()` does the lookup on every render.
        case queuedItem(id: String)
        case pairPhone

        public var id: String {
            switch self {
            case let .queuedItem(id): "queued:\(id)"
            case .pairPhone: "pair"
            }
        }
    }

    /// Discover — a catalogue entry, and what the official mark asserts.
    public enum Discover: Equatable, Sendable, Identifiable {
        /// By id, for the same reason `Inbox.queuedItem` is: the sheet must see a completed
        /// install rather than the row as it was when it opened.
        case registryEntry(id: String)
        case officialMark

        public var id: String {
            switch self {
            case let .registryEntry(id): "entry:\(id)"
            case .officialMark: "official"
            }
        }
    }

    /// Activity — forgetting the call record the board is drawn from.
    public enum Activity: Equatable, Sendable, Identifiable {
        case resetHistory

        public var id: String { "reset" }
    }

    /// Settings — where the servers this router starts look for their binaries.
    ///
    /// Its own group because the brief has one requirement with no reference to build against:
    /// *"A sheet opened from the Settings window attaches to the Settings window."* The mock draws
    /// both windows on one page and cannot demonstrate it. Putting this case anywhere else would
    /// put the sheet on the console window.
    public enum Settings: Equatable, Sendable, Identifiable {
        case childPath

        public var id: String { "path" }
    }
}

// MARK: - The inventory

public extension RouterSheet {
    /// The inventory, flattened so it can be compared against the mock.
    ///
    /// Sixteen: the thirteen `id="sh-*"` sheets in `design/mcp-router-console.html`, plus the three
    /// the build draws that the mock does not — resetting the call history, a capability's origin,
    /// and a catalogue entry's detail. `RouterSheetTests` parses the mock and compares both
    /// directions, so a fourteenth sheet drawn there reddens the build, and a case added here with
    /// no sheet in the mock does too.
    ///
    /// The raw values are the mock's own ids, not Swift-cased names, because the comparison is the
    /// whole point of the type.
    enum Kind: String, CaseIterable, Sendable {
        case addMarketplace = "add-marketplace"
        case addServer = "add-server"
        case analyzer
        case capabilityDelta = "capability-delta"
        case confirmRemove = "confirm-remove"
        case official
        case pair
        case path
        case quarantine
        case queuedDetail = "queued-detail"
        case readme
        case recommendation
        case reconcile
        // Drawn by the build, drawn nowhere in the mock. Listed rather than left out: an inventory
        // that counts only what the mock knows about cannot notice a sheet nobody designed.
        case registryDetail = "-registry-detail"
        case resetHistory = "-reset-history"
        case skillProvenance = "-skill-provenance"

        /// The thirteen the mock draws, by its own ids. The three above are excluded by their
        /// leading `-`, which is not a legal HTML id fragment in this file and so cannot collide.
        public static var drawnInMock: [Kind] { allCases.filter { !$0.rawValue.hasPrefix("-") } }

        /// Who closes this sheet, for the four the mock draws and this app cannot host yet.
        ///
        /// `nil` means hosted. A kind that is neither hosted nor owned is a hole, and
        /// `RouterSheetTests` fails on one.
        public var owner: String? {
            switch self {
            case .reconcile, .recommendation, .analyzer: "M22"
            case .readme: "M19"
            default: nil
            }
        }

        /// Whether a `RouterSheet` case exists for this kind.
        public var isHosted: Bool { owner == nil }
    }

    /// Which sheet this is, independent of whose board is presenting it.
    var kind: Kind {
        switch self {
        case let .servers(sheet):
            switch sheet {
            case .addServer: .addServer
            case .heldChange: .quarantine
            case .removeServer: .confirmRemove
            }
        case let .skills(sheet):
            switch sheet {
            case .heldVersion: .capabilityDelta
            case .marketplaces: .addMarketplace
            }
        case let .cleanup(sheet):
            switch sheet {
            case .removeCandidate: .confirmRemove
            case .resetHistory: .resetHistory
            case .provenance: .skillProvenance
            }
        case let .inbox(sheet):
            switch sheet {
            case .queuedItem: .queuedDetail
            case .pairPhone: .pair
            }
        case let .discover(sheet):
            switch sheet {
            case .registryEntry: .registryDetail
            case .officialMark: .official
            }
        case .activity: .resetHistory
        case .settings: .path
        }
    }

    /// Unique across boards, so two boards presenting the same kind are still two sheets.
    var id: String {
        switch self {
        case let .servers(sheet): "servers/\(sheet.id)"
        case let .skills(sheet): "skills/\(sheet.id)"
        case let .cleanup(sheet): "cleanup/\(sheet.id)"
        case let .inbox(sheet): "inbox/\(sheet.id)"
        case let .discover(sheet): "discover/\(sheet.id)"
        case let .activity(sheet): "activity/\(sheet.id)"
        case let .settings(sheet): "settings/\(sheet.id)"
        }
    }

    /// One value per presentable case, for tests that need to enumerate across boards.
    ///
    /// Hand-written because the cases carry subjects and `CaseIterable` cannot synthesise them.
    /// Safe to be hand-written for `MenuCommand.fixedCases`' reason: `RouterSheetTests` compares
    /// the set of kinds this produces against `Kind.allCases` in both directions, so an omission
    /// here is a test failure rather than a silent gap.
    static var allPresentable: [RouterSheet] {
        [
            .servers(.addServer),
            .servers(.heldChange(server: "s")),
            .servers(.removeServer(server: "s")),
            .skills(.heldVersion(skillID: "k")),
            .skills(.marketplaces),
            .cleanup(.removeCandidate(name: "s")),
            .cleanup(.resetHistory),
            .cleanup(.provenance(skillPath: "/p")),
            .inbox(.queuedItem(id: "i")),
            .inbox(.pairPhone),
            .discover(.registryEntry(id: "e")),
            .discover(.officialMark),
            .activity(.resetHistory),
            .settings(.childPath)
        ]
    }
}
