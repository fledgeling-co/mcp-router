import Foundation

/// What one ingest run did, written to disk so it can be undone without re-downloading anything.
///
/// This is the acceptance clause "the removal is reversible from the router without re-downloading"
/// in one file. Every entry names where Claude's bytes went and where they came from; every removed
/// `settings.json` key carries its value and its index. Nothing here is a reference to something
/// that has to be fetched again — the bytes are in the router's quarantine and the JSON is in this
/// document.
public struct IngestManifest: Sendable {
    public struct Entry: Sendable, Hashable {
        public let kind: ExtensionKind
        public let name: String
        /// Where Claude had it. An undo puts the bytes back exactly here.
        public let sourcePath: String
        public let storedPath: String
        /// Where Claude's copy is now, or `nil` for an entry that was never removed.
        public let quarantinePath: String?
        public let linked: Bool
        public let version: String?
        public let digest: String
        public let files: Int
        public let bytes: Int

        public init(
            kind: ExtensionKind,
            name: String,
            sourcePath: String,
            storedPath: String,
            quarantinePath: String?,
            linked: Bool,
            version: String?,
            digest: String,
            files: Int,
            bytes: Int
        ) {
            self.kind = kind
            self.name = name
            self.sourcePath = sourcePath
            self.storedPath = storedPath
            self.quarantinePath = quarantinePath
            self.linked = linked
            self.version = version
            self.digest = digest
            self.files = files
            self.bytes = bytes
        }
    }

    public let runId: String
    public let startedAtMilliseconds: Double
    public let claudeRoot: String
    public let storeRoot: String
    public let settingsPath: String
    public let entries: [Entry]
    public let removedSettingsKeys: [ClaudeSettingsEdit.RemovedKey]

    public init(
        runId: String,
        startedAtMilliseconds: Double,
        claudeRoot: String,
        storeRoot: String,
        settingsPath: String,
        entries: [Entry],
        removedSettingsKeys: [ClaudeSettingsEdit.RemovedKey]
    ) {
        self.runId = runId
        self.startedAtMilliseconds = startedAtMilliseconds
        self.claudeRoot = claudeRoot
        self.storeRoot = storeRoot
        self.settingsPath = settingsPath
        self.entries = entries
        self.removedSettingsKeys = removedSettingsKeys
    }
}

/// The manifest's bytes, built from ``JSONValue`` members in a fixed order.
///
/// Hand-built rather than encoded, under the same rule as every other wire shape in this directory:
/// `scripts/lint/no-wire-codable.sh` refuses `Codable` here, and the reason applies with force to a
/// document whose whole job is to be read back correctly a week later.
public enum IngestManifestJSON {
    public static func text(_ manifest: IngestManifest) -> String {
        JSStringify.prettyTwoSpace(value(manifest)) + "\n"
    }

    public static func value(_ manifest: IngestManifest) -> JSONValue {
        .object([
            member("runId", .string(JSString(manifest.runId))),
            member("startedAt", .number(manifest.startedAtMilliseconds)),
            member("claudeRoot", .string(JSString(manifest.claudeRoot))),
            member("storeRoot", .string(JSString(manifest.storeRoot))),
            member("settingsPath", .string(JSString(manifest.settingsPath))),
            member("entries", .array(manifest.entries.map(entryValue))),
            member("removedSettingsKeys", .array(manifest.removedSettingsKeys.map(keyValue)))
        ])
    }

    static func entryValue(_ entry: IngestManifest.Entry) -> JSONValue {
        .object([
            member("kind", .string(JSString(entry.kind.rawValue))),
            member("name", .string(JSString(entry.name))),
            member("sourcePath", .string(JSString(entry.sourcePath))),
            member("storedPath", .string(JSString(entry.storedPath))),
            member(
                "quarantinePath",
                entry.quarantinePath.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            member("linked", .bool(entry.linked)),
            member("version", entry.version.map { JSONValue.string(JSString($0)) } ?? .null),
            member("digest", .string(JSString(entry.digest))),
            member("files", .number(Double(entry.files))),
            member("bytes", .number(Double(entry.bytes)))
        ])
    }

    static func keyValue(_ key: ClaudeSettingsEdit.RemovedKey) -> JSONValue {
        .object([
            member("container", .string(JSString(key.container))),
            member("key", .string(JSString(key.key))),
            member("value", .string(JSString(key.valueJSON))),
            member("index", .number(Double(key.index)))
        ])
    }

    /// Read one back. `nil` when the document is not one of ours — an undo that guessed at a
    /// half-understood manifest is the failure mode this whole item is built to avoid.
    public static func parse(_ text: String) -> IngestManifest? {
        guard let root = try? JSONParser.parse(text),
              let runId = root.member("runId")?.asString?.string,
              let claudeRoot = root.member("claudeRoot")?.asString?.string,
              let storeRoot = root.member("storeRoot")?.asString?.string,
              let settingsPath = root.member("settingsPath")?.asString?.string
        else { return nil }
        return IngestManifest(
            runId: runId,
            startedAtMilliseconds: root.member("startedAt")?.asNumber ?? 0,
            claudeRoot: claudeRoot,
            storeRoot: storeRoot,
            settingsPath: settingsPath,
            entries: (root.member("entries")?.asArray ?? []).compactMap(entry),
            removedSettingsKeys: (root.member("removedSettingsKeys")?.asArray ?? [])
                .compactMap(removedKey)
        )
    }

    static func entry(_ value: JSONValue) -> IngestManifest.Entry? {
        guard let raw = value.member("kind")?.asString?.string,
              let kind = ExtensionKind(rawValue: raw),
              let name = value.member("name")?.asString?.string,
              let source = value.member("sourcePath")?.asString?.string,
              let stored = value.member("storedPath")?.asString?.string
        else { return nil }
        return IngestManifest.Entry(
            kind: kind, name: name, sourcePath: source, storedPath: stored,
            quarantinePath: value.member("quarantinePath")?.asString?.string,
            linked: value.member("linked")?.isTruthy ?? false,
            version: value.member("version")?.asString?.string,
            digest: value.member("digest")?.asString?.string ?? "",
            files: Int(value.member("files")?.asNumber ?? 0),
            bytes: Int(value.member("bytes")?.asNumber ?? 0)
        )
    }

    static func removedKey(_ value: JSONValue) -> ClaudeSettingsEdit.RemovedKey? {
        guard let container = value.member("container")?.asString?.string,
              let key = value.member("key")?.asString?.string,
              let json = value.member("value")?.asString?.string
        else { return nil }
        return ClaudeSettingsEdit.RemovedKey(
            container: container, key: key, valueJSON: json,
            index: Int(value.member("index")?.asNumber ?? 0)
        )
    }

    private static func member(_ key: String, _ value: JSONValue) -> JSONMember {
        JSONMember(key: JSString(key), value: value)
    }
}
