import Foundation
import Testing
@testable import MCPRouterKit

/// The block parser: every kind the mock draws, and the boundaries a marketplace document reaches.
@Suite("The Markdown block parser — M19")
struct MarkdownParserTests {
    private func kinds(_ source: String) -> [MarkdownBlock.Kind] {
        MarkdownParser.blocks(from: source).map(\.kind)
    }

    // MARK: - The kinds the mock draws

    @Test("headings parse at levels one to three")
    func headings() {
        #expect(kinds("# a\n\n## b\n\n### c") == [.heading1, .heading2, .heading3])
    }

    /// `DESIGN.md`'s ladder has three heading roles above body and the mock draws exactly those
    /// three, so a fourth level has nothing to render at. It stays visible as its own text rather
    /// than being invented a size or dropped — `spec-M19.md` §2's first assumption.
    @Test("a fourth heading level stays visible as text rather than being drawn or dropped")
    func fourthLevelFallsBackVisibly() throws {
        let blocks = MarkdownParser.blocks(from: "#### deeper")
        #expect(blocks.map(\.kind) == [.paragraph])
        guard case let .paragraph(inline) = try #require(blocks.first) else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(inline.text == "#### deeper")
    }

    @Test("a hash with no space is not a heading")
    func hashtagIsNotAHeading() {
        #expect(kinds("#hashtag") == [.paragraph])
    }

    @Test("a fence keeps its language and its body verbatim")
    func fence() throws {
        let blocks = MarkdownParser.blocks(from: "```bash\ntrawl --export a.md\n  indented\n```")
        guard case let .codeFence(language, code) = try #require(blocks.first) else {
            Issue.record("expected a fence")
            return
        }
        #expect(language == "bash")
        #expect(code == "trawl --export a.md\n  indented")
    }

    /// Every renderer does this and the alternative is guessing where the author meant to stop.
    /// What must not happen is losing the text, and it does not.
    @Test("an unclosed fence runs to the end of the document rather than losing its text")
    func unclosedFence() throws {
        let blocks = MarkdownParser.blocks(from: "```\nline one\nline two")
        guard case let .codeFence(_, code) = try #require(blocks.first) else {
            Issue.record("expected a fence")
            return
        }
        #expect(blocks.count == 1)
        #expect(code == "line one\nline two")
    }

    @Test("a quote parses its own contents as blocks")
    func quote() throws {
        let blocks = MarkdownParser.blocks(from: "> ## inside\n> and a line")
        guard case let .blockquote(inner) = try #require(blocks.first) else {
            Issue.record("expected a quote")
            return
        }
        #expect(inner.map(\.kind) == [.heading2, .paragraph])
    }

    @Test("both list kinds parse, and an ordered list counts from its own first marker")
    func lists() {
        let blocks = MarkdownParser.blocks(from: "- one\n- two\n\n3. three\n4. four")
        #expect(blocks.map(\.kind) == [.unorderedList, .orderedList])
        guard case let .list(ordered) = blocks[1] else {
            Issue.record("expected an ordered list")
            return
        }
        #expect(ordered.start == 3)
        #expect(ordered.items.map(\.text) == ["three", "four"])
    }

    /// A changelog heading reads `1.4.2 — 17 Aug 2026`, and a list marker that did not require the
    /// space would turn every version number at the start of a line into a numbered item.
    @Test("a version number is not a list marker")
    func versionIsNotAList() {
        #expect(kinds("1.4.2 shipped on Tuesday") == [.paragraph])
    }

    @Test("an indented continuation joins its item rather than being dropped")
    func continuation() throws {
        let blocks = MarkdownParser.blocks(from: "- one\n  - nested\n- two")
        guard case let .list(list) = try #require(blocks.first) else {
            Issue.record("expected a list")
            return
        }
        #expect(list.items.count == 2)
        #expect(list.items[0].text == "one - nested")
    }

    @Test("three dashes, asterisks or underscores are a rule")
    func rules() {
        #expect(kinds("---\n\n***\n\n___") == [.rule, .rule, .rule])
    }

    @Test("a table parses its header, alignments and rows")
    func table() throws {
        let source = """
        | Harness | Store | Format |
        |---|:---:|---:|
        | Claude Code | `~/.claude` | JSON Lines |
        """
        guard case let .table(table) = try #require(MarkdownParser.blocks(from: source).first) else {
            Issue.record("expected a table")
            return
        }
        #expect(table.header.map(\.text) == ["Harness", "Store", "Format"])
        #expect(table.alignments == [.leading, .center, .trailing])
        #expect(table.rows.count == 1)
        #expect(table.rows[0].map(\.text) == ["Claude Code", "~/.claude", "JSON Lines"])
    }

    /// A line with a pipe in it is prose, and rendering prose in a grid is what happens when the
    /// delimiter row is not required.
    @Test("a line containing a pipe is not a table")
    func pipeIsNotATable() {
        #expect(kinds("a | b, which is prose") == [.paragraph])
    }

    /// A ragged table is exactly what a marketplace document produces, and a view that indexed a
    /// short row would crash on a document the reader did not write.
    @Test("a ragged table is padded and truncated to its header's width")
    func raggedTable() throws {
        let source = """
        | a | b | c |
        |---|---|---|
        | 1 |
        | 1 | 2 | 3 | 4 |
        """
        guard case let .table(table) = try #require(MarkdownParser.blocks(from: source).first) else {
            Issue.record("expected a table")
            return
        }
        #expect(table.rows.allSatisfy { $0.count == 3 })
        #expect(table.rows[0].map(\.text) == ["1", "", ""])
        #expect(table.rows[1].map(\.text) == ["1", "2", "3"])
    }

    @Test("an escaped pipe stays inside its cell")
    func escapedPipe() {
        #expect(MarkdownParser.tableCells("| a \\| b | c |") == ["a | b", "c"])
    }

    // MARK: - Images and shields

    @Test("a paragraph that is only shields becomes one shield row")
    func shieldRow() throws {
        let source = "![m](https://img.shields.io/badge/marketplace-fledgeling-blue) "
            + "![c](https://img.shields.io/badge/checks-12%20of%2012-brightgreen)"
        guard case let .shields(shields) = try #require(MarkdownParser.blocks(from: source).first) else {
            Issue.record("expected a shield row")
            return
        }
        #expect(shields.map(\.key) == ["marketplace", "checks"])
        #expect(shields.map(\.tone) == [.neutral, .good])
    }

    @Test("a paragraph that is only a non-shield image becomes an image block")
    func imageBlock() throws {
        guard case let .image(image) = try #require(
            MarkdownParser.blocks(from: "![Matches per week](docs/matches.png)").first
        ) else {
            Issue.record("expected an image")
            return
        }
        #expect(image.alternateText == "Matches per week")
        #expect(image.reference == "docs/matches.png")
    }

    /// The distinction the block/inline split turns on: a sentence with an image in it keeps its
    /// prose, and only a run that is nothing but images becomes a block of its own.
    @Test("an image inside a sentence leaves the sentence a paragraph")
    func imageInsideProse() {
        #expect(kinds("See ![the chart](docs/a.png) for the shape.") == [.paragraph])
    }

    @Test("a reference containing balanced parentheses survives the scan")
    func parenthesesInReference() {
        let images = MarkdownParser.inlineImages(in: "![a](docs/chart_(2026).png)")
        #expect(images.map(\.reference) == ["docs/chart_(2026).png"])
    }

    // MARK: - Bounds

    /// Not a security boundary — nothing here executes — but a denial of the surface is still a way
    /// for a document to make the app useless, and the reader is told rather than quietly cut.
    @Test("a document past the block cap is truncated and says so")
    func blockCap() throws {
        let source = (1 ... 40).map { "para \($0)" }.joined(separator: "\n\n")
        let blocks = MarkdownParser.blocks(from: source, limits: MarkdownLimits(blocks: 5))
        #expect(blocks.count == 6)
        guard case let .paragraph(last) = try #require(blocks.last) else {
            Issue.record("expected a closing paragraph")
            return
        }
        #expect(last.text.contains("not rendered"))
    }

    @Test("a line past the length cap is truncated rather than held whole")
    func lineCap() throws {
        let blocks = MarkdownParser.blocks(
            from: String(repeating: "x", count: 500),
            limits: MarkdownLimits(lineLength: 100)
        )
        guard case let .paragraph(inline) = try #require(blocks.first) else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(inline.text.count == 100)
    }

    @Test("an empty document produces no blocks rather than one empty one")
    func emptyDocument() {
        #expect(MarkdownParser.blocks(from: "").isEmpty)
        #expect(MarkdownParser.blocks(from: "\n\n   \n").isEmpty)
    }
}
