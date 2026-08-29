import Foundation

/// The JSON `GET /extensions/updates` answers with.
///
/// Built out of ``JSONValue`` members in a fixed order rather than through an encoder, the
/// constraint `scripts/lint/no-wire-codable.sh` enforces over this half of the router.
///
/// **Every member is always present, and an unobserved figure is `null` rather than `0`.** A
/// catalogue whose age could not be measured carries `null` beside the sentence saying why, because
/// a zero age is a measurement and this is an absence (`DESIGN.md` §6). The distinction is
/// load-bearing here rather than decorative: an age of zero reads as *just refreshed* and would
/// make every verdict taken against that catalogue look freshly checked.
extension ControlHandler {
    static func freshnessValue(_ report: FreshnessReport) -> JSONValue {
        .object([
            JSONMember(key: JSString("checkedAtMs"), value: .number(report.checkedAtMilliseconds)),
            JSONMember(
                key: JSString("staleAfterMs"), value: .number(report.staleAfterMilliseconds)
            ),
            JSONMember(key: JSString("summary"), value: summaryValue(report.summary)),
            JSONMember(
                key: JSString("catalogues"), value: .array(report.catalogues.map(catalogueValue))
            ),
            JSONMember(key: JSString("entries"), value: .array(report.rows.map(rowValue))),
            JSONMember(
                key: JSString("unreadable"),
                value: .array(report.unreadable.map { .string(JSString($0)) })
            )
        ])
    }

    /// `compared` and `uncomparable` are both here, and they sum to `total`.
    ///
    /// That is the summary's whole job. *Zero updates over 127 plugins* is produced identically by
    /// a healthy machine and by a checker that read nothing, and the pair of counts is what tells
    /// those two apart in a reply somebody is about to act on.
    static func summaryValue(_ summary: FreshnessSummary) -> JSONValue {
        .object([
            JSONMember(key: JSString("total"), value: .number(Double(summary.total))),
            JSONMember(
                key: JSString("updatesAvailable"), value: .number(Double(summary.updatesAvailable))
            ),
            JSONMember(key: JSString("compared"), value: .number(Double(summary.compared))),
            JSONMember(key: JSString("uncomparable"), value: .number(Double(summary.uncomparable))),
            JSONMember(
                key: JSString("staleCatalogues"), value: .number(Double(summary.staleCatalogues))
            )
        ])
    }

    static func catalogueValue(_ reading: CatalogueReading) -> JSONValue {
        .object([
            JSONMember(key: JSString("name"), value: .string(JSString(reading.name))),
            JSONMember(key: JSString("path"), value: .string(JSString(reading.path))),
            JSONMember(
                key: JSString("newestModifiedMs"),
                value: reading.newestModifiedMilliseconds.map { JSONValue.number($0) } ?? .null
            ),
            JSONMember(
                key: JSString("ageMs"),
                value: reading.ageMilliseconds.map { JSONValue.number($0) } ?? .null
            ),
            JSONMember(key: JSString("stale"), value: .bool(reading.stale)),
            JSONMember(key: JSString("refreshable"), value: .bool(reading.refreshable)),
            JSONMember(key: JSString("offers"), value: .number(Double(reading.offers))),
            JSONMember(
                key: JSString("declaredNoVersion"),
                value: .number(Double(reading.declaredNoVersion))
            ),
            JSONMember(
                key: JSString("problem"),
                value: reading.problem.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            // Separate from `problem`, because the two suppress different things: a catalogue that
            // could not be READ offers nothing to compare, while one whose AGE could not be taken
            // still compares perfectly well and only loses its freshness figure.
            JSONMember(
                key: JSString("ageProblem"),
                value: reading.ageProblem.map { JSONValue.string(JSString($0)) } ?? .null
            )
        ])
    }

    static func rowValue(_ row: FreshnessRow) -> JSONValue {
        .object([
            JSONMember(key: JSString("kind"), value: .string(JSString(row.kind.rawValue))),
            JSONMember(key: JSString("name"), value: .string(JSString(row.name))),
            JSONMember(
                key: JSString("catalogue"),
                value: row.catalogue.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(key: JSString("state"), value: .string(JSString(row.verdict.state))),
            JSONMember(
                key: JSString("installed"),
                value: row.verdict.installedVersion.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(
                key: JSString("available"),
                value: row.verdict.availableVersion.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            // The one boolean a caller is likely to branch on, present so nobody has to re-derive
            // it from the slug and get `catalogue-behind` wrong.
            JSONMember(key: JSString("hasUpdate"), value: .bool(row.verdict.hasUpdate)),
            JSONMember(key: JSString("compared"), value: .bool(row.verdict.isComparison)),
            JSONMember(key: JSString("reason"), value: .string(JSString(row.verdict.sentence)))
        ])
    }
}
