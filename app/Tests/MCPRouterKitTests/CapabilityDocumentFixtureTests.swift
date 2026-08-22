import Foundation
import Testing
@testable import MCPRouterKit

/// The brief's acceptance line, as an assertion: *a fixture README containing every block kind in
/// the mock renders with no block falling back to raw text.*
///
/// The kind list is `design/mcp-router-console.html`'s `sh-readme` sheet read off the mock, not a
/// list composed here — the mock's document body draws a shield row, `h1`, `h2`, `h3`, paragraphs,
/// a blockquote, a table, a fence, an unordered list, an ordered list, a figure and a rule, and
/// each of those is one row below.
@Suite("The fixture capability document — M19's acceptance")
struct CapabilityDocumentFixtureTests {
    private func document() throws -> CapabilityDocument {
        try #require(
            FixtureCapabilityDocumentSource.build(),
            "the fixture package is not in the resource bundle"
        )
    }

    /// The kinds the mock's `sh-readme` body draws, in the order it draws them.
    static let kindsTheMockDraws: [MarkdownBlock.Kind] = [
        .shields, .heading1, .paragraph, .blockquote, .heading2, .table,
        .heading2, .codeFence, .heading3, .unorderedList, .heading2, .orderedList,
        .image, .rule, .paragraph
    ]

    @Test("the read me carries every block kind the mock draws")
    func everyKindIsCovered() throws {
        let blocks = try #require(document().blocks(for: .readMe))
        let present = Set(blocks.map(\.kind))
        for kind in Set(Self.kindsTheMockDraws) {
            #expect(present.contains(kind), "the fixture draws no \(kind.rawValue)")
        }
    }

    /// The other half of the same line, and the half that keeps `plainText` from becoming a way to
    /// not build something: nothing in the fixture falls back.
    @Test("no block in any tab falls back to raw text")
    func nothingFallsBack() throws {
        let document = try document()
        for tab in CapabilityDocument.Tab.allCases {
            let blocks = try #require(document.blocks(for: tab), "\(tab.rawValue) is not published")
            let fallbacks = blocks.filter { $0.kind == .plainText }
            #expect(fallbacks.isEmpty, "\(tab.rawValue) fell back \(fallbacks.count) times")
        }
    }

    @Test("all three tabs are published, and the mock's five facts are carried")
    func tabsAndFacts() throws {
        let document = try document()
        #expect(document.publishedTabs == CapabilityDocument.Tab.allCases)
        #expect(document.facts.map(\.label) == ["Kind", "Version", "Licence", "Runs in", "Reads"])
    }

    /// The four badges the mock's readme sheet opens with, and the tone each takes. `version` and
    /// `checks` are the two the mock marks `good`.
    @Test("the shield row matches the mock's four badges and their two tones")
    func shieldRow() throws {
        let blocks = try #require(document().blocks(for: .readMe))
        guard case let .shields(shields) = try #require(blocks.first) else {
            Issue.record("the read me does not open with a shield row")
            return
        }
        #expect(shields.map(\.key) == ["marketplace", "version", "checks", "licence"])
        #expect(shields.map(\.value) == ["fledgeling", "1.4.2", "12 of 12", "MIT"])
        #expect(shields.map(\.tone) == [.neutral, .good, .good, .neutral])
    }

    /// The reason the fixture is a directory of real files rather than a Swift string: it makes
    /// "images resolve from inside the downloaded package" a path that runs.
    @Test("the package's own image resolves to bytes and no image is refused")
    func imageResolvesFromThePackage() throws {
        let document = try document()
        let png = try #require(document.images["docs/matches.png"])
        #expect(png.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
        #expect(document.refusedImages.isEmpty)
    }

    @Test("the source answers for trawl and refuses a name it does not hold")
    func sourceAnswersByName() async throws {
        let source = FixtureCapabilityDocumentSource()
        let document = try await source.document(for: "trawl")
        #expect(document.identity.name == "trawl")

        await #expect(throws: CapabilityDocumentError.notFound(capability: "nope")) {
            try await source.document(for: "nope")
        }
    }

    /// The production arm is not a stub waiting to be filled in — it is the honest answer while
    /// nothing serves a document, and its copy says what is true with no invented next step.
    @Test("the production source reports that nothing serves a document")
    func productionSourceIsUnavailable() async {
        await #expect(throws: CapabilityDocumentError.notServed) {
            try await UnavailableCapabilityDocumentSource().document(for: "trawl")
        }
        #expect(CapabilityDocumentError.notServed.advice.contains("The router doesn't read"))
    }
}
