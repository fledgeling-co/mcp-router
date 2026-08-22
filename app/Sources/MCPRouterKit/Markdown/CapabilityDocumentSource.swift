import Foundation

/// Where a capability's documentation comes from.
///
/// **There is no production implementation, and the protocol exists to say so honestly.** Measured
/// on 2026-08-22: the control API admits `/servers`, `/usage` and `/registry` (`src/control.ts`
/// `:279-283`) and nothing else, and no wire type — `RegistryEntry`, `Skill`, `PluginOrigin` —
/// carries a read me, a changelog, a licence or a capability table. So the router observes no
/// document, `DESIGN.md` §6 forbids displaying what it does not observe, and the panel this item
/// builds has a fixture behind it and a stated absence behind that.
///
/// `Unavailable` is the production arm. It is not a stub waiting to be filled in: it is the honest
/// answer to "what does this app know about that capability's read me", and it stays the answer
/// until something serves one. `planning/features-to-triage/M29-capability-document-source.md`
/// is where that is owned.
public protocol CapabilityDocumentSource: Sendable {
    /// The document for one capability, by the name the router identifies it under.
    func document(for name: String) async throws(CapabilityDocumentError) -> CapabilityDocument
}

/// Why a document could not be produced.
///
/// Split into headline and advice for the reason `ControlAPIError` is: `DESIGN.md` §6 asks for one
/// wording per state, and a surface that paraphrases gives the product two.
public enum CapabilityDocumentError: Error, Equatable, Sendable {
    /// Nothing this app can reach serves documentation. Not a failure of this request — the
    /// capability does not exist as far as documents are concerned.
    case notServed
    /// The source could be asked and does not hold one for this capability.
    case notFound(capability: String)

    public var headline: String {
        switch self {
        case .notServed: "Documentation isn't available in the app yet"
        case let .notFound(capability): "Nothing is published for \(capability)"
        }
    }

    /// What is true and what can be done, with no invented next step where there is none.
    public var advice: String {
        switch self {
        case .notServed:
            """
            The router doesn't read a capability's read me, changelog or capability list, \
            so there is nothing here to show. Its repository link still opens in a browser.
            """
        case .notFound:
            """
            The package this came from carries no documentation files. \
            Its repository link still opens in a browser.
            """
        }
    }
}

/// The production arm: this app cannot reach a document, and says which.
///
/// A type rather than a `nil` source, so the panel renders a designed state with real copy rather
/// than a caller deciding per site what an absent source means (`DESIGN.md` §5).
public struct UnavailableCapabilityDocumentSource: CapabilityDocumentSource {
    public init() {}

    public func document(for _: String) async throws(CapabilityDocumentError) -> CapabilityDocument {
        throw .notServed
    }
}
