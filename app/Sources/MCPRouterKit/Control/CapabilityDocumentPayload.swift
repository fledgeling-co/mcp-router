import Foundation

/// What `GET /servers/:name/document` sends.
///
/// A wire type, and it carries **no path**. The router resolves every image reference against the
/// package and sends the bytes it read, so nothing here can be opened, and `A36`'s rule — the app
/// talks to the router over the loopback control API and nothing else — has nothing to lean on but
/// this shape. `spec-M30.md` §3 is the contract.
public struct CapabilityDocumentPayload: Codable, Hashable, Sendable {
    /// One cell of the facts strip, exactly as the router observed it.
    public struct Fact: Codable, Hashable, Sendable {
        public var label: String
        public var value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    /// One image the router read, as bytes.
    public struct Image: Codable, Hashable, Sendable {
        public var reference: String
        public var media: String
        public var base64: String

        public init(reference: String, media: String, base64: String) {
            self.reference = reference
            self.media = media
            self.base64 = base64
        }
    }

    /// One image the router would not read, and why.
    ///
    /// The payload beside `reason` differs by reason — a scheme, an extension, a byte limit — so
    /// each is optional and each is read only by the case that carries it. A reason this version
    /// does not recognise is kept rather than dropped: the reader still learns the document pointed
    /// somewhere the router would not go, which is the thing worth knowing.
    public struct RefusedImage: Codable, Hashable, Sendable {
        public var reference: String
        public var reason: String
        public var scheme: String?
        /// Backticked rather than renamed with a `CodingKeys` map: the wire member is `extension`,
        /// and a nested coding-key enum here is a second level of nesting the linter refuses. The
        /// keyword spelling keeps the synthesised key equal to the wire's without a mapping to
        /// keep in step.
        public var `extension`: String?
        public var limit: Int?

        public init(
            reference: String,
            reason: String,
            scheme: String? = nil,
            extension: String? = nil,
            limit: Int? = nil
        ) {
            self.reference = reference
            self.reason = reason
            self.scheme = scheme
            self.extension = `extension`
            self.limit = limit
        }
    }

    public var server: String
    public var facts: [Fact]
    /// Keyed by the tab's own name — `readMe`, `changelog`, `capabilities`. A key that is absent
    /// means the package published no such file, which is different from an empty one.
    public var documents: [String: String]
    public var images: [Image]
    public var refusedImages: [RefusedImage]

    public init(
        server: String,
        facts: [Fact] = [],
        documents: [String: String] = [:],
        images: [Image] = [],
        refusedImages: [RefusedImage] = []
    ) {
        self.server = server
        self.facts = facts
        self.documents = documents
        self.images = images
        self.refusedImages = refusedImages
    }
}

/// A refusal body from the document route.
///
/// `reason` is what distinguishes this route's own 404 from the 404 an older router answers for a
/// path it has never heard of. A 404 with no `reason` is version skew and takes the wording
/// `LiveControlAPIClient+Absent.swift` already carries for that state.
public struct CapabilityDocumentRefusal: Codable, Hashable, Sendable {
    public var error: String
    public var reason: String
    public var cap: String?
    public var limit: Int?
    public var actual: Int?
    public var file: String?

    public init(
        error: String,
        reason: String,
        cap: String? = nil,
        limit: Int? = nil,
        actual: Int? = nil,
        file: String? = nil
    ) {
        self.error = error
        self.reason = reason
        self.cap = cap
        self.limit = limit
        self.actual = actual
        self.file = file
    }
}
