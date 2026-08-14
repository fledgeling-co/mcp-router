import Foundation

/// `watch-state.json` — the only thing the watcher remembers between fires.
///
/// Exempt from W4's backup rule, deliberately: every field is derived and recoverable. Losing it
/// costs one adoption pass that re-reads and re-indexes, which is exactly what the file exists to
/// avoid and not something worth a backup directory.
///
/// **A corrupt file recovers as empty state** (W8). The alternative — failing the run — would leave
/// a machine unable to adopt anything until someone deleted a file they have never heard of.
public struct WatchState: Sendable, Equatable {
    public struct Failure: Sendable, Equatable {
        public let hash: String
        public let at: Double
        public let error: String

        public init(hash: String, at: Double, error: String) {
            self.hash = hash
            self.at = at
            self.error = error
        }
    }

    /// Hash of the `mcpServers` object only — the rest of `~/.claude.json` churns constantly.
    public var mcpServersHash: String?
    public var failures: [String: Failure]
    /// A restart this watcher owes the router but has not yet successfully issued.
    ///
    /// New in the Swift watcher (X7). It is persisted **before** the `servers.json` write, not
    /// after: a process killed between the rename and the state save would otherwise leave the
    /// config changed, nothing owed, and the running router never told — which is D7's exact end
    /// state reached through a door the reference's own bug did not need.
    public var restartPending: Bool

    public init(
        mcpServersHash: String? = nil,
        failures: [String: Failure] = [:],
        restartPending: Bool = false
    ) {
        self.mcpServersHash = mcpServersHash
        self.failures = failures
        self.restartPending = restartPending
    }

    // MARK: - Persistence

    public static func load(path: String, fileSystem: any FileSystem) -> WatchState {
        guard fileSystem.fileExists(atPath: path),
              let data = try? fileSystem.readFile(atPath: path),
              let parsed = try? JSONParser.parse(data),
              let members = parsed.asObjectMembers
        else { return WatchState() }

        var state = WatchState()
        state.mcpServersHash = members
            .first { $0.key == JSString("mcpServersHash") }?.value.asString?.string
        state.restartPending = members
            .first { $0.key == JSString("restartPending") }?.value.isTruthy ?? false
        if let recorded = members.first(where: { $0.key == JSString("failures") })?.value,
           let entries = recorded.asObjectMembers
        {
            for entry in entries {
                guard let fields = entry.value.asObjectMembers else { continue }
                func text(_ key: String) -> String {
                    fields.first { $0.key == JSString(key) }?.value.asString?.string ?? ""
                }
                let at = fields.first { $0.key == JSString("at") }?.value.asNumber ?? 0
                state.failures[entry.key.string] = Failure(
                    hash: text("hash"), at: at, error: text("error")
                )
            }
        }
        return state
    }

    /// Temp-plus-rename, two-space pretty — `saveState`'s shape (`watch.ts:107-112`).
    public func save(path: String, fileSystem: any FileSystem, processIdentifier: Int32) throws {
        try fileSystem.createDirectory(atPath: (path as NSString).deletingLastPathComponent)
        let text = JSStringify.prettyTwoSpace(value)
        let temporary = "\(path).tmp-\(processIdentifier)"
        try fileSystem.writeFile(Data(text.utf8), atPath: temporary)
        try fileSystem.moveItem(atPath: temporary, toPath: path)
    }

    /// Key order follows the reference's object literal, with `restartPending` appended — an
    /// unknown key to the TypeScript reader, which ignores it.
    var value: JSONValue {
        var members: [JSONMember] = []
        if let mcpServersHash {
            members.append(
                JSONMember(key: JSString("mcpServersHash"), value: .string(JSString(mcpServersHash)))
            )
        }
        let sorted = failures.keys.sorted()
        members.append(JSONMember(key: JSString("failures"), value: .object(sorted.map { name in
            let failure = failures[name] ?? Failure(hash: "", at: 0, error: "")
            return JSONMember(key: JSString(name), value: .object([
                JSONMember(key: JSString("hash"), value: .string(JSString(failure.hash))),
                JSONMember(key: JSString("at"), value: .number(failure.at)),
                JSONMember(key: JSString("error"), value: .string(JSString(failure.error)))
            ]))
        })))
        if restartPending {
            members.append(JSONMember(key: JSString("restartPending"), value: .bool(true)))
        }
        return .object(members)
    }
}
