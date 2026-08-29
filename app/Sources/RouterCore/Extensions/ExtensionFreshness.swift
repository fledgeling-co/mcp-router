import Foundation

/// What comparing one installed entry against one catalogue produced.
///
/// Eight cases, and only the first means an update. The seven others exist because the mechanism
/// the brief names — *version deltas on installed tools* — answers `updateAvailable` **zero times
/// out of 127** on the machine this product runs on, and answers it backwards once. Measured
/// 2026-08-29 by `planning/evidence/F6/measure-update-surface.py`: 105 equal, 10 offered with no
/// version, 10 no longer offered at all, 1 whose marketplace directory is gone, and **1 where the
/// catalogue is older than what is installed** (held 2.0.0, offered 1.0.0).
///
/// That last row is the reason this is an enum with a direction rather than a `Bool`. A checker
/// that read a difference as an update would have offered a downgrade, described as an update, with
/// nothing in the reply able to tell the reader which it was.
public enum FreshnessVerdict: Sendable, Hashable {
    /// The one state that costs an install. Both versions parsed, and the catalogue's is greater.
    case updateAvailable(installed: String, available: String)
    /// Both sides declare the same version.
    case current(String)
    /// The catalogue offers an **older** version than the one installed. A fact about the
    /// catalogue, never an update, and it is on the wire as its own state so a caller cannot mistake
    /// it for one.
    case catalogueBehind(installed: String, available: String)
    /// Both sides declare a version, they differ, and at least one cannot be ordered — a git short
    /// SHA is the measured case. *Differs* is knowable and *behind* is not.
    case unorderable(installed: String, available: String)
    /// The entry's own descriptor declares no version. 10 of the 22 readable skills on this machine.
    case installedDeclaresNoVersion
    /// The catalogue names the entry and declares no version for it. 557 of 763 offers.
    case catalogueDeclaresNoVersion(installed: String?)
    /// The catalogue was read and does not name this entry.
    case notOffered
    /// There is no catalogue to compare against, and why.
    case noCatalogue(String)

    /// True for `updateAvailable` and nothing else.
    public var hasUpdate: Bool {
        if case .updateAvailable = self { return true }
        return false
    }

    /// Whether two versions were actually put side by side.
    ///
    /// This is what lets a report say *four of 127 could not be compared* rather than *four are up
    /// to date*. A count of zero updates produced by comparing everything and a count of zero
    /// produced by comparing nothing are different answers, and only one of them is a measurement
    /// (`DESIGN.md` §6).
    public var isComparison: Bool {
        switch self {
        case .updateAvailable, .current, .catalogueBehind, .unorderable: true
        case .installedDeclaresNoVersion, .catalogueDeclaresNoVersion, .notOffered, .noCatalogue:
            false
        }
    }

    /// The slug a caller branches on.
    public var state: String {
        switch self {
        case .updateAvailable: "update-available"
        case .current: "current"
        case .catalogueBehind: "catalogue-behind"
        case .unorderable: "unorderable"
        case .installedDeclaresNoVersion: "installed-declares-no-version"
        case .catalogueDeclaresNoVersion: "catalogue-declares-no-version"
        case .notOffered: "not-offered"
        case .noCatalogue: "no-catalogue"
        }
    }

    /// The version the entry itself declares, or `nil`.
    public var installedVersion: String? {
        switch self {
        case let .updateAvailable(installed, _): installed
        case let .current(version): version
        case let .catalogueBehind(installed, _): installed
        case let .unorderable(installed, _): installed
        case let .catalogueDeclaresNoVersion(installed): installed
        case .installedDeclaresNoVersion, .notOffered, .noCatalogue: nil
        }
    }

    /// The version the catalogue offers, or `nil`.
    public var availableVersion: String? {
        switch self {
        case let .updateAvailable(_, available): available
        case let .current(version): version
        case let .catalogueBehind(_, available): available
        case let .unorderable(_, available): available
        case .installedDeclaresNoVersion, .catalogueDeclaresNoVersion, .notOffered, .noCatalogue:
            nil
        }
    }

    /// What a person reads. It names the versions rather than saying that something was wrong.
    public var sentence: String {
        switch self {
        case let .updateAvailable(installed, available):
            "\(available) is offered and \(installed) is installed"
        case let .current(version):
            "\(version) is installed and is what the catalogue offers"
        case let .catalogueBehind(installed, available):
            "the catalogue offers \(available) and \(installed) is installed, "
                + "so this copy of the catalogue is behind rather than the install"
        case let .unorderable(installed, available):
            "\(installed) and \(available) differ and neither pair is orderable, "
                + "so which is newer cannot be said"
        case .installedDeclaresNoVersion:
            "this entry's descriptor declares no version, so there is nothing to compare"
        case .catalogueDeclaresNoVersion:
            "the catalogue names this entry and declares no version for it"
        case .notOffered:
            "the catalogue was read and does not offer this entry"
        case let .noCatalogue(reason):
            reason
        }
    }
}

/// Comparing one installed entry against one catalogue.
public enum ExtensionFreshness {
    /// The order of the guards is the design.
    ///
    /// Rows 3 and 4 come **before** the equality check deliberately: two absent versions are not
    /// two equal versions, and `nil == nil` would report 557 uncomparable offers as up to date.
    public static func compare(
        installedVersion: String?, offer: CatalogueOffer?, catalogueProblem: String?
    ) -> FreshnessVerdict {
        if let catalogueProblem { return .noCatalogue(catalogueProblem) }
        guard let offer else { return .notOffered }
        guard let available = offer.version else {
            return .catalogueDeclaresNoVersion(installed: installedVersion)
        }
        guard let installed = installedVersion else { return .installedDeclaresNoVersion }
        if installed == available { return .current(installed) }
        switch SemanticVersion.compare(installed, available) {
        case .orderedAscending:
            return .updateAvailable(installed: installed, available: available)
        case .orderedDescending:
            return .catalogueBehind(installed: installed, available: available)
        case .orderedSame:
            // Two spellings of one version — `1.0.0` and `v1.0.0`. Neither side is behind.
            return .current(installed)
        case nil:
            return .unorderable(installed: installed, available: available)
        }
    }
}
