import Foundation

/// The half of the quarantine diff that was not being shown.
///
/// The router holds a tool-surface change when **either** the description **or** the input schema
/// differs — `src/manifest.ts:80-93` compares both and ships both on `ToolShape`. The review sheet
/// rendered only the description, which meant a server that left its description untouched and
/// rewrote `inputSchema` produced a card showing two identical text fields and no indication that
/// anything had changed at all.
///
/// That is worse than not holding the change, because it manufactures the appearance of review: the
/// user is asked to accept a diff they cannot see. A tool that adds a `context` parameter it never
/// previously asked for is the shape an exfiltration takes, and it is invisible in a
/// description-only diff.
///
/// Two rules here are about being *readable* rather than merely present, because a diff nobody can
/// read fails the same way a missing one does. The schema arrives as `JSON.stringify(inputSchema)`
/// — one unformatted line, often long — so both sides are decoded, compared structurally, and
/// re-encoded sorted and indented. That means a change lands on its own line, and a difference in
/// serialisation order is correctly reported as no change at all.
public enum SchemaDiff {
    /// One top-level parameter that differs between the approved schema and the pending one.
    public struct ParameterChange: Equatable, Sendable, Identifiable, Hashable {
        public enum Kind: String, Equatable, Sendable, Hashable, CaseIterable {
            /// An input the tool did not previously ask for. **The case that matters.**
            case added
            case removed
            case altered
        }

        public let name: String
        public let kind: Kind

        public init(name: String, kind: Kind) {
            self.name = name
            self.kind = kind
        }

        public var id: String { "\(kind.rawValue)|\(name)" }

        /// What the card says about this parameter.
        public var sentence: String {
            switch kind {
            case .added: "adds \(name)"
            case .removed: "no longer takes \(name)"
            case .altered: "changes \(name)"
            }
        }

        /// Whether this change is marked in `--attn`.
        ///
        /// Only an addition is. A new input a tool did not previously ask for is the one the reader
        /// must not have to find by eye; a removed or altered parameter is worth reading and is not
        /// the shape a fresh exfiltration takes. `--attn` means "wants a human decision", which is
        /// exactly what an added input is asking for.
        public var wantsAttention: Bool { kind == .added }
    }

    public enum Result: Equatable, Sendable {
        /// The two schemas are structurally the same. Serialisation order alone lands here, which
        /// is the point of comparing decoded values rather than strings.
        case identical

        /// They differ. `parameters` is the top-level summary; the two pretty-printed forms are for
        /// the reader who wants the whole thing.
        case changed(parameters: [ParameterChange], beforePretty: String, afterPretty: String)

        /// One or both sides could not be decoded.
        ///
        /// **Never folded into `identical`.** A decode path whose failure mode is "no change" is
        /// the silent-empty shape `SWIFT_PRACTICES.md` §2 names as the worst available, and here it
        /// would quietly pass an unreviewable schema through the one surface meant to review it.
        case unreadable(beforeRaw: String, afterRaw: String, reason: String)
    }

    /// Compare the approved schema against the pending one.
    ///
    /// Absent on both sides is `identical` — a tool that never declared a schema and still does not
    /// has not changed. Absent on one side is a real difference and is reported as such.
    public static func compare(before: String?, after: String?) -> Result {
        let beforeRaw = before ?? ""
        let afterRaw = after ?? ""

        if beforeRaw.isEmpty, afterRaw.isEmpty { return .identical }

        guard let beforeValue = decode(beforeRaw) else {
            return .unreadable(
                beforeRaw: beforeRaw,
                afterRaw: afterRaw,
                reason: "The approved schema is not readable as JSON."
            )
        }
        guard let afterValue = decode(afterRaw) else {
            return .unreadable(
                beforeRaw: beforeRaw,
                afterRaw: afterRaw,
                reason: "The pending schema is not readable as JSON."
            )
        }

        if equal(beforeValue, afterValue) { return .identical }

        return .changed(
            parameters: parameterChanges(from: beforeValue, to: afterValue),
            beforePretty: pretty(beforeValue) ?? beforeRaw,
            afterPretty: pretty(afterValue) ?? afterRaw
        )
    }

    // MARK: - Decoding and comparison

    /// An empty string decodes as an empty object rather than failing: a tool declaring no schema
    /// and one declaring `{}` are the same tool, and reporting the transition between them as
    /// unreadable would put a scary banner on a non-event.
    private static func decode(_ raw: String) -> Any? {
        if raw.isEmpty { return [String: Any]() }
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Structural equality over decoded JSON.
    ///
    /// `NSDictionary`'s own `isEqual` does this correctly and recursively for the value types
    /// `JSONSerialization` produces, and it is order-insensitive for dictionaries — which is the
    /// behaviour that makes a re-serialised-in-a-different-order schema report as unchanged.
    private static func equal(_ lhs: Any, _ rhs: Any) -> Bool {
        (lhs as AnyObject).isEqual(rhs as AnyObject)
    }

    /// The top-level `properties` of a JSON Schema, which is where a tool's parameters live.
    private static func properties(of value: Any) -> [String: Any] {
        guard let object = value as? [String: Any] else { return [:] }
        if let declared = object["properties"] as? [String: Any] { return declared }
        // A schema with no `properties` key declares no parameters. Falling back to the whole
        // object here would report every schema keyword as a parameter.
        return [:]
    }

    private static func parameterChanges(from before: Any, to after: Any) -> [ParameterChange] {
        let old = properties(of: before)
        let new = properties(of: after)

        var changes: [ParameterChange] = []
        // Added first, then altered, then removed — the order the card reads them in, and the
        // order of how much they matter.
        for name in new.keys.sorted() where old[name] == nil {
            changes.append(ParameterChange(name: name, kind: .added))
        }
        for name in new.keys.sorted() {
            guard let oldValue = old[name], let newValue = new[name] else { continue }
            if !equal(oldValue, newValue) {
                changes.append(ParameterChange(name: name, kind: .altered))
            }
        }
        for name in old.keys.sorted() where new[name] == nil {
            changes.append(ParameterChange(name: name, kind: .removed))
        }
        return changes
    }

    /// Sorted keys and indentation, so a one-field change is a one-line change rather than a
    /// difference buried in the middle of a single very long string.
    private static func pretty(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value) else { return nil }
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Copy

    /// Shown when the schema changed and the description did not — the case that previously drew
    /// two identical fields and left the reader to wonder what they were looking at.
    public static let descriptionUnchanged = """
    The description is unchanged. What changed is the shape of the input this tool accepts.
    """

    /// The header above the parameter summary.
    public static let parametersHeading = "What the input changed"

    /// Shown above the two pretty-printed schemas.
    public static let approvedSchemaHeading = "Approved schema"
    public static let pendingSchemaHeading = "Pending schema"
}
