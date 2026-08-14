import CryptoKit
import Foundation

/// The reference's `hashOf(stable(value))` — canonical key order, then `JSON.stringify`, then
/// sha256, hex, **truncated to 32 characters** (`watch.ts:82-97`).
///
/// Two details are load-bearing and easy to get wrong:
///
/// - **The truncation is 32 here and 16 in ``UpstreamHash``.** Two different widths in the same
///   reference. This value is written into `watch-state.json` and read back on the next fire, so a
///   width that disagrees with the reference means a machine switching implementations re-runs one
///   adoption pass it did not need to.
/// - **Key order is sorted recursively, values are not touched.** `JSON.stringify` on an object
///   emits insertion order, so a re-serialisation that reordered keys would look like a change to
///   `mcpServers` and wake the whole adoption path on a file that had not changed — which, for a
///   file Claude Code rewrites constantly, is the difference between a watcher that costs nothing
///   and one that spawns children all day.
///
/// Stringification is ``JSStringify/compact(_:)`` — the same ECMA-faithful emitter ``UpstreamHash``
/// already relies on, including its number formatting and its lowercase `\u` escapes.
public enum StableHash {
    /// `stable()`: sort object keys at every depth, leave arrays and scalars alone.
    public static func stable(_ value: JSONValue) -> JSONValue {
        switch value {
        case let .array(items):
            .array(items.map(stable))
        case let .object(members):
            // `Object.keys(v).sort()` compares UTF-16 code units, which is what `JSString`'s own
            // ordering does — the same comparator `UpstreamHash.sortedEntries` uses.
            .object(members.sorted { $0.key < $1.key }.map {
                JSONMember(key: $0.key, value: stable($0.value))
            })
        default:
            value
        }
    }

    /// sha256, hex, first 32 characters — the reference's `.slice(0, 32)`.
    public static func hash(of value: JSONValue) -> String {
        let text = JSStringify.compact(stable(value))
        let sum = SHA256.hash(data: Data(text.utf8))
        return sum.map { String(format: "%02x", $0) }.joined().prefix(32).description
    }
}
