import Foundation

/// Reading and writing one profile's file, by hand rather than through an encoder.
///
/// `scripts/lint/no-wire-codable.sh` forbids `Codable` over this half of the router, and the reason
/// applies to a file as much as to a wire: a reordering encoder makes a byte comparison
/// meaningless, and this file is compared byte for byte by the store's own tests.
public enum ProfileDocument {
    public enum Reading: Sendable {
        case read(ProfileRecord)
        case unreadable(String)
    }

    /// One member's reading. A two-case enum rather than `Result`, because the failure side is a
    /// sentence for a person and not an `Error` anything throws.
    public enum NamesReading: Sendable {
        case names([String])
        case problem(String)
    }

    /// The member order is fixed and is the order below. A profile written twice from the same
    /// record produces the same bytes.
    public static func value(_ record: ProfileRecord) -> JSONValue {
        .object([
            JSONMember(key: JSString("name"), value: .string(JSString(record.name))),
            JSONMember(
                key: JSString("title"),
                value: record.title.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(key: JSString("servers"), value: array(record.servers)),
            JSONMember(key: JSString("skills"), value: array(record.skills)),
            JSONMember(key: JSString("plugins"), value: array(record.plugins)),
            JSONMember(key: JSString("marketplaces"), value: array(record.marketplaces))
        ])
    }

    private static func array(_ names: [String]) -> JSONValue {
        .array(names.map { .string(JSString($0)) })
    }

    /// The name on disk wins over the `name` member.
    ///
    /// They are the same on anything this store wrote. They differ once somebody renames the file,
    /// and then the directory is the truth — a `GET /profiles/<file>` that answered with a
    /// different name than the one requested would be answering about something else.
    public static func read(name: String, text: String) -> Reading {
        let parsed: JSONValue
        do {
            parsed = try JSONParser.parse(text)
        } catch {
            return .unreadable("\(name).json is not valid JSON: \(error)")
        }
        guard parsed.asObjectMembers != nil else {
            return .unreadable("\(name).json is not a JSON object")
        }
        // A member that is present and is not an array of strings is a refusal rather than an empty
        // list, because "this profile selects nothing" and "this file says something this router
        // does not understand" are different facts and only one of them is a selection.
        // An ordered array and not a keyed map, for the reason `no-wire-codable.sh` gives: a Swift
        // `Dictionary` loses member order and code-unit key identity, and this reader's output
        // becomes a wire body one call later.
        var selections: [[String]] = []
        for key in ["servers", "skills", "plugins", "marketplaces"] {
            switch names(in: parsed, key: key) {
            case let .names(values): selections.append(values)
            case let .problem(problem): return .unreadable("\(name).json: \(problem)")
            }
        }
        return .read(ProfileRecord(
            name: name,
            title: parsed.member("title")?.asString?.string,
            servers: selections[0],
            skills: selections[1],
            plugins: selections[2],
            marketplaces: selections[3]
        ))
    }

    private static func names(in value: JSONValue, key: String) -> NamesReading {
        guard let member = value.member(key) else { return .names([]) }
        if case .null = member { return .names([]) }
        guard let entries = member.asArray else {
            return .problem("\"\(key)\" is present and is not an array")
        }
        var out: [String] = []
        for (position, entry) in entries.enumerated() {
            guard let text = entry.asString?.string else {
                return .problem("\(key)[\(position)] is not a string")
            }
            out.append(text)
        }
        return .names(out)
    }
}
