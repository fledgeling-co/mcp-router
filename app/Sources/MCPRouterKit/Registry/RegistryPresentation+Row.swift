import Foundation

/// How one row reads: what its date means, what its one figure is, and the sanitising every
/// third-party string passes through before a view ever sees it.
///
/// Split from `RegistryPresentation` for length alone — this is the same type, and the reasoning
/// that governs it is documented on the base declaration. Three groups live here because they
/// share one property: each turns a field an index chose into something a row may safely draw.
public extension RegistryPresentation {
    // MARK: - The date, and its two meanings

    /// What a row's `updatedAt` actually means.
    ///
    /// `RegistryMerge.officialRow` takes it from `_meta` — a **registry-entry update**.
    /// `RegistryMerge.smitheryRow` takes it from Smithery's **`createdAt`** — a **first-published**
    /// date. One wire field, two meanings, and which one is settled by `provenance` rather than by
    /// `source`, for the reason `Provenance` documents at length.
    enum DateMeaning: String, Sendable, Equatable, CaseIterable {
        case entryUpdated
        case firstPublished

        public var verb: String {
            switch self {
            case .entryUpdated: "updated"
            case .firstPublished: "added"
            }
        }
    }

    static func dateMeaning(for entry: RegistryEntry) -> DateMeaning {
        provenance(for: entry).isOfficial ? .entryUpdated : .firstPublished
    }

    struct DateCell: Equatable, Sendable {
        public var text: String
        public var meaning: DateMeaning
    }

    /// The date as it reads on a row, or `nil` when there is no parseable date.
    ///
    /// `nil` rather than a placeholder: `updatedAt` is optional on the wire, and an em-dash where a
    /// date belongs is a quieter lie than a wrong date but a lie all the same. The cell is simply
    /// not drawn.
    static func dateCell(for entry: RegistryEntry) -> DateCell? {
        guard let date = timestamp(entry.updatedAt) else { return nil }
        let meaning = dateMeaning(for: entry)
        return DateCell(text: "\(meaning.verb) \(dayFormatter.string(from: date))", meaning: meaning)
    }

    /// When GitHub last saw a push to the repository — an index-independent fact, and the best
    /// answer available to "is this still alive".
    ///
    /// Shown in the detail sheet rather than on the row: it is present only where enrichment
    /// reached, so a row column would be empty for most rows and read as a claim about them. It is
    /// never an ordering, for the same reason stars are not.
    static func lastPushed(for entry: RegistryEntry) -> String? {
        guard let date = timestamp(entry.pushedAt) else { return nil }
        return "code last pushed \(dayFormatter.string(from: date))"
    }

    /// Both shapes the indexes actually emit.
    ///
    /// Smithery sends `2025-11-19T07:26:28.312Z` and the official registry
    /// `2025-09-14T15:20:36.371442Z` — three and six fractional digits — while GitHub's `pushedAt`
    /// has none. One formatter configured for fractional seconds rejects the third; one configured
    /// without rejects the first two. Trying both is what makes every real row parse, and
    /// `asControlAPIDate` already does exactly that for every other surface in the app.
    ///
    /// **Delegated rather than reimplemented, and the reason is the compiler's.** The obvious
    /// version holds the two `ISO8601DateFormatter`s as `static let`s so they are built once.
    /// `ISO8601DateFormatter` is not `Sendable`, so under Swift 6 a `static let` of one is a
    /// concurrency error — which is what this file did, and it did not compile. `DateFormatter`
    /// and `NumberFormatter` *are* `@unchecked Sendable`, which is why `dayFormatter` and
    /// `decimalFormatter` below are held as statics and these are not.
    static func timestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.asControlAPIDate
    }

    /// Held once. A `DateFormatter` built per row is the classic way a table becomes slow.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d MMM y")
        return formatter
    }()

    // MARK: - The figure

    /// The one number a row carries, with its unit and where it came from.
    ///
    /// Never a bare integer: `2,984` and `9` on adjacent rows under one heading would read as one
    /// scale, and they are not on one scale.
    struct Figure: Equatable, Sendable {
        public var text: String
        public var attribution: String
    }

    /// `nil` when the row carries neither figure — **never a zero**.
    ///
    /// A rendered `0` claims the number was measured and found to be none. For an official-only row
    /// there is no usage figure in existence to be zero; for a row enrichment never reached there
    /// is a star count that simply was not fetched.
    static func figure(for entry: RegistryEntry) -> Figure? {
        if let uses = entry.useCount {
            return Figure(
                text: "\(decimal(uses)) \(uses == 1 ? "session" : "sessions")",
                attribution: "sessions started, as counted by Smithery"
            )
        }
        if let stars = entry.stars {
            return Figure(
                text: "\(decimal(stars)) \(stars == 1 ? "star" : "stars")",
                attribution: "stars on GitHub"
            )
        }
        return nil
    }

    static func decimal(_ value: Int) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    // MARK: - Sanitising third-party text

    /// Strips what a hostile index entry would use to make text lie about itself.
    ///
    /// Every string on this board — `displayName`, `name`, `description`, and every element of an
    /// install command — is chosen by whoever published the entry, and this is the surface where a
    /// user decides whether to run their code. Two classes are removed:
    ///
    /// - **Bidirectional overrides and isolates** (U+202A–U+202E, U+2066–U+2069). A right-to-left
    ///   override inside a `displayName` renders `evil-server` as `revres-live`, which is a spoof
    ///   of the one field the user reads to identify what they are installing.
    /// - **C0 and C1 controls**, newline and tab included. A newline inside `args` lets an entry
    ///   inject extra lines into the block the capability statement offers as ground truth — text
    ///   that appears to be the app speaking.
    ///
    /// Applied at the boundary, so no view can forget it.
    static func sanitized(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { scalar in
            if (0x202A ... 0x202E).contains(scalar.value) { return false }
            if (0x2066 ... 0x2069).contains(scalar.value) { return false }
            // C0 (including \n and \t), DEL, and C1.
            if scalar.value < 0x20 || scalar.value == 0x7F { return false }
            if (0x80 ... 0x9F).contains(scalar.value) { return false }
            return true
        })
    }

    /// Sanitised, and capped so one entry cannot push everything else off the surface.
    ///
    /// The cap is not a layout nicety: `description` is unbounded on the wire, and a megabyte of
    /// text in a sheet is a denial of the sheet.
    static func sanitized(_ raw: String, cap: Int) -> String {
        let clean = sanitized(raw)
        guard clean.count > cap else { return clean }
        return String(clean.prefix(cap)) + "…"
    }

    // MARK: - Artwork

    /// This board never loads a remote image, and the reason is the product's own boundary.
    ///
    /// `iconUrl` is a URL chosen by a third-party index. Fetching it would (a) make the Mac app
    /// open a connection to a host of an attacker's choosing, disclosing the user's address once
    /// per row, and (b) violate the standing constraint that the app talks to the router **only**
    /// over the loopback control API — an outbound fetch to `api.smithery.ai` is a second channel,
    /// which is the one thing that boundary exists to forbid.
    ///
    /// So every row draws the authored monogram plate (`DESIGN.md` §4's provision for an entry
    /// whose marketplace ships no art), and no gradient rectangle stands anywhere. Serving the real
    /// artwork means proxying it through the router, which is a router-side item.
    static let remoteArtworkRefusal = """
    Artwork is drawn locally. This app fetches nothing from the registries directly — it talks only \
    to the router on this Mac.
    """

    /// The one or two letters on the monogram plate, from the name the entry gave.
    static func monogram(for entry: RegistryEntry) -> String {
        let clean = sanitized(entry.displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = clean.split(separator: " ", omittingEmptySubsequences: true)
        if let first = words.first, let initial = first.first {
            if words.count > 1, let second = words.dropFirst().first?.first {
                return "\(initial)\(second)".uppercased()
            }
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}
