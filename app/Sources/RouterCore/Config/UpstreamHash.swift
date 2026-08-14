import CryptoKit
import Foundation

/// Config-identity hash. A changed command, args, cwd or env — keys *or values* — invalidates that
/// server's cached manifest, and for an HTTP upstream a changed url or static header does the same.
///
/// Values are in the hashed material, not just the key names. A server whose tool surface depends
/// on an env value — a mode flag, or a key that gates which tools it advertises — would otherwise
/// keep serving the tool list it had under the old value. The digest is one-way and truncated, so
/// no secret is recoverable from what lands in `manifest.json`.
///
/// OAuth tokens are deliberately **not** hashed. They live in the auth store rather than the
/// config, and a routine token refresh must not invalidate a tool list that has not changed.
///
/// Excluded for the same reason: `name`, `idleMs`, `startupTimeoutMs`, `projects`, `warm` and
/// `placard`. None of them changes what the server advertises, so none of them should cost a
/// re-index.
public enum UpstreamHash {
    public static func hash(_ upstream: UpstreamConfig) -> String {
        let material: JSONValue = if upstream.isStdio {
            .array([
                .string(JSString("stdio")),
                upstream.raw.member("command") ?? .null,
                upstream.raw.member("args") ?? .array([]),
                // Absent `cwd` is JSON `null`, not an omitted element — the array length is
                // constant, so a server with no cwd and one with a cwd of `null` hash alike.
                upstream.raw.member("cwd") ?? .null,
                sortedEntries(upstream.raw.member("env"))
            ])
        } else {
            .array([
                .string(JSString(upstream.transport.rawValue)),
                upstream.raw.member("url") ?? .null,
                sortedEntries(upstream.raw.member("headers"))
            ])
        }
        return digest(of: JSStringify.compact(material))
    }

    /// `Object.entries(obj).sort(byKey)` — pairs, with the value left exactly as it was, sorted by
    /// UTF-16 code unit because that is what the reference's comparator does.
    private static func sortedEntries(_ value: JSONValue?) -> JSONValue {
        guard let value, case let .object(members) = value else { return .array([]) }
        let sorted = members.sorted { $0.key < $1.key }
        return .array(sorted.map { .array([.string($0.key), $0.value]) })
    }

    /// sha256, hex, truncated to 16 characters — the reference's `.slice(0, 16)`.
    static func digest(of text: String) -> String {
        let sum = SHA256.hash(data: Data(text.utf8))
        return sum.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
