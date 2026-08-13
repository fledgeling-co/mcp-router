import Foundation
import MCP

/// One tool, exactly as its server advertised it.
///
/// This is the item's own representation rather than the SDK's `Tool`, and the difference is not
/// stylistic. `Tool` is a `Codable` struct with a fixed set of coding keys and an `inputSchema`
/// typed as the SDK's `Value`, whose object case is a Swift `[String: Value]` — a dictionary. So a
/// tool decoded into `Tool` and re-encoded loses three things at once: any member the SDK does not
/// model, the order of every schema member, and the distinction between two keys Swift's `String`
/// considers equal.
///
/// Each of those matters here for a different reason. The unmodeled members matter because what the
/// cache holds is what gets served to clients — a tool description the upstream never wrote is a
/// tool description nobody can audit. The member order matters because the tool-surface digest is
/// taken over `JSON.stringify(schema)`, so reordering members changes the digest and makes every
/// server look like it has changed its tools at once. And the key distinction matters because
/// merging two keys the server sent separately changes those same bytes.
///
/// So the wire JSON is kept whole, and typed accessors are read off it.
public struct CachedTool: Sendable, Hashable {
    /// The object as it arrived, member order intact.
    public let members: [JSONMember]

    public init(members: [JSONMember]) {
        self.members = members
    }

    /// Fails only for a non-object, which is not a tool.
    public init?(_ value: JSONValue) {
        guard case let .object(members) = value else { return nil }
        self.members = members
    }

    public var value: JSONValue { .object(members) }

    /// The member exactly as it is, where a `nil` result means **absent** and `.null` means the
    /// member is there and holds JSON null.
    ///
    /// The distinction is load-bearing in ``DiffTools``, which compares descriptions with
    /// JavaScript's `!==`: `null !== undefined`, so a tool that gained an explicit null description
    /// is a change, and one that never had the member is not.
    public func rawMember(_ key: String) -> JSONValue? {
        let target = JSString(key)
        return members.first(where: { $0.key == target })?.value
    }

    /// JavaScript's `??`: absent **and** `null` both count as missing, which is what the reference's
    /// `t.description ?? ''` and `t.inputSchema ?? {}` mean.
    private func nullish(_ key: String) -> JSONValue? {
        guard let found = rawMember(key), found != .null else { return nil }
        return found
    }

    /// The raw `name` member. Absent is distinct from present-and-not-a-string, because the digest
    /// material embeds whichever it is rather than a normalised form.
    public var nameValue: JSONValue? { nullish("name") }

    /// The name when it is a string, which is the only shape an MCP server may send.
    public var name: JSString? { nameValue?.asString }

    public var descriptionValue: JSONValue? { nullish("description") }

    public var descriptionText: JSString? { descriptionValue?.asString }

    public var inputSchemaValue: JSONValue? { nullish("inputSchema") }

    /// Replaces a member in place when it is already there, and appends otherwise.
    ///
    /// In-place is the load-bearing half: the reference builds the served tool with `{...t, name,
    /// description}`, and a JavaScript spread keeps an existing key at its original position. A
    /// version that removed and re-appended would emit the same members in a different order, and
    /// the manifest's bytes would stop matching.
    public func setting(_ key: String, to newValue: JSONValue) -> CachedTool {
        let target = JSString(key)
        var updated = members
        if let index = updated.firstIndex(where: { $0.key == target }) {
            updated[index] = JSONMember(key: target, value: newValue)
        } else {
            updated.append(JSONMember(key: target, value: newValue))
        }
        return CachedTool(members: updated)
    }

    /// The SDK type, for the protocol boundary a later item serves clients over.
    ///
    /// **Lossy in exactly the ways this type exists to avoid**, so it belongs at the edge and
    /// nowhere else: object members become a dictionary and lose their order, canonically
    /// equivalent keys merge, lone surrogates cannot survive the trip through `String`, and any
    /// member the SDK does not model is dropped. Never round-trip a cached tool through this.
    public func sdkTool() -> Tool {
        Tool(
            name: name?.string ?? "",
            description: descriptionText?.string,
            inputSchema: Self.sdkValue(inputSchemaValue ?? .object([]))
        )
    }

    static func sdkValue(_ value: JSONValue) -> Value {
        switch value {
        case .null: .null
        case let .bool(flag): .bool(flag)
        case let .number(number):
            // The SDK splits integers from doubles; JSON does not. Anything integral and
            // representable goes to `.int` so it re-encodes without a `.0`.
            if number.rounded() == number, number.magnitude < 9.007_199_254_740_992e15 {
                .int(Int(number))
            } else {
                .double(number)
            }
        case let .string(text): .string(text.string)
        case let .array(values): .array(values.map(sdkValue))
        case let .object(members):
            .object(Dictionary(members.map { ($0.key.string, sdkValue($0.value)) }) { _, last in last })
        }
    }
}
