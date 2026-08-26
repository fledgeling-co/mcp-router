import Foundation

/// Where a capability's documentation comes from.
///
/// **Two implementations, and the difference between them is what can be asked rather than what is
/// known.** Measured on 2026-08-22, the control API admitted `/servers`, `/usage` and `/registry`
/// and nothing else, and no wire type carried a read me — so M19 shipped the panel over a fixture
/// and a stated absence. M30 added `GET /servers/:name/document` to both routers, which reads a
/// package out of the directory a server is declared with. What the router still does not observe
/// is absent rather than invented: `DESIGN.md` §6 forbids displaying a figure it does not observe,
/// and `spec-M30.md` answers the facts strip's five cells one at a time.
///
/// **M30 supplied the second implementation** — ``ControlAPICapabilityDocumentSource``, which asks
/// the router for a server's own package. `UnavailableCapabilityDocumentSource` is still the honest
/// answer wherever there is no control client to ask, and stays reachable and tested for that
/// reason: a surface with nothing to ask is not the same as a router that answered.
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
    /// The capability declares no directory, so there is no package to read documentation from.
    ///
    /// Distinct from ``notFound(capability:)`` because the remedies differ: a package with no
    /// documents is a publishing choice, and a server declared without a directory is a
    /// configuration this router cannot read a package out of at all.
    case noPackageDirectory(capability: String)
    /// A directory is declared and is not there any more.
    case packageUnreadable(capability: String)
    /// A document is larger than the transport will send, and the refusal names which cap.
    ///
    /// `MarkdownLimits` caps the parse, in this app, after the bytes have already crossed. This is
    /// the wire's own bound, and saying "too large" without naming the cap tells a reader nothing
    /// they could act on.
    case tooLarge(file: String, capBytes: Int)
    /// The router could not be asked. Carried rather than paraphrased, so the two surfaces do not
    /// end up with two wordings for one state (`DESIGN.md` §6).
    case router(ControlAPIError)

    public var headline: String {
        switch self {
        case .notServed: "Documentation isn't available in the app yet"
        case let .notFound(capability): "Nothing is published for \(capability)"
        case let .noPackageDirectory(capability): "\(capability) has no package to read"
        case let .packageUnreadable(capability): "\(capability)'s directory isn't there"
        case let .tooLarge(file, _): "\(file) is too large to show here"
        case let .router(error): error.headline
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
        case .noPackageDirectory:
            """
            This server is declared without a directory, so the router has no package to read \
            a read me out of. Its repository link still opens in a browser.
            """
        case .packageUnreadable:
            """
            The directory this server is declared with is no longer on this Mac, so there is \
            nothing left to read. Re-installing the package puts it back.
            """
        case let .tooLarge(_, capBytes):
            """
            The router sends at most \(capBytes / 1024) KB per document and this one is over it, \
            so nothing was sent rather than a shortened version of it. \
            Its repository link still opens in a browser.
            """
        case let .router(error):
            error.advice
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
