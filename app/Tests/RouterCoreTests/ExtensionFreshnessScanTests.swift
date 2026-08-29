import Foundation
import Testing
@testable import RouterCore

/// F6 — the report, against a **real** store on disk.
///
/// Real rather than a double, for the reason `ExtensionStoreTests` gives and one of this item's
/// own: the catalogue's age comes from `ExtensionStamp.measure` walking a directory tree, and
/// `refreshable` comes from a `.git` directory existing. Neither is observable in memory, and both
/// are what the report's honesty rests on.
@Suite("F6 — the freshness report")
struct ExtensionFreshnessScanTests {
    private static func scratch() -> String {
        NSTemporaryDirectory() + "mcprouter-f6-" + UUID().uuidString
    }

    /// A store holding one marketplace and whichever plugins and skills the case needs.
    private struct Bench {
        let root: String
        let store: DiskExtensionStore

        init() {
            root = ExtensionFreshnessScanTests.scratch()
            store = DiskExtensionStore(root: root, clock: FixedMillisecondClock(1000))
        }

        /// Written with `FileManager` rather than through `add`, and that is the subject rather
        /// than convenience. `add` refuses a descriptor whose `name` differs from the entry name,
        /// and the real store cannot satisfy it: R30 stores a plugin under
        /// `<plugin>@<marketplace>` while the `plugin.json` Claude wrote says `<plugin>`, which is
        /// why R30 uses `adopt` and not `add`. A fixture built through `add` would be a shape the
        /// product never holds, and the version this report reads would be read off it.
        func write(_ kind: ExtensionKind, _ name: String, _ text: String) {
            let entry = ((root as NSString).appendingPathComponent(kind.rawValue) as NSString)
                .appendingPathComponent(name)
            let descriptor = (entry as NSString).appendingPathComponent(kind.descriptorPath)
            try? FileManager.default.createDirectory(
                atPath: (descriptor as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try? text.write(toFile: descriptor, atomically: true, encoding: .utf8)
        }

        func marketplace(_ name: String, offers: [(String, String?)]) {
            let body = offers.map { offer in
                offer.1.map { "{\"name\":\"\(offer.0)\",\"version\":\"\($0)\"}" }
                    ?? "{\"name\":\"\(offer.0)\"}"
            }.joined(separator: ",")
            write(.marketplaces, name, "{\"name\":\"\(name)\",\"plugins\":[\(body)]}")
        }

        /// The descriptor names the plugin, NOT the `<plugin>@<marketplace>` it is stored under —
        /// the shape `adopt` produces from a real Claude tree.
        func plugin(_ name: String, version: String?) {
            let bare = String(name.split(separator: "@", maxSplits: 1)[0])
            let versionMember = version.map { ",\"version\":\"\($0)\"" } ?? ""
            write(.plugins, name, "{\"name\":\"\(bare)\"\(versionMember)}")
        }

        func skill(_ name: String, version: String?) {
            let versionLine = version.map { "version: \($0)\n" } ?? ""
            write(.skills, name, "---\nname: \(name)\ndescription: a skill\n\(versionLine)---\n")
        }

        /// A marketplace entry that looks like a git checkout, made with `mkdir` rather than
        /// through the API so the report is reading the disk and not a record of a call.
        func makeGitCheckout(_ name: String) {
            let path = ((root as NSString).appendingPathComponent("marketplaces") as NSString)
                .appendingPathComponent(name)
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).appendingPathComponent(".git"),
                withIntermediateDirectories: true
            )
        }

        func cleanup() { try? FileManager.default.removeItem(atPath: root) }
    }

    private static func row(_ report: FreshnessReport, _ name: String) -> FreshnessRow? {
        report.rows.first { $0.name == name }
    }

    // MARK: - Every verdict, reached through the store

    @Test("G1 — all eight verdicts are reachable through a real store")
    func everyVerdict() {
        let bench = Bench()
        defer { bench.cleanup() }
        bench.marketplace("mkt", offers: [
            ("behind", "2.0.0"), ("level", "1.0.0"), ("ahead", "1.0.0"),
            ("sha", "aa11bb22cc33"), ("silent", nil), ("unversioned", "1.0.0")
        ])
        bench.plugin("behind@mkt", version: "1.0.0")
        bench.plugin("level@mkt", version: "1.0.0")
        bench.plugin("ahead@mkt", version: "2.0.0")
        bench.plugin("sha@mkt", version: "ed404106fcd8")
        bench.plugin("silent@mkt", version: "1.0.0")
        bench.plugin("unversioned@mkt", version: nil)
        bench.plugin("dropped@mkt", version: "1.0.0")
        bench.plugin("orphan@gone", version: "1.0.0")
        bench.skill("noversion", version: nil)
        bench.skill("versioned", version: "3.0.0")

        let report = ExtensionFreshnessScan.build(store: bench.store, now: 10_000)

        #expect(Self.row(report, "behind@mkt")?.verdict.state == "update-available")
        #expect(Self.row(report, "level@mkt")?.verdict.state == "current")
        #expect(Self.row(report, "ahead@mkt")?.verdict.state == "catalogue-behind")
        #expect(Self.row(report, "sha@mkt")?.verdict.state == "unorderable")
        #expect(Self.row(report, "silent@mkt")?.verdict.state == "catalogue-declares-no-version")
        #expect(Self.row(report, "unversioned@mkt")?.verdict.state == "installed-declares-no-version")
        #expect(Self.row(report, "dropped@mkt")?.verdict.state == "not-offered")
        #expect(Self.row(report, "orphan@gone")?.verdict.state == "no-catalogue")
        #expect(Self.row(report, "noversion")?.verdict.state == "installed-declares-no-version")
        #expect(Self.row(report, "versioned")?.verdict.state == "no-catalogue")

        // Exactly one update over ten entries, which is the number the fixture puts there.
        #expect(report.summary.updatesAvailable == 1)
    }

    /// The summary's whole job. Zero updates produced by comparing everything and zero produced by
    /// comparing nothing are different answers, and this is the pair that tells them apart.
    @Test("G2 — compared and uncomparable partition the rows and sum to total")
    func summaryPartitions() {
        let bench = Bench()
        defer { bench.cleanup() }
        bench.marketplace("mkt", offers: [("a", "2.0.0"), ("b", nil)])
        bench.plugin("a@mkt", version: "1.0.0")
        bench.plugin("b@mkt", version: "1.0.0")
        bench.plugin("c@mkt", version: "1.0.0")
        bench.skill("s", version: nil)

        let report = ExtensionFreshnessScan.build(store: bench.store, now: 10_000)
        #expect(report.summary.total == 5) // four entries plus the marketplace's own row
        #expect(report.summary.compared + report.summary.uncomparable == report.summary.total)
        #expect(report.summary.compared == 1)
        #expect(report.summary.updatesAvailable == 1)
    }

    // MARK: - The catalogue's age

    @Test("G3 — a catalogue older than the window is stale, and a fresh one is not")
    func staleness() {
        let bench = Bench()
        defer { bench.cleanup() }
        bench.marketplace("mkt", offers: [("a", "1.0.0")])
        bench.plugin("a@mkt", version: "1.0.0")

        let realNow = Date().timeIntervalSince1970 * 1000
        let fresh = ExtensionFreshnessScan.build(
            store: bench.store, staleAfterMilliseconds: 86_400_000, now: realNow
        )
        #expect(fresh.catalogues.first { $0.name == "mkt" }?.stale == false)

        // The same store, asked a year later. Nothing on disk moved; only the window did.
        let later = ExtensionFreshnessScan.build(
            store: bench.store, staleAfterMilliseconds: 86_400_000,
            now: realNow + 365 * 86_400_000
        )
        let reading = later.catalogues.first { $0.name == "mkt" }
        #expect(reading?.stale == true)
        #expect((reading?.ageMilliseconds ?? 0) > 86_400_000)
        #expect(later.summary.staleCatalogues == 1)

        // And the verdict itself is UNCHANGED by staleness. A stale catalogue does not turn
        // `current` into something else; it puts an age beside it.
        #expect(Self.row(later, "a@mkt")?.verdict.state == "current")
    }

    /// Two of the ten marketplaces on this machine are not git checkouts, so a report implying
    /// every catalogue could be refreshed would be wrong for one in five.
    @Test("G4 — refreshable reads the disk, and is false without a .git directory")
    func refreshable() {
        let bench = Bench()
        defer { bench.cleanup() }
        bench.marketplace("plain", offers: [])
        bench.marketplace("cloned", offers: [])
        bench.makeGitCheckout("cloned")
        bench.plugin("a@plain", version: "1.0.0")
        bench.plugin("b@cloned", version: "1.0.0")

        let report = ExtensionFreshnessScan.build(store: bench.store, now: 10_000)
        #expect(report.catalogues.first { $0.name == "plain" }?.refreshable == false)
        #expect(report.catalogues.first { $0.name == "cloned" }?.refreshable == true)
    }

    /// An age that could not be measured is `null` and `stale` is false — "not known to be stale"
    /// rather than "fresh". A zero age would read as *just refreshed* and make every verdict taken
    /// against that catalogue look freshly checked.
    @Test("G5 — a missing catalogue carries a null age and never a zero one")
    func missingCatalogueAge() {
        let bench = Bench()
        defer { bench.cleanup() }
        bench.plugin("a@gone", version: "1.0.0")

        let report = ExtensionFreshnessScan.build(store: bench.store, now: 10_000)
        let reading = report.catalogues.first { $0.name == "gone" }
        #expect(reading?.newestModifiedMilliseconds == nil)
        #expect(reading?.ageMilliseconds == nil)
        #expect(reading?.stale == false)
        #expect(reading?.problem != nil)
        #expect(Self.row(report, "a@gone")?.verdict.state == "no-catalogue")
    }

    /// The other side of G3: a clock BEHIND the catalogue's newest file. `null`, not a negative
    /// number, because a negative age exceeds no window and would read as fresh forever.
    @Test("G10 — a catalogue stamped ahead of the clock has a null age, at any window")
    func futureStamp() {
        let bench = Bench()
        defer { bench.cleanup() }
        bench.marketplace("mkt", offers: [("a", "1.0.0")])
        bench.plugin("a@mkt", version: "1.0.0")

        for window in [0.0, 1.0, 86_400_000.0] {
            let report = ExtensionFreshnessScan.build(
                store: bench.store, staleAfterMilliseconds: window, now: 1000
            )
            let reading = report.catalogues.first { $0.name == "mkt" }
            #expect(reading?.ageMilliseconds == nil)
            #expect(reading?.stale == false)
            #expect(reading?.ageProblem?.contains("stamped ahead") == true)
            // The catalogue still READ, so it still suppresses nothing: the comparison against it
            // is unchanged. Folding the age problem into `problem` turned this into `no-catalogue`.
            #expect(reading?.problem == nil)
            #expect(report.rows.first { $0.name == "a@mkt" }?.verdict.state == "current")
            #expect(report.summary.staleCatalogues == 0)
        }
    }

    @Test("G6 — the catalogue reports how many offers declared no version")
    func declaredNoVersionIsCounted() {
        let bench = Bench()
        defer { bench.cleanup() }
        bench.marketplace("mkt", offers: [("a", "1.0.0"), ("b", nil), ("c", nil)])
        bench.plugin("a@mkt", version: "1.0.0")

        let report = ExtensionFreshnessScan.build(store: bench.store, now: 10_000)
        let reading = report.catalogues.first { $0.name == "mkt" }
        #expect(reading?.offers == 3)
        #expect(reading?.declaredNoVersion == 2)
    }

    // MARK: - The reading is of the bytes

    /// The store holds no index, so a catalogue edited underneath the router must change the next
    /// answer. This is the assertion that would fail if a cache were ever introduced.
    @Test("G7 — editing the catalogue on disk changes the next report")
    func readsTheDisk() {
        let bench = Bench()
        defer { bench.cleanup() }
        bench.marketplace("mkt", offers: [("a", "1.0.0")])
        bench.plugin("a@mkt", version: "1.0.0")
        #expect(
            ExtensionFreshnessScan.build(store: bench.store, now: 10_000)
                .summary.updatesAvailable == 0
        )

        let manifest = ((((bench.root as NSString).appendingPathComponent("marketplaces")
            as NSString).appendingPathComponent("mkt") as NSString)
            .appendingPathComponent(".claude-plugin") as NSString)
            .appendingPathComponent("marketplace.json")
        try? "{\"name\":\"mkt\",\"plugins\":[{\"name\":\"a\",\"version\":\"9.9.9\"}]}"
            .write(toFile: manifest, atomically: true, encoding: .utf8)

        let after = ExtensionFreshnessScan.build(store: bench.store, now: 10_000)
        #expect(after.summary.updatesAvailable == 1)
        #expect(Self.row(after, "a@mkt")?.verdict == .updateAvailable(installed: "1.0.0", available: "9.9.9"))
    }

    @Test("G8 — a kind filter and a name filter narrow the rows without changing a verdict")
    func filters() {
        let bench = Bench()
        defer { bench.cleanup() }
        bench.marketplace("mkt", offers: [("a", "2.0.0")])
        bench.plugin("a@mkt", version: "1.0.0")
        bench.skill("s", version: "1.0.0")

        let plugins = ExtensionFreshnessScan.build(
            store: bench.store, kinds: [.plugins], now: 10_000
        )
        #expect(plugins.rows.count == 1)
        #expect(plugins.rows[0].verdict.state == "update-available")

        let named = ExtensionFreshnessScan.build(store: bench.store, now: 10_000, name: "s")
        #expect(named.rows.count == 1)
        #expect(named.rows[0].kind == .skills)
    }

    /// An empty store is a report of zero rows, not a failure — and `updatesAvailable == 0` there
    /// is honest because `compared == 0` sits beside it.
    @Test("G9 — an empty store reports zero rows and zero comparisons")
    func emptyStore() {
        let bench = Bench()
        defer { bench.cleanup() }
        let report = ExtensionFreshnessScan.build(store: bench.store, now: 10_000)
        #expect(report.rows.isEmpty)
        #expect(report.summary.total == 0)
        #expect(report.summary.compared == 0)
        #expect(report.summary.updatesAvailable == 0)
    }
}
