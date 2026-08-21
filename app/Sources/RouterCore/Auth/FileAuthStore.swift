import Foundation

/// The auth record store: one file per server, read on every call.
///
/// Stateless by design, exactly as the reference is — `hasTokens`, `authorizedAt` and every write
/// re-read the file rather than consulting a cache. S6's rule that a handler is a total function of
/// its dependencies depends on it: a cached record would let a response reflect a state the
/// filesystem no longer holds.
///
/// Every name is a `JSString`. There is no Swift-`String`-keyed map anywhere in this type — see
/// B80: Swift `String` equality is canonical where JavaScript's is by code unit, and the typing is
/// what keeps that from silently becoming a divergence if the name gate is ever relaxed.
public struct FileAuthStore: Sendable {
    private let authDir: String
    private let fileSystem: any FileSystem & FileModeWriting
    private let log: RouterLog?

    public init(
        authDir: String,
        fileSystem: any FileSystem & FileModeWriting = RealFileSystem(),
        log: RouterLog? = nil
    ) {
        self.authDir = authDir
        self.fileSystem = fileSystem
        self.log = log
    }

    private func path(_ server: JSString) -> String {
        AuthPaths.recordPath(authDir: authDir, server: server)
    }

    /// `readRecord`: an absent file is an empty record; an unreadable one **warns** and is also an
    /// empty record (B61, B100).
    ///
    /// Not `try?`-and-default: the two cases are distinguished, and only the second logs. Collapsing
    /// them would make a corrupt credential file indistinguishable from a first run — which is the
    /// difference between "sign in" and "something is wrong with your saved credentials".
    public func read(_ server: JSString) async -> AuthRecord {
        let file = path(server)
        guard fileSystem.fileExists(atPath: file) else { return AuthRecord() }
        do {
            let data = try fileSystem.readFile(atPath: file)
            guard
                let text = String(data: data, encoding: .utf8),
                let parsed = try? JSONParser.parse(text),
                let record = AuthRecord(parsed)
            else {
                await warnUnreadable(server, reason: "Unexpected token in JSON")
                return AuthRecord()
            }
            return record
        } catch {
            await warnUnreadable(server, reason: error.localizedDescription)
            return AuthRecord()
        }
    }

    private func warnUnreadable(_ server: JSString, reason: String) async {
        await log?.log(.authRecordUnreadable(server: server.string, reason: reason))
    }

    /// `writeRecord`: `0700` on the directory, `0600` on the file, both at creation (B60).
    public func write(_ server: JSString, _ record: AuthRecord) throws {
        try fileSystem.createDirectory(atPath: authDir, mode: 0o700)
        let bytes = Data(record.serialized.utf8)
        try fileSystem.writeFile(bytes, atPath: path(server), mode: 0o600)
    }

    /// `{ ...readRecord(server), <key>: <value> }` then write. The merge is what preserves the
    /// file's existing key order (B91).
    public func merge(_ server: JSString, _ key: String, _ value: JSONValue) async throws {
        var record = await read(server)
        record.merge(key, value)
        try write(server, record)
    }

    /// Whether a record file exists at all, which `read` deliberately cannot tell you.
    ///
    /// `read` returns an empty record for both an absent file and an unreadable one, because that
    /// is what the reference does. The upstream state report needs the distinction the reference
    /// draws with `existsSync`: a server nobody has ever authorised and one whose authorisation
    /// was started and abandoned want different sentences, and only the file's presence tells them
    /// apart.
    public func recordExists(_ server: JSString) async -> Bool {
        fileSystem.fileExists(atPath: path(server))
    }

    /// `hasTokens` (B60).
    public func hasTokens(_ server: JSString) async -> Bool {
        await read(server).hasAccessToken
    }

    /// `authorizedAt` (B97).
    public func authorizedAt(_ server: JSString) async -> JSString? {
        await read(server).authorizedAt
    }

    /// `clearAuth`: reports whether a record existed, by testing **before** removing (B62).
    @discardableResult
    public func clear(_ server: JSString) -> Bool {
        let file = path(server)
        guard fileSystem.fileExists(atPath: file) else { return false }
        try? fileSystem.removeItem(atPath: file)
        return true
    }

    /// `saveTokens`: tokens **and** `authorizedAt` in one write, which is why there is no
    /// half-authorized record and no Partial state for this surface.
    public func saveTokens(_ server: JSString, tokens: JSONValue, nowMilliseconds: Double) async throws {
        var record = await read(server)
        record.merge("tokens", tokens)
        record.merge("authorizedAt", .string(JSString(JSDate.iso8601(milliseconds: nowMilliseconds))))
        try write(server, record)
    }
}
