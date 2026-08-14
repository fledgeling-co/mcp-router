import Foundation

/// Reading and writing `manifest.json`.
public enum ManifestIO {
    public enum Problem: Error, Sendable, Hashable, CustomStringConvertible {
        case unreadable(path: String, reason: String)
        case malformed(path: String, reason: String)

        /// The reference's own wording, carried over verbatim. Rewording it would make R4's gate
        /// report a difference that is only a rewording.
        public var description: String {
            switch self {
            case let .unreadable(path, reason), let .malformed(path, reason):
                "manifest at \(path) unreadable (\(reason)); rebuilding"
            }
        }
    }

    /// What a load produced.
    ///
    /// Three cases where the reference has one. This is divergence D2, and the reason is that the
    /// reference returns an ordinary empty manifest for a cold cache *and* for a corrupt one, and
    /// says which only in a log line nobody downstream can read. A caller handed the same value
    /// both times cannot tell "you have no cached tools yet" from "your tool cache is damaged" —
    /// which are the Empty and Error states of the surface that renders it, and they want opposite
    /// copy. The manifest itself is unchanged in every case, so R4 compares that and ignores this.
    public enum Load: Sendable {
        case loaded(Manifest)
        /// No file yet: the normal first run.
        case cold
        /// An empty manifest, and why it is empty.
        case degraded(Manifest, Problem)

        public var manifest: Manifest {
            switch self {
            case let .loaded(manifest): manifest
            case .cold: .empty
            case let .degraded(manifest, _): manifest
            }
        }

        public var problem: Problem? {
            guard case let .degraded(_, problem) = self else { return nil }
            return problem
        }
    }

    public static func load(path: String, fileSystem: FileSystem = RealFileSystem()) -> Load {
        guard fileSystem.fileExists(atPath: path) else { return .cold }
        let data: Data
        do {
            data = try fileSystem.readFile(atPath: path)
        } catch {
            return .degraded(.empty, .unreadable(path: path, reason: error.localizedDescription))
        }
        do {
            return try .loaded(parse(data))
        } catch let problem as ParseFailure {
            return .degraded(.empty, .malformed(path: path, reason: problem.reason))
        } catch {
            return .degraded(.empty, .malformed(path: path, reason: error.localizedDescription))
        }
    }

    struct ParseFailure: Error, Sendable {
        let reason: String
    }

    /// As shallow as the reference, deliberately.
    ///
    /// `version` must be the number 1, and `servers` must pass `typeof x === "object" && x !== null`
    /// — which **admits an array**, because `typeof [] === "object"`. The entries themselves are not
    /// validated at all and unknown fields are preserved. A stricter parser here would reject
    /// manifests the reference reads happily, and R4 would see that as a regression rather than as
    /// the improvement it looks like.
    public static func parse(_ data: Data) throws -> Manifest {
        let value: JSONValue
        do {
            value = try JSONParser.parse(data)
        } catch {
            throw ParseFailure(reason: "\(error)")
        }
        guard case let .object(members) = value else {
            throw ParseFailure(reason: "not a version-1 manifest object")
        }
        let manifest = Manifest(members: members)
        guard manifest.value.member("version") == .number(1),
              let servers = manifest.serversValue, servers.isObjectOrArray
        else {
            throw ParseFailure(reason: "not a version-1 manifest object")
        }
        return manifest
    }

    /// Writes the manifest atomically: temp file, then rename over whatever is there.
    ///
    /// A reader can never observe a half-written manifest, which would otherwise present as every
    /// MCP tool vanishing at once. **A failed write leaves the temp file behind**, matching the
    /// reference — cleaning it up would discard the only evidence of what was being written when
    /// the disk filled.
    public static func save(
        _ manifest: Manifest,
        toPath path: String,
        fileSystem: FileSystem = RealFileSystem()
    ) throws {
        try fileSystem.createDirectory(atPath: (path as NSString).deletingLastPathComponent)
        let temporary = "\(path).tmp-\(ProcessInfo.processInfo.processIdentifier)"
        let text = JSStringify.prettyTwoSpace(manifest.value)
        try fileSystem.writeFile(Data(text.utf8), atPath: temporary)
        try fileSystem.moveItem(atPath: temporary, toPath: path)
    }
}
