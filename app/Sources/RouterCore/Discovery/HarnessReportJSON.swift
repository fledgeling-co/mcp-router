import Foundation

/// One encoding of a ``HarnessReport``, shared by the CLI verb and by `GET /harnesses`.
///
/// It exists because there are now two consumers of the same measurement and they must not drift:
/// `mcp-router harnesses --json` is what `scripts/acceptance/r7-harness-reconciliation.sh` asserts
/// against, and the control route is what the Mac app draws. Two encoders would let the lane keep
/// passing while the board read something else.
///
/// Built through ``JSStringify``'s value type rather than `Codable`, which is this repository's
/// wire rule and is enforced for the control directory by `scripts/lint/no-wire-codable.sh`.
///
/// **This file names ``HarnessReport`` and therefore writes nothing.** `no-harness-config-writes.sh`
/// fails any file that pairs R7's reconciliation API with a write, and it is also inside the seam
/// by directory, which is the wider rule.
public enum HarnessReportJSON {
    /// The whole envelope: the port the comparison was made against, the scope it covers, when the
    /// files were read, and a row per harness.
    ///
    /// `readAt` is the board's staleness clock. The brief's own words are that these counts are
    /// only as fresh as the last read and *"a stale reading here is worse than no reading"*, so the
    /// reading carries when it was taken rather than leaving a surface to assume it is now.
    public static func envelope(
        _ reports: [HarnessReport], port: Int, readAtMilliseconds: Double
    ) -> JSONValue {
        .object([
            JSONMember(key: JSString("port"), value: .number(Double(port))),
            JSONMember(key: JSString("scope"), value: .string(JSString("global"))),
            JSONMember(
                key: JSString("readAt"),
                value: .string(JSString(JSDate.iso8601(milliseconds: readAtMilliseconds)))
            ),
            JSONMember(key: JSString("harnesses"), value: .array(reports.map(row)))
        ])
    }

    /// One harness.
    ///
    /// **`unreadable` is the member a consumer reads first.** When it is non-null the harness's
    /// file could not be parsed, and every other member on the row is the *empty* report rather
    /// than a measurement: `state` reads `not-wired`, `entries` and `duplicateCount` read 0. Those
    /// are the same bytes a clean unwired harness produces, and the collision has already cost one
    /// confident wrong answer against `~/.grok/config.toml`.
    public static func row(_ report: HarnessReport) -> JSONValue {
        .object([
            JSONMember(key: JSString("harness"), value: .string(JSString(report.client.rawValue))),
            JSONMember(
                key: JSString("displayName"), value: .string(JSString(report.client.displayName))
            ),
            JSONMember(key: JSString("path"), value: .string(JSString(report.path))),
            JSONMember(key: JSString("exists"), value: .bool(report.exists)),
            JSONMember(
                key: JSString("unreadable"),
                value: report.unreadable.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(key: JSString("state"), value: .string(JSString(stateWord(report.state)))),
            JSONMember(key: JSString("route"), value: .string(JSString(routeWord(report.route)))),
            // The bridge is the cost the shim reading names — `mcp-remote`, one extra process per
            // session. It is a member of its own rather than folded into a sentence, because the
            // sentence belongs to the reading and the reading is drawn by the app.
            JSONMember(
                key: JSString("bridge"),
                value: bridgeName(report.route).map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(key: JSString("entries"), value: .number(Double(report.entryCount))),
            JSONMember(
                key: JSString("duplicateCount"), value: .number(Double(report.duplicates.count))
            ),
            JSONMember(
                key: JSString("duplicates"), value: .array(report.duplicates.map(duplicateRow))
            ),
            JSONMember(
                key: JSString("unparsed"),
                value: .array(report.unparsed.map { .string(JSString($0)) })
            ),
            JSONMember(
                key: JSString("httpCapability"),
                value: .string(JSString(report.capability.summary))
            ),
            // The provenance as a word, beside the sentence that spells it out. A surface that has
            // to decide whether to offer a fix or a question needs the discriminator, and parsing
            // it back out of English is how two readers come to disagree about one fact.
            JSONMember(
                key: JSString("capability"),
                value: .string(JSString(capabilityWord(report.capability)))
            )
        ])
    }

    public static func duplicateRow(_ duplicate: Duplicate) -> JSONValue {
        .object([
            JSONMember(
                key: JSString("harnessName"), value: .string(JSString(duplicate.harnessName))
            ),
            JSONMember(key: JSString("routerName"), value: .string(JSString(duplicate.routerName))),
            JSONMember(key: JSString("basis"), value: .string(JSString(basisWord(duplicate.basis))))
        ])
    }

    public static func stateWord(_ state: HarnessState) -> String {
        switch state {
        case .notWired: "not-wired"
        case .wiredViaHTTP: "wired-http"
        case .wiredViaShim: "wired-shim"
        case .wiredWithDuplicates: "wired-with-duplicates"
        }
    }

    public static func routeWord(_ route: HarnessRoute) -> String {
        switch route {
        case .notWired: "none"
        case .directHTTP: "http"
        case .stdioShim: "stdio-shim"
        }
    }

    public static func basisWord(_ basis: DuplicateBasis) -> String {
        switch basis {
        case .name: "name"
        case .identity: "identity"
        }
    }

    static func capabilityWord(_ capability: HTTPCapability) -> String {
        switch capability {
        case .measured: "measured"
        case .documented: "documented"
        case .unknown: "unknown"
        }
    }

    /// What bridges a shimmed harness to this router, or nil when nothing does.
    ///
    /// Read off ``HarnessRoute`` rather than off ``HarnessState``, because the duplicate reading
    /// carries the route inside it — a harness can be shimmed *and* declaring duplicates, and the
    /// shim's cost does not stop being real because there is a second finding on the same row.
    static func bridgeName(_ route: HarnessRoute) -> String? {
        switch route {
        case .notWired, .directHTTP: nil
        case let .stdioShim(_, bridge, _): bridge
        }
    }
}
