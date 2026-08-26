import Foundation
import Testing
@testable import MCPRouterKit

/// `ControlAPICapabilityDocumentSource` — the second implementation of `CapabilityDocumentSource`.
///
/// The mapping is tested through the static `document(from:)` rather than through a client, because
/// a mapping only reachable by a network call is one nothing checks: every refusal reason, every tab
/// key and every absent field has to land somewhere, and this is where that is asserted.
@Suite("M30 · the control-API document source")
struct ControlAPIDocumentSourceTests {
    private static func payload(
        documents: [String: String] = ["readMe": "# a\n\nb"],
        facts: [CapabilityDocumentPayload.Fact] = [],
        images: [CapabilityDocumentPayload.Image] = [],
        refused: [CapabilityDocumentPayload.RefusedImage] = []
    ) -> CapabilityDocumentPayload {
        CapabilityDocumentPayload(
            server: "pkg", facts: facts, documents: documents,
            images: images, refusedImages: refused
        )
    }

    @Test("a tab the package did not publish is absent, not empty")
    func absentTabsStayAbsent() {
        let document = ControlAPICapabilityDocumentSource.document(
            from: Self.payload(documents: ["readMe": "# a", "capabilities": "# c"])
        )
        #expect(document.blocks(for: .readMe) != nil)
        #expect(document.blocks(for: .capabilities) != nil)
        // Nil rather than `[]`. The panel says *which* document is missing, and it cannot tell an
        // unpublished changelog from an empty one if both arrive as an empty array.
        #expect(document.blocks(for: .changelog) == nil)
        #expect(document.publishedTabs == [.readMe, .capabilities])
    }

    @Test("the facts are the router's, in the router's order, with nothing added")
    func factsPassThrough() {
        let document = ControlAPICapabilityDocumentSource.document(
            from: Self.payload(facts: [
                .init(label: "Kind", value: "stdio"), .init(label: "Tools", value: "17")
            ])
        )
        #expect(document.facts.map(\.label) == ["Kind", "Tools"])
        #expect(document.facts.map(\.value) == ["stdio", "17"])
        // No publisher and no pitch: the router observes neither for an installed upstream, and
        // this source does not invent them. The header omits the rows rather than drawing blanks.
        #expect(document.identity.publisher == nil)
        #expect(document.identity.pitch == nil)
        #expect(document.identity.name == "pkg")
    }

    @Test("an image arrives as bytes and nothing downstream holds a path")
    func imagesDecode() {
        let document = ControlAPICapabilityDocumentSource.document(
            from: Self.payload(images: [
                .init(reference: "docs/a.png", media: "image/png", base64: "QUFBQQ==")
            ])
        )
        #expect(document.images["docs/a.png"] == Data("AAAA".utf8))
        #expect(document.refusedImages.isEmpty)
    }

    @Test("an undecodable image body becomes a refusal rather than a silent omission")
    func undecodableImageIsRefused() {
        let document = ControlAPICapabilityDocumentSource.document(
            from: Self.payload(images: [
                .init(reference: "docs/a.png", media: "image/png", base64: "not base64 at all!!")
            ])
        )
        #expect(document.images.isEmpty)
        #expect(
            document.refusedImages["docs/a.png"]
                == .unrecognised(reason: "the image body was not readable")
        )
    }

    @Test("every refusal reason the route can send maps to its own placeholder")
    func everyRefusalReasonMaps() {
        let cases: [(CapabilityDocumentPayload.RefusedImage, PackageImageResolver.Refusal)] = [
            (.init(reference: "a", reason: "remote", scheme: "https"), .remote(scheme: "https")),
            (.init(reference: "b", reason: "absolutePath"), .absolutePath),
            (.init(reference: "c", reason: "escapesPackage"), .escapesPackage),
            (.init(reference: "d", reason: "notInPackage"), .notInPackage),
            (
                .init(reference: "e", reason: "unsupportedType", extension: ".svg"),
                .unsupportedType(extension: ".svg")
            ),
            (.init(reference: "f", reason: "tooLarge", limit: 2_097_152), .tooLarge(limitBytes: 2_097_152)),
            (.init(reference: "g", reason: "budgetExhausted"), .budgetExhausted),
            // A router newer than this app. Kept with its own word rather than folded into one of
            // the known cases, which would be this app reporting a finding it did not make.
            (.init(reference: "h", reason: "somethingNewer"), .unrecognised(reason: "somethingNewer"))
        ]
        for (wire, expected) in cases {
            #expect(
                ControlAPICapabilityDocumentSource.refusal(from: wire) == expected,
                "\(wire.reason)"
            )
        }
        // Every placeholder says what happened. An empty sentence would draw a blank grey box.
        for (_, refusal) in cases {
            #expect(refusal.sentence.hasPrefix("Not shown — "), "\(refusal)")
        }
    }

    @Test("each request refusal maps to its own error, and each error says which rule it hit")
    func requestRefusalsMap() {
        #expect(
            ControlAPICapabilityDocumentSource.error(
                from: .init(error: "e", reason: "noPackageDirectory"), capability: "pkg"
            ) == .noPackageDirectory(capability: "pkg")
        )
        #expect(
            ControlAPICapabilityDocumentSource.error(
                from: .init(error: "e", reason: "packageUnreadable"), capability: "pkg"
            ) == .packageUnreadable(capability: "pkg")
        )
        #expect(
            ControlAPICapabilityDocumentSource.error(
                from: .init(error: "e", reason: "noDocuments"), capability: "pkg"
            ) == .notFound(capability: "pkg")
        )
        let tooLarge = ControlAPICapabilityDocumentSource.error(
            from: .init(
                error: "e", reason: "documentTooLarge", cap: "documentBytes",
                limit: 524_288, actual: 600_000, file: "README.md"
            ),
            capability: "pkg"
        )
        #expect(tooLarge == .tooLarge(file: "README.md", capBytes: 524_288))
        // The cap is in the copy, which is the whole point of carrying it: "too large" alone tells
        // a reader nothing they can act on, and `MarkdownLimits` is a different cap entirely.
        #expect(tooLarge.advice.contains("512 KB"))
        #expect(tooLarge.headline.contains("README.md"))
    }

    @Test("the default conformance still answers notServed, so the honest absence stays reachable")
    func defaultConformanceIsStillNotServed() async throws {
        struct Bare: CapabilityDocumentSource {
            func document(for _: String) async throws(CapabilityDocumentError) -> CapabilityDocument {
                throw .notServed
            }
        }
        await #expect(throws: CapabilityDocumentError.notServed) {
            _ = try await Bare().document(for: "anything")
        }
        // And through the client protocol's own default, which is what a conformer with no opinion
        // about this route answers — a surface with nothing to ask is not a router that answered.
        await #expect(throws: CapabilityDocumentError.notServed) {
            _ = try await FixtureControlAPIClient().capabilityDocument(for: "anything")
        }
    }
}
