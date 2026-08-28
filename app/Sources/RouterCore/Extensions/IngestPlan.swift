import Foundation

/// One extension the router could take out of Claude, with everything the apply step needs and
/// nothing it would have to go back to disk for.
public struct IngestCandidate: Sendable, Hashable {
    public let kind: ExtensionKind
    /// The name the router will store it under.
    ///
    /// A skill's and a marketplace's directory name; a plugin's `<plugin>@<marketplace>`. The last
    /// is Claude's own identity for a plugin — it is the literal key of `enabledPlugins` and of
    /// `installed_plugins.json` — and it is used here because **13 plugin names on this machine
    /// exist in two marketplaces at once** (`code-review`, `design-craft`, `ship-feature` and ten
    /// others, measured 2026-08-28). A flat store keyed on the bare name would hold one of each
    /// pair and lose the other, which is the same "the router is authoritative except when it
    /// isn't" this item exists to end.
    public let name: String
    public let sourcePath: String
    /// What the entry's own descriptor calls itself, which is not always the directory it sits in.
    public let title: String
    /// The installed version, for a plugin. `nil` for the two kinds that have none.
    public let version: String?
    /// The `settings.json` key that records this entry with Claude, or `nil` for a skill.
    public let settingsKey: String?
    public let stamp: TreeStamp
    /// Something true about this candidate that a person should read before applying, and that does
    /// not stop it being applied. A descriptor whose `name` differs from its directory is the
    /// measured case: both names are known, so nothing is being guessed.
    public let note: String?

    public init(
        kind: ExtensionKind,
        name: String,
        sourcePath: String,
        title: String,
        version: String? = nil,
        settingsKey: String? = nil,
        stamp: TreeStamp,
        note: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.sourcePath = sourcePath
        self.title = title
        self.version = version
        self.settingsKey = settingsKey
        self.stamp = stamp
        self.note = note
    }
}

/// Something in Claude's tree that the router is **not** touching, and why.
///
/// This type is the acceptance clause "an extension the router cannot identify is reported and left
/// alone, never moved on a guess" in code. Every path the scan looked at and did not turn into a
/// candidate leaves one of these behind, so the two lists are a partition of what was examined and
/// there is no third pile that quietly disappears.
public struct IngestBlocked: Sendable, Hashable {
    public let kind: ExtensionKind
    public let name: String
    public let sourcePath: String
    /// A stable slug a caller branches on: `noDescriptor`, `unreadableDescriptor`, `sourceMissing`,
    /// `unusableName`, `alreadyInRouter`, `notADirectory`, `notSettled`, `unmeasurable`.
    public let reason: String
    public let detail: String

    public init(kind: ExtensionKind, name: String, sourcePath: String, reason: String, detail: String) {
        self.kind = kind
        self.name = name
        self.sourcePath = sourcePath
        self.reason = reason
        self.detail = detail
    }
}

/// What one scan found: what could move, what could not, and which registers could not be read.
///
/// `unreadableRegisters` is separate from an empty candidate list for the reason `GET /harnesses`
/// keeps the same distinction: a Claude tree with no plugins and a Claude tree whose
/// `installed_plugins.json` could not be parsed are both "no plugin candidates", and only one of
/// them is a measurement. A run that could not read a register reports it and ingests nothing of
/// that kind rather than reporting zero.
public struct ClaudeScan: Sendable {
    public let tree: ClaudeTree
    public let candidates: [IngestCandidate]
    public let blocked: [IngestBlocked]
    public let unreadableRegisters: [String]

    public init(
        tree: ClaudeTree,
        candidates: [IngestCandidate],
        blocked: [IngestBlocked],
        unreadableRegisters: [String]
    ) {
        self.tree = tree
        self.candidates = candidates
        self.blocked = blocked
        self.unreadableRegisters = unreadableRegisters
    }
}

/// What happened to one candidate when the plan was applied.
public struct IngestOutcome: Sendable, Hashable {
    public enum State: String, Sendable {
        /// Copied, verified, and Claude's copy moved into the router's quarantine.
        case ingested
        /// Copied and verified, and Claude's copy replaced by a link to the router's — `--link-back`.
        case linked
        /// Nothing was done and nothing was left behind. `detail` says at which step it stopped.
        case refused
    }

    public let candidate: IngestCandidate
    public let state: State
    /// Where the router's copy is.
    public let storedPath: String?
    /// Where Claude's copy was moved to, which is the whole of what makes this reversible.
    public let quarantinePath: String?
    public let detail: String

    public init(
        candidate: IngestCandidate,
        state: State,
        storedPath: String? = nil,
        quarantinePath: String? = nil,
        detail: String
    ) {
        self.candidate = candidate
        self.state = state
        self.storedPath = storedPath
        self.quarantinePath = quarantinePath
        self.detail = detail
    }
}
