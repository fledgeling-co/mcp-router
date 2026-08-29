import Foundation

/// Building a ``FreshnessReport`` from the store, and nothing else. **It reads and writes nothing
/// outside the store**, reaches no network and spawns no child.
///
/// That last property is why F6 holds no timer. The check reads one descriptor per entry and one
/// per catalogue — 127 and 10 respectively on this machine — so the cost that would justify a
/// background schedule is not there, and a cached report would be a third thing able to disagree
/// with the disk. What a caller needs is not a cadence inside the daemon but an answer that says how
/// old its evidence is, which is `staleAfterMilliseconds` and the per-catalogue age.
public enum ExtensionFreshnessScan {
    /// One day — the interval the brief's own example names.
    public static let defaultStaleAfterMilliseconds: Double = 86_400_000

    public static func build(
        store: any ExtensionStoring,
        kinds: [ExtensionKind] = ExtensionKind.allCases,
        staleAfterMilliseconds: Double = defaultStaleAfterMilliseconds,
        now: Double,
        name: String? = nil
    ) -> FreshnessReport {
        let context = Context(store: store, staleAfter: staleAfterMilliseconds, now: now)
        var rows: [FreshnessRow] = []
        var unreadable: [String] = []

        for kind in kinds {
            let listing = store.list(kind)
            if let reason = listing.unreadable { unreadable.append(reason) }
            for record in listing.records where name == nil || record.name == name {
                rows.append(context.row(kind: kind, record: record))
            }
        }
        return FreshnessReport(
            rows: rows,
            catalogues: context.readings(),
            checkedAtMilliseconds: now,
            staleAfterMilliseconds: staleAfterMilliseconds,
            unreadable: unreadable
        )
    }

    /// Reads each catalogue at most once, and keeps the reading whether or not any row needed it.
    private final class Context {
        let store: any ExtensionStoring
        let staleAfter: Double
        let now: Double
        private var catalogues: [String: MarketplaceCatalogue?] = [:]
        private var read: [String: CatalogueReading] = [:]
        private let marketplaceRoot: String

        init(store: any ExtensionStoring, staleAfter: Double, now: Double) {
            self.store = store
            self.staleAfter = staleAfter
            self.now = now
            marketplaceRoot = store.list(.marketplaces).root
        }

        func readings() -> [CatalogueReading] {
            read.values.sorted { $0.name < $1.name }
        }

        func row(kind: ExtensionKind, record: ExtensionRecord) -> FreshnessRow {
            switch kind {
            case .plugins:
                return pluginRow(record)
            case .skills:
                return FreshnessRow(
                    kind: kind, name: record.name, catalogue: nil,
                    verdict: skillVerdict(record)
                )
            case .marketplaces:
                // A catalogue has none above it. Its own freshness is the age of its tree, which is
                // the reading carried beside this row rather than a comparison invented for it.
                _ = catalogue(named: record.name)
                return FreshnessRow(
                    kind: kind, name: record.name, catalogue: record.name,
                    verdict: .noCatalogue(
                        "a marketplace is the catalogue; its freshness is the age of its own tree, "
                            + "reported beside this row"
                    )
                )
            }
        }

        /// A skill is a directory and nothing in this store offers it, so there is no comparison to
        /// make. It is listed rather than omitted, for the reason `notOffered` is: an absent row and
        /// an entry nothing can be said about are different problems with different fixes.
        private func skillVerdict(_ record: ExtensionRecord) -> FreshnessVerdict {
            guard record.version != nil else { return .installedDeclaresNoVersion }
            return .noCatalogue(
                "no catalogue in this store offers a skill, so \(record.name)'s declared version "
                    + "has nothing to be compared against"
            )
        }

        /// A plugin's name is `<plugin>@<marketplace>` — R30's identity, and Claude's own.
        private func pluginRow(_ record: ExtensionRecord) -> FreshnessRow {
            let split = record.name.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            guard split.count == 2, !split[0].isEmpty, !split[1].isEmpty else {
                return FreshnessRow(
                    kind: .plugins, name: record.name, catalogue: nil,
                    verdict: .noCatalogue(
                        "\"\(record.name)\" does not name a marketplace, so no catalogue can be "
                            + "resolved for it"
                    )
                )
            }
            let plugin = String(split[0])
            let market = String(split[1])
            let reading = catalogue(named: market)
            let problem = reading.problem
            let offer = catalogues[market].flatMap { $0 }?.offer(named: plugin)
            return FreshnessRow(
                kind: .plugins, name: record.name, catalogue: market,
                verdict: ExtensionFreshness.compare(
                    installedVersion: record.version, offer: offer, catalogueProblem: problem
                )
            )
        }

        @discardableResult
        private func catalogue(named market: String) -> CatalogueReading {
            if let existing = read[market] { return existing }
            let path = (marketplaceRoot as NSString).appendingPathComponent(market)
            let stamp = ExtensionStamp.measure(path)
            let parsed = store.descriptorText(.marketplaces, name: market)
                .flatMap { MarketplaceCatalogue.read(text: $0) }
            catalogues[market] = parsed
            // A negative age is not a young one. When the catalogue's newest file is stamped ahead
            // of the router's clock — skew, a restored backup, an archive extracted with its own
            // timestamps — the difference is unmeasurable rather than small, and reporting it as a
            // number would make that catalogue read as fresh against EVERY window, which is the one
            // failure this whole item is about. It is `null` with the reason instead
            // (`DESIGN.md` §6).
            let raw = stamp.map { now - $0.newestModifiedMilliseconds }
            let age = (raw ?? 0) < 0 ? nil : raw
            let problem: String? = if stamp == nil {
                "this store holds no marketplace named \"\(market)\", so there is no catalogue to "
                    + "compare against"
            } else if parsed == nil {
                "\"\(market)\"'s \(ExtensionKind.marketplaces.descriptorPath) could not be read as "
                    + "a catalogue"
            } else {
                nil
            }
            // A negative age is not a young one. When the catalogue's newest file is stamped ahead
            // of the router's clock — skew, a restored backup, an archive extracted with its own
            // timestamps — the difference is unmeasurable rather than small, and reporting it as a
            // number would make that catalogue read as fresh against EVERY window, which is the one
            // failure this whole item is about. It is `null` with the reason instead
            // (`DESIGN.md` §6). It is NOT `problem`: the catalogue still parses and its offers are
            // still comparable, so this must not suppress a single verdict.
            let ageProblem: String? = if stamp != nil, age == nil {
                "\"\(market)\"'s newest file is stamped ahead of this router's clock, so how old "
                    + "the catalogue is cannot be said"
            } else {
                nil
            }
            let reading = CatalogueReading(
                name: market,
                path: path,
                newestModifiedMilliseconds: stamp?.newestModifiedMilliseconds,
                ageMilliseconds: age,
                // An unknown age is reported rather than assumed stale: `false` here is
                // "not known to be stale", and `problem` says why it is not known.
                stale: age.map { $0 > staleAfter } ?? false,
                refreshable: FileManager.default.fileExists(
                    atPath: (path as NSString).appendingPathComponent(".git")
                ),
                offers: parsed?.offers.count ?? 0,
                declaredNoVersion: parsed?.declaredNoVersion ?? 0,
                problem: problem,
                ageProblem: ageProblem
            )
            read[market] = reading
            return reading
        }
    }
}
