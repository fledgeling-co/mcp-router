import Foundation
import Testing
@testable import RouterCore

/// The join, and the refusals that are the item.
///
/// The assertions that matter here are the ones that say a number **did not** move. A test that only
/// checked attribution would pass against an implementation that credits every run to the installed
/// version, which is the exact defect `spec-F5.md` §2.2 exists to refuse — so each of those is
/// written beside its inverse, where removing the boundary makes the count move.
@Suite("Versions at the moment a run happened")
struct InvocationVersionTests {
    /// 2026-08-27T12:00:00.000Z. Named rather than inlined because the fold's window is seven whole
    /// days ending with the day this falls in, so every fixture timestamp below is positioned
    /// against it — and an unnamed literal is how a fixture silently drifts outside its own window.
    private static let noon20260827 = 1_787_832_000_000.0

    /// A boundary, spelled the way a test reads best: `at` · `kind` · `name` · `version`.
    ///
    /// A named function rather than a four-member tuple, because this repository's linter caps a
    /// tuple at two and it is right to — an unlabelled `("2026-08-01T…", .plugin, "p@m", "1.4.2")`
    /// puts the two strings that matter most in positions nothing names.
    private static func boundary(
        _ at: String, _ kind: CapabilityKind, _ name: String, _ version: String
    ) -> VersionObservation {
        VersionObservation(ts: at, kind: kind, name: name, version: version, source: "test")
    }

    private static func ledger(_ rows: [VersionObservation]) -> VersionLedger {
        VersionLedger(observations: rows)
    }

    // MARK: - A6, A7 — attributed, and superseded

    @Test("A run after the newest boundary is attributed to that version")
    func runAfterTheBoundaryIsAttributed() {
        let ledger = Self.ledger([Self.boundary("2026-08-01T00:00:00.000Z", .plugin, "p@m", "1.4.2")])
        let outcome = ledger.version(of: .plugin, "p@m", at: "2026-08-20T09:00:00.000Z")
        #expect(outcome.version == "1.4.2")
        #expect(outcome.outcome == "attributed")
    }

    /// The whole argument in one assertion. The run sits between two boundaries carrying different
    /// versions, so the swap happened at an unknown moment around it and **neither** version may
    /// claim it.
    @Test("A run bracketed by a version change is superseded and counts toward nothing")
    func runBeforeALaterChangeIsSuperseded() {
        let ledger = Self.ledger([
            Self.boundary("2026-08-01T00:00:00.000Z", .plugin, "p@m", "1.4.0"),
            Self.boundary("2026-08-25T00:00:00.000Z", .plugin, "p@m", "1.4.2")
        ])
        let outcome = ledger.version(of: .plugin, "p@m", at: "2026-08-20T09:00:00.000Z")
        #expect(outcome.outcome == "superseded")
        #expect(outcome.version == nil)
        // The inverse, in the same test, so the assertion above is watched being able to change its
        // answer: with the later boundary gone, the same run IS attributable. A `superseded`
        // expectation that held either way would be measuring nothing.
        let withoutTheLaterBoundary = Self.ledger([
            Self.boundary("2026-08-01T00:00:00.000Z", .plugin, "p@m", "1.4.0")
        ])
        #expect(
            withoutTheLaterBoundary.version(of: .plugin, "p@m", at: "2026-08-20T09:00:00.000Z")
                .version == "1.4.0"
        )
    }

    @Test("A later boundary carrying the SAME version confirms rather than supersedes")
    func unchangedLaterBoundaryDoesNotSupersede() {
        let ledger = Self.ledger([
            Self.boundary("2026-08-01T00:00:00.000Z", .plugin, "p@m", "1.4.0"),
            Self.boundary("2026-08-25T00:00:00.000Z", .plugin, "p@m", "1.4.0")
        ])
        #expect(ledger.version(of: .plugin, "p@m", at: "2026-08-20T09:00:00.000Z").version == "1.4.0")
    }

    @Test("A run before the oldest boundary is unestablished, never the installed version")
    func runBeforeTheHorizonIsUnestablished() {
        let ledger = Self.ledger([Self.boundary("2026-08-10T00:00:00.000Z", .plugin, "p@m", "1.4.2")])
        let outcome = ledger.version(of: .plugin, "p@m", at: "2026-07-01T09:00:00.000Z")
        #expect(outcome.outcome == "unestablished")
        #expect(outcome.version == nil)
    }

    // MARK: - The plugin-name collision R30 measured

    @Test("A skill resolves through its plugin, and refuses when the name is in two marketplaces")
    func ambiguousPluginPrefixRefuses() {
        let single = Self.ledger([
            Self.boundary("2026-08-01T00:00:00.000Z", .plugin, "tailings@fledgeling", "1.0.0")
        ])
        #expect(single.version(ofSkill: "tailings:tailings", at: "2026-08-20T09:00:00.000Z")
            .version == "1.0.0")

        // 13 plugin names exist in two marketplaces at once on this machine (R30 §1.2), and
        // `ship-feature` is one of them. Taking the first match would be wrong about half the time
        // on exactly the plugins this repository's own pipeline uses most.
        let ambiguous = Self.ledger([
            Self.boundary("2026-08-01T00:00:00.000Z", .plugin, "ship-feature@fledgeling", "2.4.0"),
            Self.boundary("2026-08-01T00:00:00.000Z", .plugin, "ship-feature@diolog", "1.1.0")
        ])
        let outcome = ambiguous.version(
            ofSkill: "ship-feature:ship-feature", at: "2026-08-20T09:00:00.000Z"
        )
        #expect(outcome.outcome == "unestablished")
        #expect(outcome.version == nil)
    }

    // MARK: - A8 — the version a descriptor declares, and the digest when it declares none

    @Test("A skill declaring a version reads declared; one that does not reads a byte digest")
    func versionReadingFallsBackToBytes() {
        let withVersion = CapabilityVersionReading.read(
            .skills, descriptor: "---\nname: t\nversion: 1.4.2\n---\n# t\nversion: 9.9.9 in prose\n",
            digest: "abc123def4567890", path: "SKILL.md"
        )
        #expect(withVersion.display == "1.4.2")
        #expect(withVersion.source == "declared")

        // Nine of this machine's 22 skills declare no version, so this is the ordinary case.
        let without = CapabilityVersionReading.read(
            .skills, descriptor: "---\nname: t\n---\n# t\n",
            digest: "abc123def4567890", path: "SKILL.md"
        )
        #expect(without.display == "bytes:abc123def456")
        #expect(without.source == "derived")

        let nothing = CapabilityVersionReading.read(
            .skills, descriptor: nil, digest: nil, path: "SKILL.md"
        )
        #expect(nothing.isPinnable == false)
        #expect(nothing.unpinnableReason != nil)
    }

    /// A `version:` line outside the frontmatter is prose, not a declaration. Every SKILL.md in this
    /// repository's own plugin tree is a document that discusses versions.
    @Test("A version line outside the frontmatter is not read as a declaration")
    func proseVersionIsNotADeclaration() {
        let reading = CapabilityVersionReading.read(
            .skills, descriptor: "# t\n\nversion: 9.9.9\n", digest: "ff00ff00ff00ff00",
            path: "SKILL.md"
        )
        #expect(reading.source == "derived")
    }

    // MARK: - Seeding from the register

    @Test("installed_plugins.json seeds one boundary per record, and counts what it skipped")
    func seedReadsLastUpdated() throws {
        let text = #"""
        {"version":2,"plugins":{
          "a@m":[{"version":"1.1.0","installedAt":"2025-12-03T05:30:52.695Z",
                  "lastUpdated":"2026-06-18T03:32:37.892Z","gitCommitSha":"423563c"}],
          "b@m":[{"version":"2.0.0","installedAt":"2025-12-03T05:30:52.695Z"}]
        }}
        """#
        let parsed = try JSONParser.parse(text)
        let seed = InstalledPluginsLedgerSeed.observations(in: parsed)
        #expect(seed.observations.count == 1)
        #expect(seed.observations.first?.name == "a@m")
        #expect(seed.observations.first?.ts == "2026-06-18T03:32:37.892Z")
        #expect(seed.observations.first?.source == InstalledPluginsLedgerSeed.source)
        // A record with no `lastUpdated` is skipped and counted. 127 records producing 100
        // boundaries is a different corpus from 100 producing 100.
        #expect(seed.skipped == 1)
    }

    // MARK: - The fold, and the figures beside the table

    @Test("The fold credits only attributable runs and reports the rest beside them")
    func foldSeparatesTheUnattributable() {
        let ledger = Self.ledger([
            Self.boundary("2026-08-01T00:00:00.000Z", .server, "obscura", "0.1.0"),
            Self.boundary("2026-08-25T00:00:00.000Z", .server, "obscura", "0.2.0")
        ])
        let events = [
            // After the newest boundary — attributable to 0.2.0.
            InvocationEvent(
                ts: "2026-08-26T09:00:00.000Z", kind: .server, name: "obscura", harness: "claude-code"
            ),
            InvocationEvent(
                ts: "2026-08-26T11:00:00.000Z", kind: .server, name: "obscura", harness: "claude-code"
            ),
            // Between the boundaries, and inside the window — superseded. The window is seven whole
            // days ending 2026-08-27, so a run on the 20th would be dropped for being out of window
            // before the join ever saw it, and this test would pass for the wrong reason.
            InvocationEvent(
                ts: "2026-08-22T09:00:00.000Z", kind: .server, name: "obscura", harness: "claude-code"
            ),
            // A capability the ledger has never heard of.
            InvocationEvent(
                ts: "2026-08-26T09:00:00.000Z", kind: .server, name: "ghost", harness: "claude-code"
            )
        ]
        let window = InvocationInsights.fold(
            events: events, ledger: ledger,
            reading: InvocationReading(
                harnesses: [HarnessInvocationCount(harness: "claude-code", runs: 4)],
                accounting: TranscriptAccounting()
            ),
            nowMilliseconds: Self.noon20260827,
            days: 7
        )
        #expect(window.rows.count == 1)
        #expect(window.rows.first?.version == "0.2.0")
        #expect(window.rows.first?.runs == 2)
        #expect(window.supersededRuns == 1)
        #expect(window.unestablishedRuns == 1)
        // The identity that makes the table readable beside the headline.
        #expect(
            window.attributedRuns + window.supersededRuns + window.unestablishedRuns
                == window.totalRuns
        )
        #expect(window.totalRuns == 4)
    }

    @Test("A harness with no observable transcript reports null runs and a reason, never zero")
    func unobservableHarnessReportsNull() throws {
        let window = InvocationInsights.fold(
            events: [], ledger: Self.ledger([]),
            reading: InvocationReading(
                harnesses: [HarnessInvocationCount(
                    harness: "grok",
                    runs: nil,
                    reason: "its jsonl files are sandbox events, not transcripts"
                )],
                accounting: TranscriptAccounting()
            ),
            nowMilliseconds: Self.noon20260827,
            days: 7
        )
        let row = try #require(window.harnesses.first)
        #expect(row.runs == nil)
        #expect(row.reason != nil)
        let encoded = JSStringify.compact(InvocationExport.json(window))
        #expect(encoded.contains(#""runs":null"#))
    }

    // MARK: - A12 — one fold, two encoders

    @Test("The CSV and the JSON carry the same rows")
    func exportsAgree() {
        let ledger = Self.ledger([Self.boundary("2026-08-01T00:00:00.000Z", .skill, "trawl", "1.4.2")])
        let window = InvocationInsights.fold(
            events: [InvocationEvent(
                ts: "2026-08-26T09:00:00.000Z", kind: .skill, name: "trawl", harness: "claude-code"
            )],
            ledger: ledger,
            reading: InvocationReading(harnesses: [], accounting: TranscriptAccounting()),
            nowMilliseconds: Self.noon20260827,
            days: 7
        )
        let csv = InvocationExport.csv(window)
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.first == InvocationExport.columns.joined(separator: ","))
        #expect(lines.contains { $0.hasPrefix("skill,trawl,1.4.2,1,") })
        // The three unattributed figures ride in a trailing comment rather than as data rows, so a
        // spreadsheet summing the runs column is not summing two different things.
        #expect(csv.contains("# attributed=1 superseded=0 unestablished=0 total=1"))
        let json = JSStringify.compact(InvocationExport.json(window))
        #expect(json.contains(#""name":"trawl""#))
        #expect(json.contains(#""version":"1.4.2""#))
    }
}
