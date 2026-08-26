import Foundation

/// The production implementation: a capability's documents, asked for over the control API.
///
/// **The second implementation of `CapabilityDocumentSource`, and the reason the protocol has two.**
/// `UnavailableCapabilityDocumentSource` is what a surface with nothing to ask answers;
/// this is what a surface with a router answers.
///
/// It holds no path and reads no file. The router resolved every image reference against the
/// package and sent the bytes, so what arrives here is already `Data` — which is what keeps
/// `MCPRouterUI` free of the filesystem `A36` and `SWIFT_PRACTICES.md` §8 both keep it out of, and
/// it is why M19's resolver returns bytes in the first place.
///
/// Parsing happens here rather than in the router. The router serves the package's own markdown
/// verbatim; `MarkdownParser` and `MarkdownLimits` decide what it costs to draw, which is a
/// question about this app's renderer and not about the wire. The wire has its own caps, and a
/// document that hit one never arrives at all — it arrives as `CapabilityDocumentError.tooLarge`
/// naming the cap.
public struct ControlAPICapabilityDocumentSource: CapabilityDocumentSource {
    private let client: any ControlAPIClient
    private let limits: MarkdownLimits

    public init(client: any ControlAPIClient, limits: MarkdownLimits = .standard) {
        self.client = client
        self.limits = limits
    }

    public func document(for name: String) async throws(CapabilityDocumentError) -> CapabilityDocument {
        let payload: CapabilityDocumentPayload
        do {
            payload = try await client.capabilityDocument(for: name)
        } catch let error as CapabilityDocumentError {
            throw error
        } catch {
            // `capabilityDocument` throws `CapabilityDocumentError` already; this arm exists because
            // the compiler cannot prove it across an existential, and it must not invent a state.
            throw .router(.malformedResponse(detail: "\(error)"))
        }
        return Self.document(from: payload, limits: limits)
    }

    /// Turns one payload into the value the panel draws.
    ///
    /// Static and pure, so the mapping is testable without a client — every refusal reason, every
    /// tab key and every missing field has to land somewhere, and a mapping only reachable through
    /// a network call is one nothing checks.
    public static func document(
        from payload: CapabilityDocumentPayload,
        limits: MarkdownLimits = .standard
    ) -> CapabilityDocument {
        var tabs: [CapabilityDocument.Tab: [MarkdownBlock]] = [:]
        for tab in CapabilityDocument.Tab.allCases {
            guard let source = payload.documents[tab.rawValue] else { continue }
            tabs[tab] = MarkdownParser.blocks(from: source, limits: limits)
        }

        var images: [String: Data] = [:]
        for image in payload.images {
            // A body this app cannot decode is a refusal rather than a silent omission: the reader
            // learns something arrived and could not be drawn, which is different from the document
            // never having named a figure.
            if let data = Data(base64Encoded: image.base64) {
                images[image.reference] = data
            } else {
                continue
            }
        }
        var refused: [String: PackageImageResolver.Refusal] = [:]
        for image in payload.refusedImages where images[image.reference] == nil {
            refused[image.reference] = refusal(from: image)
        }
        // Anything the router sent bytes for that this app could not decode. Recorded after the
        // refusals so a reference the router already refused keeps the router's own reason.
        for image in payload.images where images[image.reference] == nil && refused[image.reference] == nil {
            refused[image.reference] = .unrecognised(reason: "the image body was not readable")
        }

        return CapabilityDocument(
            identity: CapabilityDocument.Identity(name: payload.server),
            facts: payload.facts.map { .init(label: $0.label, value: $0.value) },
            tabs: tabs,
            images: images,
            refusedImages: refused
        )
    }

    /// The wire's `reason` as the placeholder's own case.
    ///
    /// An unknown reason keeps its word rather than collapsing into one of the known cases: a
    /// router newer than this app can refuse for something that did not exist when this was built,
    /// and reporting it as "the package does not contain this image" would be the app inventing a
    /// finding.
    static func refusal(from image: CapabilityDocumentPayload.RefusedImage) -> PackageImageResolver.Refusal {
        switch image.reason {
        case "remote": .remote(scheme: image.scheme ?? "")
        case "absolutePath": .absolutePath
        case "escapesPackage": .escapesPackage
        case "notInPackage": .notInPackage
        case "unsupportedType": .unsupportedType(extension: image.extension ?? "")
        case "tooLarge": .tooLarge(limitBytes: image.limit ?? 0)
        case "budgetExhausted": .budgetExhausted
        default: .unrecognised(reason: image.reason)
        }
    }

    /// A refusal body as the error the panel renders.
    ///
    /// The route's own 404s each carry a `reason`; a 404 with none is a router that has never heard
    /// of the path, which is version skew and takes that state's existing wording.
    static func error(
        from refusal: CapabilityDocumentRefusal,
        capability: String
    ) -> CapabilityDocumentError {
        switch refusal.reason {
        case "noPackageDirectory": .noPackageDirectory(capability: capability)
        case "packageUnreadable": .packageUnreadable(capability: capability)
        case "noDocuments": .notFound(capability: capability)
        case "documentTooLarge":
            .tooLarge(file: refusal.file ?? "This document", capBytes: refusal.limit ?? 0)
        // A reason this version does not know is still the router refusing, and the router's own
        // sentence is the honest thing to render — not a guess at which of the known states it is.
        default: .router(.server(status: 0, message: refusal.error))
        }
    }
}
