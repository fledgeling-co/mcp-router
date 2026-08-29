import Foundation

/// Which model judges, which one judges when the first cannot, and how often.
///
/// `fallback` is optional and `primary` is not: a ladder with one rung is a coherent choice and a
/// ladder with none is not a configuration, it is an analyst that cannot run. The refusal for an
/// unknown lane names the member and the value, because a settings file that silently reverted to a
/// default would report a model the user did not choose — which is the one thing `usedFallback`
/// exists to keep honest, one layer up.
public struct AnalystSettings: Sendable, Hashable {
    public var primary: AnalystLane
    public var fallback: AnalystLane?
    public var cadence: AnalystCadence

    public init(
        primary: AnalystLane = .claude,
        fallback: AnalystLane? = .grok,
        cadence: AnalystCadence = .sixHourly
    ) {
        self.primary = primary
        self.fallback = fallback
        self.cadence = cadence
    }

    /// The rungs in the order they are tried, first to last, with no repeats.
    ///
    /// A fallback equal to the primary is collapsed rather than refused: it is not a contradiction,
    /// it is a ladder whose second rung is the first one again, and running the same failing binary
    /// twice would report two attempts where the machine made one.
    public var ladder: [AnalystLane] {
        guard let fallback, fallback != primary else { return [primary] }
        return [primary, fallback]
    }
}

/// Why a settings change was refused, with enough in it for a 422 to say which member to fix.
public struct AnalystSettingsRefusal: Error, Sendable, Hashable {
    public let member: String
    public let value: String

    public init(member: String, value: String) {
        self.member = member
        self.value = value
    }

    public var message: String {
        "\(member): \"\(value)\" is not one of \(AnalystSettingsCoding.accepted(for: member))"
    }
}

/// Reading and writing settings as JSON, through this repository's own JSON stack.
///
/// `JSONValue` rather than `Codable` for the reason `scripts/lint/no-wire-codable.sh` states about
/// every other path that reaches the wire: these three members are served on `GET /insights` and
/// accepted on `PATCH /insights/analyst`, and a `Codable` conformance decides member order and
/// missing-key behaviour somewhere the author cannot see.
public enum AnalystSettingsCoding {
    static func accepted(for member: String) -> String {
        let names = member == "cadence"
            ? AnalystCadence.allCases.map(\.rawValue)
            : AnalystLane.allCases.map(\.rawValue)
        return names.joined(separator: ", ")
    }

    /// Parse a settings object. **An absent member keeps the value it had**, which is what makes
    /// `PATCH` a patch; a member that is present and unrecognised is refused rather than dropped.
    public static func apply(
        _ value: JSONValue, to current: AnalystSettings
    ) throws(AnalystSettingsRefusal) -> AnalystSettings {
        var next = current
        if let raw = value.member("primary") {
            next.primary = try lane(raw, member: "primary")
        }
        if let raw = value.member("fallback") {
            // An explicit null is a ladder with one rung, and it is distinguishable from an absent
            // member: the first clears the fallback, the second leaves it alone.
            if case .null = raw {
                next.fallback = nil
            } else {
                next.fallback = try lane(raw, member: "fallback")
            }
        }
        if let raw = value.member("cadence") {
            let text = raw.asString?.string ?? ""
            guard let parsed = AnalystCadence(rawValue: text) else {
                throw AnalystSettingsRefusal(member: "cadence", value: text)
            }
            next.cadence = parsed
        }
        return next
    }

    private static func lane(
        _ value: JSONValue, member: String
    ) throws(AnalystSettingsRefusal) -> AnalystLane {
        let text = value.asString?.string ?? ""
        guard let parsed = AnalystLane(rawValue: text) else {
            throw AnalystSettingsRefusal(member: member, value: text)
        }
        return parsed
    }

    /// The stored form. Read back by ``parse(_:)``; served, in a wider envelope, by the route.
    public static func encode(_ settings: AnalystSettings) -> JSONValue {
        .object([
            JSONMember(key: JSString("primary"), value: .string(JSString(settings.primary.rawValue))),
            JSONMember(
                key: JSString("fallback"),
                value: settings.fallback.map { .string(JSString($0.rawValue)) } ?? .null
            ),
            JSONMember(key: JSString("cadence"), value: .string(JSString(settings.cadence.rawValue)))
        ])
    }

    /// Read stored settings, falling back to the defaults for anything the file does not hold.
    ///
    /// Lenient where ``apply(_:to:)`` is strict, and deliberately: a `PATCH` is a person making a
    /// choice now, where a stored file may have been written by an older build. A stored lane this
    /// build does not know is dropped to the default rather than refused, because refusing would
    /// leave the analyst unrunnable with no route back.
    public static func parse(_ value: JSONValue) -> AnalystSettings {
        (try? apply(value, to: AnalystSettings())) ?? AnalystSettings()
    }
}
