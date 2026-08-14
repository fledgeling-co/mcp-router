import Foundation

public extension ToolShape {
    /// `{description, schema}` — each member omitted when the reference omits it.
    ///
    /// `description` is the raw member, so an explicit JSON `null` survives as null while an absent
    /// one is left out; the two are different to the reference's `!==` comparison and therefore
    /// different on the wire (S3). `schema` is absent on a removal, which is why it is optional
    /// here rather than defaulted to `"{}"`.
    var value: JSONValue {
        var members: [JSONMember] = []
        if let description {
            members.append(JSONMember(key: "description", value: description))
        }
        if let schema {
            members.append(JSONMember(key: "schema", value: .string(JSString(schema))))
        }
        return .object(members)
    }
}

public extension ToolChange {
    /// One entry of `/servers/:name/changes`.
    ///
    /// Member order is the reference's literal — `kind, name, before, after, invisible` — with
    /// every absent member omitted rather than emitted as null. The recorded fixture shows all
    /// three shapes this produces: a `changed` entry carrying both sides and `invisible`, an
    /// `added` entry with only `after`, and a `removed` entry whose `before` carries a description
    /// and **no** schema.
    var value: JSONValue {
        var members: [JSONMember] = [
            JSONMember(key: "kind", value: .string(JSString(kind.rawValue)))
        ]
        if let name {
            members.append(JSONMember(key: "name", value: name))
        }
        if let before {
            members.append(JSONMember(key: "before", value: before.value))
        }
        if let after {
            members.append(JSONMember(key: "after", value: after.value))
        }
        if let invisible {
            members.append(JSONMember(
                key: "invisible", value: .array(invisible.map { .string(JSString($0)) })
            ))
        }
        return .object(members)
    }
}
