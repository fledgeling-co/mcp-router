import Foundation

/// The window, as something a person can take away — JSON or CSV.
///
/// **One fold, two encoders.** Both read the same ``CapabilityUseWindow``, so a row that appears in
/// one and not the other is impossible by construction rather than by discipline. The brief asks for
/// export "for team reporting", and the failure that would make it worthless is the export and the
/// board disagreeing about the same day.
///
/// The export carries no more than the board does. There is no raw-event mode and no prompt
/// anywhere: ``InvocationEvent`` has no member for one, so there is nothing here to leave out.
public enum InvocationExport {
    /// The column order, and the header row's text. Named once so the two encoders cannot drift and
    /// so a test can assert the header exactly.
    public static let columns = ["kind", "name", "version", "runs", "lastUsed", "perDay"]

    public static func json(_ window: CapabilityUseWindow) -> JSONValue {
        .object([
            JSONMember(key: "generatedAt", value: .string(JSString(window.generatedAt))),
            JSONMember(key: "days", value: .number(Double(window.days))),
            JSONMember(key: "windowStart", value: .string(JSString(window.windowStart))),
            JSONMember(key: "horizon", value: optional(window.horizon)),
            JSONMember(key: "ledgerHorizon", value: optional(window.ledgerHorizon)),
            JSONMember(key: "rows", value: .array(window.rows.map(row))),
            // Beside the rows, never folded into them. Together with `attributedRuns` these three
            // sum to every run in the window, which is what makes the table readable as a fraction
            // of the traffic rather than as the whole of it.
            JSONMember(key: "attributedRuns", value: .number(Double(window.attributedRuns))),
            JSONMember(key: "supersededRuns", value: .number(Double(window.supersededRuns))),
            JSONMember(key: "unestablishedRuns", value: .number(Double(window.unestablishedRuns))),
            JSONMember(key: "totalRuns", value: .number(Double(window.totalRuns))),
            JSONMember(key: "harnesses", value: .array(window.harnesses.map(harness))),
            JSONMember(key: "reading", value: window.accounting.value)
        ])
    }

    /// One row per capability-version, plus a header. The three unattributed figures ride in a
    /// trailing comment line rather than as data rows, because a spreadsheet that summed the `runs`
    /// column and got the traffic total would be summing two different things.
    public static func csv(_ window: CapabilityUseWindow) -> String {
        var lines = [columns.joined(separator: ",")]
        for row in window.rows {
            lines.append([
                field(row.kind.rawValue),
                field(row.name),
                field(row.version),
                String(row.runs),
                field(row.lastUsed),
                field(row.perDay.map(String.init).joined(separator: " "))
            ].joined(separator: ","))
        }
        lines.append("")
        lines.append(
            "# attributed=\(window.attributedRuns) superseded=\(window.supersededRuns) "
                + "unestablished=\(window.unestablishedRuns) total=\(window.totalRuns)"
        )
        return lines.joined(separator: "\n") + "\n"
    }

    private static func row(_ row: CapabilityUseRow) -> JSONValue {
        .object([
            JSONMember(key: "kind", value: .string(JSString(row.kind.rawValue))),
            JSONMember(key: "name", value: .string(JSString(row.name))),
            JSONMember(key: "version", value: .string(JSString(row.version))),
            JSONMember(key: "runs", value: .number(Double(row.runs))),
            JSONMember(key: "lastUsed", value: .string(JSString(row.lastUsed))),
            JSONMember(key: "perDay", value: .array(row.perDay.map { .number(Double($0)) }))
        ])
    }

    /// A harness with no figure carries `null` and the reason. Never `0` — `DESIGN.md` §6, and the
    /// same rule `/insights` follows for a harness the router cannot tell from another program.
    private static func harness(_ count: HarnessInvocationCount) -> JSONValue {
        var members: [JSONMember] = [
            JSONMember(key: "harness", value: .string(JSString(count.harness))),
            JSONMember(key: "runs", value: optional(count.runs.map { Double($0) }))
        ]
        if let reason = count.reason {
            members.append(JSONMember(key: "reason", value: .string(JSString(reason))))
        }
        return .object(members)
    }

    private static func optional(_ text: String?) -> JSONValue {
        text.map { JSONValue.string(JSString($0)) } ?? .null
    }

    private static func optional(_ number: Double?) -> JSONValue {
        number.map { JSONValue.number($0) } ?? .null
    }

    /// RFC 4180 quoting. A capability name is a path segment and cannot hold a comma today, and
    /// quoting anyway is the difference between a rule and a coincidence — the day a name can, this
    /// keeps working instead of shifting every column after it.
    static func field(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") else { return text }
        return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
