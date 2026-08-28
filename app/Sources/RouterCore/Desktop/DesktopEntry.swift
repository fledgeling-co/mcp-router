import Foundation

/// One `mcpServers` entry as Claude Desktop will actually accept it — **R32**.
///
/// This type exists because the obvious registration is wrong, and wrong in the quietest way
/// available. Claude Code is pointed at the router with `{"type":"http","url":"…/mcp"}`
/// (``ClaudeStagingEntry``), and copying that shape into Desktop's config looks like the same
/// change. It is not: Desktop validates every entry against a schema that has **no `url` and no
/// `type` member and requires `command`**, drops the entries that fail, and tells the user through a
/// dialog listing the names it skipped. Registration would report success, the file would look
/// right, and Desktop would front nothing.
///
/// So the schema is transcribed here from the shipped artifact and the entry is checked against it
/// before anything is written. `planning/evidence/R32-acceptance.md` carries the transcription and
/// how it was taken.
///
/// **It writes nothing.** ``DesktopEntryWriter`` is the half that touches a file, and it is a
/// separate type so that this one can be exercised without a filesystem at all.
public enum DesktopEntry {
    /// The name the router registers itself under, in every client. Shared with
    /// ``ClaudeStagingEntry/entryName`` by value rather than by reference: they are the same string
    /// for the same reason, and a client that renamed its entry would not rename the other's.
    public static let entryName = "mcp-router"

    /// The router's streamable-HTTP endpoint — the thing a bridge is a bridge *to*.
    public static func url(port: Int) -> String {
        "http://127.0.0.1:\(port)/mcp"
    }

    // MARK: - Claude Desktop's schema, transcribed rather than assumed

    /// Every member Claude Desktop's `mcpServers` entry schema declares.
    ///
    /// Transcribed from Claude Desktop 1.30096.1's `app.asar` on 2026-08-28. The schema is one
    /// zod object and it is quotable in full:
    ///
    ///     xb = P({ command: A(), args: N(A()).optional(),
    ///              env: I(A(), A()).optional(), extensionId: A().optional() })
    ///
    /// `P` is `z.object`, `A` is `z.string`, `N` is `z.array`, `I` is `z.record`. There is no `url`
    /// and no `type`, which is the whole finding.
    public static let acceptedMembers: Set<String> = ["command", "args", "env", "extensionId"]

    /// The members without which Desktop's `safeParse` fails and the entry is dropped.
    public static let requiredMembers: Set<String> = ["command"]

    /// What Desktop would do with a candidate entry, as two separate lists.
    ///
    /// They are separate because zod's default object is **not** strict: a member Desktop does not
    /// declare is silently stripped rather than rejected, so `type` and `url` beside a valid
    /// `command` are *dropped*, not *fatal*. Folding the two into one verdict would either refuse a
    /// working entry or promise that a stripped member reaches Desktop.
    public struct Conformance: Sendable, Hashable {
        /// Reasons Desktop's schema would reject the entry outright. Empty means it is accepted.
        public let skipped: [String]
        /// Members Desktop accepts the entry *without* — present in the candidate, absent from the
        /// schema, and therefore discarded before Desktop ever reads them.
        public let dropped: [String]

        public var isAccepted: Bool { skipped.isEmpty }
    }

    /// Check a candidate entry against the transcribed schema.
    ///
    /// The order matters: a caller asks this **before** writing, so the answer has to be about the
    /// bytes it is going to write rather than about the intent behind them.
    public static func conformance(of entry: JSONValue) -> Conformance {
        guard let members = entry.asObjectMembers else {
            return Conformance(
                skipped: ["the entry is a \(entry.typeName), and Desktop's schema is an object"],
                dropped: []
            )
        }
        var skipped: [String] = []
        var dropped: [String] = []
        let names = members.map(\.key.string)

        for required in requiredMembers.sorted() where !names.contains(required) {
            skipped.append("\"\(required)\" is required and is missing")
        }
        for member in members {
            let name = member.key.string
            if !acceptedMembers.contains(name) {
                dropped.append(name)
                continue
            }
            if let reason = typeProblem(name: name, value: member.value) {
                skipped.append(reason)
            }
        }
        return Conformance(skipped: skipped, dropped: dropped.sorted())
    }

    /// The per-member type rules, one arm each, in the schema's own terms.
    private static func typeProblem(name: String, value: JSONValue) -> String? {
        switch name {
        case "command", "extensionId":
            guard value.asString == nil else { return nil }
            return "\"\(name)\" is a \(value.typeName), and the schema says string"
        case "args":
            guard let items = value.asArray else {
                return "\"args\" is a \(value.typeName), and the schema says array of string"
            }
            guard let offender = items.first(where: { $0.asString == nil }) else { return nil }
            return "\"args\" holds a \(offender.typeName), and the schema says array of string"
        case "env":
            guard let pairs = value.asObjectMembers else {
                return "\"env\" is a \(value.typeName), and the schema says record of string"
            }
            guard let offender = pairs.first(where: { $0.value.asString == nil }) else { return nil }
            return "\"env\".\(offender.key.string) is a \(offender.value.typeName), "
                + "and the schema says record of string"
        default:
            return nil
        }
    }

    // MARK: - Building the entry

    /// The entry the router would register, given a bridge to reach it through.
    ///
    /// There is no overload that takes only a port, and that absence is the design. Desktop cannot
    /// be handed a URL, so a function that produced an entry from a port alone would have to invent
    /// the command — and the invented command is exactly what nobody has measured.
    public static func entry(bridge: DesktopBridge) -> JSONValue {
        var members = [
            JSONMember(key: JSString("command"), value: .string(JSString(bridge.command)))
        ]
        if !bridge.arguments.isEmpty {
            members.append(JSONMember(
                key: JSString("args"),
                value: .array(bridge.arguments.map { .string(JSString($0)) })
            ))
        }
        return .object(members)
    }

    /// The document Desktop's config becomes once the router's entry is in it.
    ///
    /// Everything the router does not own is carried through untouched and in order — the file this
    /// was measured against holds `coworkUserFilesPath` and a `preferences` tree of the user's whole
    /// window state, and a writer that reconstructed the document from the members it understood
    /// would silently discard it.
    ///
    /// Unlike ``ClaudeStagingEntry/rewritten(_:port:)`` this **throws** on a root that is not an
    /// object. That divergence is deliberate: the Claude Code path is reproducing an installer whose
    /// JavaScript treats a non-object root as a silent no-op, and this path is a command a person
    /// runs on purpose, where "nothing happened and the exit code was 0" is the wrong answer.
    public static func rewritten(
        _ root: JSONValue, bridge: DesktopBridge
    ) throws -> JSONValue {
        guard var members = root.asObjectMembers else {
            throw Refusal.rootIsNotAnObject(found: root.typeName)
        }
        let candidate = entry(bridge: bridge)
        let verdict = conformance(of: candidate)
        guard verdict.isAccepted else {
            throw Refusal.entryWouldBeSkipped(reasons: verdict.skipped)
        }

        let key = JSString("mcpServers")
        let existing = members.first { $0.key == key }?.value
        guard existing == nil || existing?.isObject == true else {
            throw Refusal.serversIsNotAnObject(found: existing?.typeName ?? "null")
        }
        var entries = existing?.asObjectMembers ?? []
        set(&entries, JSString(entryName), candidate)
        set(&members, key, .object(entries))
        return .object(members)
    }

    /// Whether a document already declares the router's entry, with these exact bytes.
    ///
    /// Used to say "nothing to do" honestly. Comparing the whole entry rather than the name is what
    /// stops a stale entry — one naming a bridge that has since moved — reading as up to date.
    public static func declaresCurrentEntry(_ document: JSONValue, bridge: DesktopBridge) -> Bool {
        document.member("mcpServers")?.member(entryName) == entry(bridge: bridge)
    }

    /// Why the command refused. Every case is a sentence a person can act on, because the whole
    /// point of the item is that the failures here are reported rather than assumed away.
    public enum Refusal: Error, Sendable, Equatable, CustomStringConvertible {
        case noConfigFile(path: String)
        case unparseable(path: String, reason: String)
        case rootIsNotAnObject(found: String)
        case serversIsNotAnObject(found: String)
        case entryWouldBeSkipped(reasons: [String])
        case noBridge(url: String)
        case bridgeNotExecutable(path: String)
        case bridgeNotAbsolute(command: String)

        public var description: String {
            switch self {
            case let .noConfigFile(path):
                "no \(path). Claude Desktop writes this file itself the first time it runs; "
                    + "nothing here creates one, because a config file for an app that has never "
                    + "started is a guess about an app that may not be installed."
            case let .unparseable(path, reason):
                "\(path) is not valid JSON (\(reason)). Nothing was changed."
            case let .rootIsNotAnObject(found):
                "the config's root is a \(found), not an object, so it has no mcpServers to add to."
            case let .serversIsNotAnObject(found):
                "\"mcpServers\" is a \(found), not an object. Fix it by hand: replacing it here "
                    + "would discard whatever is in there."
            case let .entryWouldBeSkipped(reasons):
                "Claude Desktop would skip this entry — " + reasons.joined(separator: "; ")
            case let .noBridge(url):
                "Claude Desktop's config accepts a command to launch, never a url, so it cannot be "
                    + "pointed at \(url) directly. Name a stdio-to-HTTP bridge with --bridge <path>."
            case let .bridgeNotExecutable(path):
                "\(path) is not an executable file. Desktop launches this command itself and "
                    + "reports nothing when it cannot."
            case let .bridgeNotAbsolute(command):
                "\(command) is not an absolute path. Claude Desktop is launched by the window "
                    + "server and does not inherit a shell's PATH, so a bare command name resolves "
                    + "differently there than it does here — or not at all."
            }
        }
    }

    private static func set(_ members: inout [JSONMember], _ key: JSString, _ value: JSONValue) {
        let member = JSONMember(key: key, value: value)
        if let index = members.firstIndex(where: { $0.key == key }) {
            members[index] = member
        } else {
            members.append(member)
        }
    }
}

/// The command Claude Desktop would launch to reach a streamable-HTTP MCP server.
///
/// **The router does not ship one.** `mcp-router serve` speaks streamable HTTP and has no stdio
/// mode, so on this machine, today, there is nothing to put here — which is why this is a value a
/// caller supplies and validates rather than a default this type invents.
public struct DesktopBridge: Sendable, Hashable {
    public let command: String
    public let arguments: [String]

    public init(command: String, arguments: [String]) {
        self.command = command
        self.arguments = arguments
    }

    /// Whether the command is one Desktop could actually launch, checked as two separate things.
    ///
    /// Absoluteness is checked **first and separately** from executability because the two failures
    /// have different fixes and the second hides the first: a bare `mcp-remote` that resolves on the
    /// developer's `PATH` passes an executability check taken in a terminal and then fails inside
    /// Desktop, which is launched by `launchd` with an environment that has no shell in it. This is
    /// the false-positive install the out-of-family review of this item named, refused at the point
    /// where it is still cheap.
    public func problem(using fileSystem: any FileSystem) -> DesktopEntry.Refusal? {
        guard command.hasPrefix("/") else {
            return .bridgeNotAbsolute(command: command)
        }
        guard fileSystem.fileExists(atPath: command), isExecutable(command) else {
            return .bridgeNotExecutable(path: command)
        }
        return nil
    }

    /// `access(2)` with `X_OK`, which is the question Desktop's `spawn` will ask. Not routed through
    /// ``FileSystem``: that protocol is shared by every runner in this fleet and has no permission
    /// query, and widening it for one caller manufactures a conflict for all of them — the reason
    /// ``ClaudeStagingEntry/isRegularFile(atPath:)`` reaches for `stat(2)` directly too.
    private func isExecutable(_ path: String) -> Bool {
        access(path, X_OK) == 0
    }
}
