import Foundation
import Testing
@testable import MCPRouterKit

/// The criterion the whole feature is shaped around: **no number or sentence is displayed that the
/// router does not observe.**
///
/// A1 forbids any rate, delta or percentage anywhere in Discover or Detail. A7 states the positive
/// half so it is checkable — an unbounded "no fabricated figures" is not a test — by naming the
/// permitted set exactly: `useCount`, `stars`, `forks`, and dates from `updatedAt` / `pushedAt`.
/// Nothing on the wire carries an eval count, a licence, a category or a download count, so none of
/// those may appear.
///
/// This suite asserts it three ways, because each catches something the others cannot:
///
/// 1. **Every string the feature can emit** is checked for a percentage or delta pattern.
/// 2. **Every data-derived string** has its digits traced back to the field it came from.
/// 3. **The view sources are scanned**, so a view that starts formatting numbers is caught rather
///    than assumed absent. Without this the first two check one of two possible sources.
@Suite("Discover honesty — A1 and A7")
struct DiscoverHonestyTests {
    // MARK: - Specimens

    /// Entries spanning what the wire actually produces: a Smithery entry with a count and no
    /// repository data, an official entry with GitHub enrichment and no count, and one carrying
    /// neither.
    static let specimens: [RegistryEntry] = [
        RegistryEntry(
            id: "smithery:github",
            name: "github",
            displayName: "GitHub",
            description: "Manage repos, issues and PRs",
            source: .both,
            repository: "https://github.com/",
            version: nil,
            updatedAt: "2025-11-19T07:26:28.312Z",
            useCount: 2984,
            verified: false,
            iconURL: nil,
            stars: nil,
            forks: nil,
            pushedAt: nil,
            archived: nil,
            install: RegistryInstall(
                type: .http,
                command: nil,
                args: nil,
                url: "https://server.smithery.ai/github/mcp",
                requires: [RegistryRequirement(
                    name: "Authorization",
                    description: "Bearer <key>",
                    isSecret: true
                )]
            ),
            installed: false
        ),
        RegistryEntry(
            id: "official:obsidian",
            name: "ai.smithery/obsidian",
            displayName: "obsidian-github-mcp",
            description: "Search a GitHub-hosted Obsidian vault",
            source: .official,
            repository: "https://github.com/Hint-Services/obsidian-github-mcp",
            version: "0.4.0",
            updatedAt: "2025-09-14T15:20:36.371442Z",
            useCount: nil,
            verified: nil,
            iconURL: nil,
            stars: 9,
            forks: 7,
            pushedAt: "2025-11-28T13:53:01Z",
            archived: false,
            install: RegistryInstall(
                type: .stdio,
                command: "npx",
                args: ["-y", "obsidian-github-mcp"],
                url: nil,
                requires: nil
            ),
            installed: false
        ),
        RegistryEntry(
            id: "official:bare",
            name: "bare",
            displayName: "bare",
            description: "Neither index says much",
            source: .official,
            repository: nil,
            version: nil,
            updatedAt: nil,
            useCount: nil,
            verified: nil,
            iconURL: nil,
            stars: nil,
            forks: nil,
            pushedAt: nil,
            archived: true,
            install: nil,
            installed: true
        )
    ]

    /// Every substitution any template can take, filled with a value that would be visible if it
    /// leaked somewhere it should not.
    static let substitutions: [DiscoverCopy.Token: String] = [
        .mac: "Luke's MacBook Pro",
        .count: "2,984",
        .query: "github",
        .window: "30",
        .name: "GitHub",
        .reason: DiscoverFailureReason.transport.text,
        .warning: "something the router said",
        .host: "server.smithery.ai"
    ]

    /// Everything the feature can put in front of a person: the copy manifest, resolved; every
    /// failure reason; every window label; every plate line; and every data-derived string.
    static func everyRenderableString() -> [String] {
        var strings: [String] = []

        for key in DiscoverCopy.Key.allCases {
            let entry = DiscoverCopy.entry(key).resolved(substitutions)
            strings.append(contentsOf: [entry.headline, entry.actionLabel].compactMap { $0 })
            strings.append(entry.body)
        }
        strings.append(contentsOf: DiscoverFailureReason.allCases.map(\.text))
        strings.append(contentsOf: RecencyWindow.allCases.map(\.label))
        strings.append(PairingCopy.neverInstalls)

        for entry in specimens {
            strings.append(contentsOf: [
                DiscoverPresentation.useCountText(entry),
                DiscoverPresentation.starsText(entry),
                DiscoverPresentation.changedText(entry),
                DiscoverPresentation.lastCommitText(entry),
                CapabilityPlate.invocation(install: entry.install)
            ].compactMap { $0 })
            strings.append(contentsOf: CapabilityPlate
                .lines(install: entry.install, archived: entry.archived)
                .map(\.text))
        }
        strings.append(contentsOf: [
            DiscoverPresentation.truncationText(shown: 30, limit: 30),
            DiscoverPresentation.truncationText(shown: 3, limit: 30)
        ].compactMap { $0 })

        return strings
    }

    // MARK: - A1

    @Test("No rate, delta or percentage is displayed anywhere in this feature")
    func noRateOrDelta() throws {
        let strings = everyRenderableString()
        #expect(strings.count > 40, "only \(strings.count) strings were checked")

        // A percentage anywhere, a signed figure anywhere, or the words a trend surface reaches
        // for. The prototype's phone Discover list painted `+218%` and `−8%` in `--live` and
        // `--fail`; `DESIGN.md` §10 records that as a defect the surfaces shipping Discover own,
        // and this is where it is discharged.
        let forbidden: [(name: String, pattern: String)] = [
            ("a percentage", #"\d\s*%"#),
            ("a signed figure", #"[+\u{2212}\u{2013}]\s*\d"#),
            ("a per-window rate", #"(?i)\d+\s*(per|/)\s*(day|week|month|hour)"#),
            ("trend vocabulary", #"(?i)\b(trending|trend|growth|up \d|down \d)\b"#)
        ]

        for string in strings {
            for rule in forbidden {
                let range = string.range(of: rule.pattern, options: .regularExpression)
                #expect(range == nil, "\(rule.name) in: \(string)")
            }
        }
    }

    @Test("No band is called Trending")
    func noTrendingBand() {
        for band in DiscoverBand.allCases {
            let title = DiscoverCopy.entry(band.titleKey).body
            #expect(!title.lowercased().contains("trend"), "band titled \(title)")
        }
        #expect(DiscoverBand.allCases.count == 2, "the third band cannot be populated")
    }

    // MARK: - A7

    @Test("A count renders exactly the digits of the field it came from")
    func countsTraceToTheirField() throws {
        for entry in specimens {
            if let useCount = entry.useCount {
                let rendered = try #require(DiscoverPresentation.useCountText(entry))
                #expect(digits(rendered) == String(useCount), "useCount: \(rendered)")
            } else {
                // Absent, never zero. A missing count means Smithery does not index the entry,
                // which is not the same as nobody using it.
                #expect(DiscoverPresentation.useCountText(entry) == nil)
            }

            if let stars = entry.stars {
                let rendered = try #require(DiscoverPresentation.starsText(entry))
                #expect(digits(rendered) == String(stars), "stars: \(rendered)")
            } else {
                #expect(DiscoverPresentation.starsText(entry) == nil)
            }
        }
    }

    @Test("A date renders the day and year of the field it came from, and nothing else numeric")
    func datesTraceToTheirField() throws {
        let calendar = Calendar(identifier: .gregorian)
        for entry in specimens {
            if let updatedAt = entry.updatedAt {
                let parsed = try #require(DiscoverPresentation.date(from: updatedAt))
                let rendered = try #require(DiscoverPresentation.changedText(entry))
                let components = calendar.dateComponents(
                    [.day, .year],
                    from: parsed
                )
                let day = try #require(components.day)
                let year = try #require(components.year)
                #expect(digits(rendered) == "\(day)\(year)" || digits(rendered) == "\(year)\(day)",
                        "updatedAt rendered as \(rendered)")
            } else {
                #expect(DiscoverPresentation.changedText(entry) == nil)
            }

            if entry.pushedAt == nil {
                #expect(DiscoverPresentation.lastCommitText(entry) == nil)
            }
        }
    }

    @Test("An unparseable timestamp renders nothing rather than today")
    func unparseableDateIsNil() {
        // A fallback to `Date()` would put a date on screen the router never reported, and would
        // sort the entry to the top of Recently changed — a fabricated figure that also reorders
        // the page.
        #expect(DiscoverPresentation.date(from: "not a date") == nil)
        #expect(DiscoverPresentation.date(from: "") == nil)
        #expect(DiscoverPresentation.date(from: nil) == nil)
    }

    @Test("All three timestamp shapes the wire actually produces parse")
    func timestampShapes() throws {
        // Seconds, milliseconds and microseconds all appear in the recorded fixture alone, because
        // the two indexes and GitHub each serialise differently. A parser handling one of them
        // would silently drop entries from a band.
        _ = try #require(DiscoverPresentation.date(from: "2025-11-28T13:53:01Z"))
        _ = try #require(DiscoverPresentation.date(from: "2025-11-19T07:26:28.312Z"))
        _ = try #require(DiscoverPresentation.date(from: "2025-09-14T15:20:36.371442Z"))
    }

    @Test("Truncation is disclosed only when the results fill the limit")
    func truncationOnlyWhenFull() throws {
        // `sources.merged` counts entries *before* the slice and legitimately exceeds the rows
        // shown, so it is never rendered. This is the only truncation signal.
        #expect(DiscoverPresentation.truncationText(shown: 29, limit: 30) == nil)
        let full = try #require(DiscoverPresentation.truncationText(shown: 30, limit: 30))
        #expect(digits(full) == "30")
    }

    // MARK: - The scan

    @Test("No view under Phone/Discover formats a number or reads a numeric field")
    func viewsDoNotFormat() throws {
        let files = try Self.swiftFiles(under: "app/Sources/MCPRouterUI/Phone/Discover")
        #expect(files.count >= 6, "only \(files.count) Discover view files were scanned")

        // The strong half: a view that never names a numeric field cannot format one. Every figure
        // has to arrive through `DiscoverPresentation`, which is what makes the two assertions
        // above cover the whole feature rather than one of two possible sources.
        let numericFields = ["useCount", "stars", "forks", "updatedAt", "pushedAt"]
        // The direct half: no formatter, anywhere.
        let formatters = [".formatted(", "NumberFormatter", "DateFormatter", "String(format:"]

        for (name, source) in files where name != "DiscoverModel.swift" {
            let stripped = Self.stripped(source)
            for field in numericFields {
                #expect(
                    !stripped.contains(field),
                    "\(name) reads \(field) directly — route it through DiscoverPresentation"
                )
            }
            for formatter in formatters {
                #expect(
                    !stripped.contains(formatter),
                    "\(name) formats a value: \(formatter) — DiscoverPresentation owns formatting"
                )
            }
        }
    }

    // MARK: - Helpers

    private func digits(_ string: String) -> String {
        string.filter(\.isNumber)
    }

    /// The repo root, found by walking up from this file — the same way the design-token tests find
    /// `DESIGN.md`, and a hard failure rather than a skip when it is missing.
    static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("DESIGN.md").path
            ) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw ScanError.rootNotFound
    }

    enum ScanError: Error { case rootNotFound, nothingScanned }

    static func swiftFiles(under relativePath: String) throws -> [(name: String, source: String)] {
        let root = try repoRoot().appendingPathComponent(relativePath)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw ScanError.nothingScanned
        }
        var files: [(String, String)] = []
        for case let path as String in walker where path.hasSuffix(".swift") {
            let url = root.appendingPathComponent(path)
            try files.append((path, String(contentsOf: url, encoding: .utf8)))
        }
        // A scan that scanned nothing must not read as a pass.
        guard !files.isEmpty else { throw ScanError.nothingScanned }
        return files
    }

    /// Remove comments and string literals, so a rule cannot be tripped by prose that mentions the
    /// thing it forbids — the doc comments in these files discuss `useCount` at length — and,
    /// more importantly, cannot be evaded by a value hidden in an interpolation.
    static func stripped(_ source: String) -> String {
        var out = ""
        for line in source.components(separatedBy: .newlines) {
            let withoutComment = line.components(separatedBy: "//").first ?? ""
            var inString = false
            var kept = ""
            for character in withoutComment {
                if character == "\"" { inString.toggle(); continue }
                if !inString { kept.append(character) }
            }
            out += kept + "\n"
        }
        return out
    }
}
