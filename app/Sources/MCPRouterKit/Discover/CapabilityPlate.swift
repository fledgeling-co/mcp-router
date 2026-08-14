import Foundation

/// The capability plate: what queueing this entry would actually mean, in plain language.
///
/// The brief's rule, and the reason this type exists at all: **the security fact is never behind a
/// tap the user can skip.** The plate is drawn above the commit, always, never behind a disclosure
/// control (A12).
///
/// Every line is **derived from the `install` descriptor**, never authored per entry. An authored
/// line is a line someone can forget to write, and the entry it is forgotten for is the one where
/// it mattered. Deriving them means a new entry from either index gets its plate for free, and a
/// wrong plate is a bug in one function rather than in one row of data.
public enum CapabilityPlate {
    /// How loudly a line is drawn. Maps to `DESIGN.md` §2's tokens at the view boundary — this
    /// type carries no colour, because `MCPRouterKit` holds no UI framework
    /// (`SWIFT_PRACTICES.md` §8).
    public enum Severity: Sendable, Equatable {
        /// `--attn`: wants a human decision.
        case attention
        /// Neutral. A fact the user should read, drawn in the label tiers.
        case fact
    }

    /// What a line is about, so the view can pick a symbol without parsing the copy.
    public enum Kind: Sendable, Equatable, CaseIterable {
        case runsLocally
        case remote
        case credential
        case archived
        case unknownTransport
    }

    public struct Line: Sendable, Equatable, Identifiable {
        public let kind: Kind
        public let severity: Severity
        public let copyKey: DiscoverCopy.Key
        /// The host, for `.remote`. Nil everywhere else.
        public let host: String?

        public var id: Kind { kind }

        /// The rendered sentence, with its substitution already applied.
        public var text: String {
            let entry = DiscoverCopy.entry(copyKey)
            guard let host else { return entry.body }
            return entry.resolved([.host: host]).body
        }
    }

    /// The five derivations of A13, **accumulating**.
    ///
    /// They are not mutually exclusive and the code must not pretend they are: a `stdio` entry may
    /// also require a secret and also be archived, and that entry is exactly the one whose plate
    /// has to say all three. All matching lines render, in this table's order.
    ///
    /// | Input | Line | Severity |
    /// |---|---|---|
    /// | `install.type == .stdio` | runs a program on your Mac | attention |
    /// | `install.type == .http` / `.sse` | nothing runs on your Mac; requests go to {host} | fact |
    /// | any `requires` with `isSecret` | needs a credential | attention |
    /// | `archived == true` | the repository is archived | fact |
    /// | `install == nil` | neither index says how this runs | fact |
    public static func lines(install: RegistryInstall?, archived: Bool?) -> [Line] {
        var lines: [Line] = []

        guard let install else {
            // A17: with no descriptor there is nothing to queue, and this line is what the
            // disabled commit's reason points at.
            lines.append(Line(
                kind: .unknownTransport,
                severity: .fact,
                copyKey: .plateNoInstall,
                host: nil
            ))
            if archived == true {
                lines.append(archivedLine)
            }
            return lines
        }

        switch install.type {
        case .stdio:
            lines.append(Line(
                kind: .runsLocally,
                severity: .attention,
                copyKey: .plateStdio,
                host: nil
            ))
        case .http, .sse:
            // The line **names the host**, because for a remote MCP server the decision that
            // matters is that tool arguments leave the machine. It is a fact rather than an
            // attention line: the user is queueing for review, not granting access, and an amber
            // block that fires on everything stops meaning anything.
            lines.append(Line(
                kind: .remote,
                severity: .fact,
                copyKey: .plateRemote,
                host: host(of: install.url) ?? "an address neither index published"
            ))
        }

        if let requires = install.requires, requires.contains(where: { $0.isSecret == true }) {
            // A14: every Smithery-hosted install declares a required `Authorization`
            // unconditionally (`src/registry.ts:172-179`), so within that subset this line
            // distinguishes nothing. Where the host is Smithery's, the copy says so — the
            // difference between a warning and noise is whether it admits when it carries no
            // signal.
            let isSmitheryHosted = host(of: install.url)?.hasSuffix("smithery.ai") == true
            lines.append(Line(
                kind: .credential,
                severity: .attention,
                copyKey: isSmitheryHosted ? .plateCredentialSmithery : .plateCredential,
                host: nil
            ))
        }

        if archived == true {
            lines.append(archivedLine)
        }

        return lines
    }

    private static let archivedLine = Line(
        kind: .archived,
        severity: .fact,
        copyKey: .plateArchived,
        host: nil
    )

    /// The plate takes `--attn` if any line does.
    public static func severity(of lines: [Line]) -> Severity {
        lines.contains { $0.severity == .attention } ? .attention : .fact
    }

    /// The literal invocation, in the entry's own words — the evidence the plain-language lines
    /// interpret (A12). Monospace at the view boundary: it is instrument data (`DESIGN.md` §2).
    ///
    /// Returns nil when there is no descriptor, which is the case where there is nothing to show
    /// and the plate says so instead.
    ///
    /// This is a **string for a human to read**. Nothing in this app executes it, and nothing in
    /// this app can: the phone queues for review on the Mac and never installs (`DESIGN.md` §9),
    /// and the control API's `command`, `args` and `env` are not writable at all.
    public static func invocation(install: RegistryInstall?) -> String? {
        guard let install else { return nil }
        switch install.type {
        case .stdio:
            guard let command = install.command else { return nil }
            let args = install.args ?? []
            return ([command] + args).joined(separator: " ")
        case .http, .sse:
            return install.url
        }
    }

    /// The host of a URL, for the remote line.
    ///
    /// `URLComponents` rather than string splitting, and nil rather than a guess: a line that names
    /// the wrong host is worse than one that admits it does not know which host, because the whole
    /// point of the line is telling the user where their arguments go.
    static func host(of urlString: String?) -> String? {
        guard let urlString, let host = URLComponents(string: urlString)?.host, !host.isEmpty else {
            return nil
        }
        return host
    }
}
