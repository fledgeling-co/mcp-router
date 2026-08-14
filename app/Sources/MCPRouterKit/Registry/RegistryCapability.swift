import Foundation

/// What an entry will actually do, read off its install block — and the decision about whether it
/// may be installed at all.
///
/// **Why this is a reading rather than a manifest.** The brief requires every entry to "state its
/// capabilities in plain language before install — what it reads, what it contacts, whether it runs
/// shell". Neither index publishes a capability manifest; no MCP registry format carries one. The
/// only honest source is the install block itself, which is a fact the index published. So the
/// statement below is a *reading of the install block* and says so, in the same way M4's skills
/// board labels its own derived capability list.
///
/// The honest answer to "does it run shell" is not a boolean. It is the argv, shown.
public enum RegistryCapability {
    // MARK: - The statement

    /// What the user is being asked to allow, in the three shapes the wire actually has.
    public struct Statement: Equatable, Sendable {
        public var headline: String
        public var detail: String
        /// The command and its arguments, sanitised, **one element per token**.
        ///
        /// Kept as an array rather than joined into a string on purpose. A joined line reads as a
        /// shell command, and an entry whose `args` contain spaces or quotes would render as a
        /// different command from the one that will run. Rendering token by token also means an
        /// entry cannot smuggle what looks like a second command into the block.
        public var argv: [String]
        /// The host an HTTP entry connects to — the authority alone, never the path, which is where
        /// a misleading string would hide (`https://api.trusted.com.evil.io/…`).
        public var host: String?
        /// True when nothing will run on this Mac.
        public var isRemote: Bool
    }

    public static func statement(for entry: RegistryEntry) -> Statement {
        guard let install = entry.install else {
            return Statement(
                headline: "Neither index says how to run this",
                detail: """
                The entry exists in the catalogue but carries no command and no address, so there \
                is nothing to add.
                """,
                argv: [],
                host: nil,
                isRemote: false
            )
        }

        switch install.type {
        case .stdio:
            let argv = argvTokens(of: install)
            return Statement(
                headline: "Runs a program on this Mac",
                detail: """
                It runs as you, which means it can read and write the files you can and open the \
                connections you can. Nothing declares what it will actually do, and that cannot be \
                checked before it runs.
                """,
                argv: argv,
                host: nil,
                isRemote: false
            )
        case .http, .sse:
            let host = host(of: install.url)
            return Statement(
                headline: host.map { "Connects to \($0)" } ?? "Connects to a remote server",
                detail: """
                Nothing runs on this Mac. Whatever you send it goes to that host, and what it does \
                with it is not declared here.
                """,
                argv: [],
                host: host,
                isRemote: true
            )
        }
    }

    /// `command` followed by each argument, each sanitised, empties dropped.
    static func argvTokens(of install: RegistryInstall) -> [String] {
        var tokens: [String] = []
        if let command = install.command {
            tokens.append(RegistryPresentation.sanitized(command))
        }
        for argument in install.args ?? [] {
            tokens.append(RegistryPresentation.sanitized(argument))
        }
        return tokens.filter { !$0.isEmpty }
    }

    /// The authority of a URL, or `nil` when it does not parse to one.
    ///
    /// Deliberately `URLComponents.host` rather than any string handling: a hand-rolled parse is
    /// how `https://api.smithery.ai@evil.io/` gets read as `api.smithery.ai`.
    static func host(of raw: String?) -> String? {
        guard let raw, let components = URLComponents(string: raw), let host = components.host,
              !host.isEmpty else { return nil }
        return RegistryPresentation.sanitized(host)
    }

    /// The one quiet sentence saying where this came from, so it is not mistaken for something the
    /// entry's author declared and stands behind.
    public static let derivationNote = """
    Read from the entry's install instructions, not from anything its author declared. No registry \
    format carries a capability list, so this describes how it starts and not what it goes on to do.
    """

    // MARK: - What it asks you for

    public static func secrets(in entry: RegistryEntry) -> [RegistryRequirement] {
        (entry.install?.requires ?? []).filter { $0.isSecret ?? false }
    }

    /// The summary line above the requirement fields.
    public static func requirementSummary(for entry: RegistryEntry) -> String? {
        let requirements = entry.install?.requires ?? []
        guard !requirements.isEmpty else { return nil }
        let secretCount = secrets(in: entry).count
        let noun = requirements.count == 1 ? "value" : "values"
        guard secretCount > 0 else {
            return "Asks for \(requirements.count) \(noun) before it can start."
        }
        return """
        Asks for \(requirements.count) \(noun) before it can start, \
        \(secretCount == requirements.count ? "all" : "\(secretCount)") of them secret.
        """
    }

    /// Where a value the user types actually ends up, stated plainly.
    ///
    /// Deliberately unflattering and deliberately accurate. The app itself stores nothing — the
    /// value is held for the life of the sheet and handed to the router with the declaration —
    /// but the router writes it into its own config, and a sentence implying a keychain would be
    /// false. `SWIFT_PRACTICES.md` §6 wants credentials in the keychain; that is the router's
    /// storage to change, and it is raised as an open question against the router rather than
    /// papered over here.
    public static let secretDestination = """
    Held only while this sheet is open, then sent to the router with the declaration. This app \
    does not store it.
    """

    // MARK: - The action

    /// Whether, and how, this entry may be added.
    public struct Action: Equatable, Sendable {
        public var label: String
        public var isEnabled: Bool
        /// Shown beside the control when it is disabled — never instead of it (`DESIGN.md` §3.4).
        public var disabledReason: String?
        /// The `…` case: pressing it reveals the requirement fields rather than committing.
        public var revealsRequirements: Bool
    }

    /// `DESIGN.md` §3.4 as a decision rather than a constant: `…` means "opens a further view", its
    /// absence means "commits now". Whether this entry commits now is a property of its install
    /// block, so the label is computed from it.
    ///
    /// `isInstalling` is a parameter rather than a separate state because the disabled-while-in-
    /// flight case is the one that matters: without it the prominent button stays live across the
    /// round trip and a second press sends a second `add` for the same entry.
    public static func action(
        for entry: RegistryEntry,
        isInstalling: Bool = false,
        requirementsRevealed: Bool = false
    ) -> Action {
        let name = RegistryPresentation.sanitized(entry.displayName, cap: 40)

        if entry.installed ?? false {
            let declared = RegistryPresentation.sanitized(entry.name, cap: 60)
            return Action(
                label: "Added",
                isEnabled: false,
                disabledReason: "Already declared as \u{201C}\(declared)\u{201D}.",
                revealsRequirements: false
            )
        }
        guard entry.install != nil else {
            return Action(
                label: "Add \(name)",
                isEnabled: false,
                disabledReason: "Neither index says how to run this, so there is nothing to add.",
                revealsRequirements: false
            )
        }
        if isInstalling {
            return Action(
                label: "Adding\u{2026}",
                isEnabled: false,
                disabledReason: nil,
                revealsRequirements: false
            )
        }
        let requirements = entry.install?.requires ?? []
        // Once the fields are on screen the button commits, so it loses its ellipsis — the
        // ellipsis promised a further view and the further view has arrived.
        let reveals = !requirements.isEmpty && !requirementsRevealed
        return Action(
            label: reveals ? "Add \(name)\u{2026}" : "Add \(name)",
            isEnabled: true,
            disabledReason: nil,
            revealsRequirements: reveals
        )
    }

    // MARK: - Building the declaration

    /// The `NewServer` an entry becomes, with the values the user supplied.
    ///
    /// Two guarantees live here rather than at the call site:
    ///
    /// - **`force` is never set.** `add(_:force:)` with `force: true` adopts an existing
    ///   declaration, which on this surface would mean a registry entry the user found in a list
    ///   could replace the command line of a server they already trust. The caller cannot pass
    ///   `force` at all, because this function does not offer it and the model's install path takes
    ///   its argument from here.
    /// - **The name is the entry's `name`, sanitised**, never its `displayName`, which is the field
    ///   an index lets an author choose freely.
    ///
    /// Returns `nil` when there is no install block, so a caller cannot construct a declaration for
    /// an entry that never said how to run.
    public static func declaration(
        for entry: RegistryEntry,
        values: [String: String]
    ) -> NewServer? {
        guard let install = entry.install else { return nil }
        let name = RegistryPresentation.sanitized(entry.name)
        guard !name.isEmpty else { return nil }

        // Only the values this entry actually asked for are carried. A value left over from an
        // earlier sheet, or a key the user never saw, must not reach the router.
        let asked = Set((install.requires ?? []).map(\.name))
        let supplied = values.filter { asked.contains($0.key) && !$0.value.isEmpty }

        switch install.type {
        case .stdio:
            guard let command = install.command, !command.isEmpty else { return nil }
            return NewServer(
                name: name,
                command: command,
                args: install.args,
                env: supplied.isEmpty ? nil : supplied
            )
        case .http, .sse:
            guard let url = install.url, !url.isEmpty else { return nil }
            return NewServer(
                name: name,
                url: url,
                headers: supplied.isEmpty ? nil : supplied,
                type: install.type.rawValue
            )
        }
    }

    /// Every requirement the entry asked for that has no value yet.
    ///
    /// A secret with no value is not sent as an empty string — the router would store an empty
    /// credential and the server would fail with an authentication error that names nothing.
    public static func missingRequirements(
        for entry: RegistryEntry,
        values: [String: String]
    ) -> [RegistryRequirement] {
        (entry.install?.requires ?? []).filter { requirement in
            (values[requirement.name] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
