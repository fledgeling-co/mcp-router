import Foundation

/// One plugin a marketplace offers, as its own descriptor states it.
public struct CatalogueOffer: Sendable, Hashable {
    public let name: String
    /// `nil` when the catalogue names the plugin and declares no version for it. Measured on this
    /// machine on 2026-08-29: **557 of the 763 offers across ten catalogues are in this state**, so
    /// it is the ordinary case rather than a malformed one.
    public let version: String?

    public init(name: String, version: String?) {
        self.name = name
        self.version = version
    }
}

/// What a marketplace descriptor offers, read from its bytes.
///
/// `declaredNoVersion` is carried as a count rather than left to be derived, because a catalogue
/// that names 291 plugins and versions 14 of them must not read as a catalogue of 14 (`DESIGN.md`
/// §6). The largest catalogue on this machine is exactly that shape.
public struct MarketplaceCatalogue: Sendable {
    public let offers: [CatalogueOffer]
    public let declaredNoVersion: Int

    public init(offers: [CatalogueOffer]) {
        self.offers = offers
        declaredNoVersion = offers.count { $0.version == nil }
    }

    public func offer(named name: String) -> CatalogueOffer? {
        offers.first { $0.name == name }
    }

    /// `nil` when the text is not a marketplace descriptor at all.
    ///
    /// `JSONParser`, never `JSONSerialization` — the constraint every reader in this directory
    /// works under, enforced by `scripts/lint/no-wire-codable.sh`. An entry with no `name` is
    /// skipped rather than refusing the whole catalogue: one malformed offer among 291 must not
    /// take the other 290 with it, and a skipped offer surfaces as `notOffered` for the plugin that
    /// names it, which is a stated verdict rather than a silent absence.
    public static func read(text: String) -> MarketplaceCatalogue? {
        guard let parsed = try? JSONParser.parse(text), case .object = parsed else { return nil }
        guard let entries = parsed.member("plugins")?.asArray else { return nil }
        var offers: [CatalogueOffer] = []
        for entry in entries {
            guard let name = entry.member("name")?.asString?.string, !name.isEmpty else { continue }
            let version = entry.member("version")?.asString?.string
            offers.append(CatalogueOffer(
                name: name, version: (version?.isEmpty ?? true) ? nil : version
            ))
        }
        return MarketplaceCatalogue(offers: offers)
    }
}
