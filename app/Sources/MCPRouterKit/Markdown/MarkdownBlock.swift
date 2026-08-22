import Foundation

/// One block of a rendered document, after parsing and before drawing.
///
/// A typed block per kind, rather than one attributed string, because `AttributedString(markdown:)`
/// renders neither a table nor a fenced code block and both appear in every README this app will
/// show. The system parser keeps the inline runs — emphasis, code spans, links — and everything
/// structural is a case here with its own small view.
///
/// **`plainText` is the visible fallback and it is deliberate.** A construct outside this list
/// renders as its own source text rather than disappearing: a block that fell back is something a
/// reader can see and report, and a block that was dropped is not. `spec-M19.md` §2's first
/// assumption is that rule, and the brief's acceptance line — a fixture containing every kind the
/// mock draws parses with *no* block falling back — is what stops it becoming a way to not build
/// something.
public enum MarkdownBlock: Equatable, Sendable {
    /// A heading at level 1, 2 or 3. Four hashes or more is not a kind the mock draws, so it
    /// arrives here as `plainText`.
    case heading(level: Int, content: MarkdownInline)
    case paragraph(MarkdownInline)

    /// A fenced block. `language` is the info string, kept for the label and never used to select
    /// a highlighter — the mock draws a monospace ground and no colour.
    case codeFence(language: String?, code: String)

    /// A quote, holding its own blocks. Recursive rather than flattened to a string, because the
    /// mock's quotes are paragraphs today and a quoted list is one edit away in a document nobody
    /// here writes.
    case blockquote([MarkdownBlock])

    case list(MarkdownList)
    case table(MarkdownTable)
    case rule
    case image(MarkdownImage)

    /// A run of shields — the two-part badges that open almost every document of this kind. Their
    /// own case rather than a row of images, because they are re-drawn from what they say and
    /// never loaded.
    case shields([Shield])

    /// A construct this renderer does not draw, shown as the source wrote it.
    case plainText(String)

    /// The kind name used by the fidelity ledger and by the coverage assertion, so a test can say
    /// *every kind the mock draws is present* without pattern-matching each case at the call site.
    public var kind: Kind {
        switch self {
        case let .heading(level, _): level == 1 ? .heading1 : (level == 2 ? .heading2 : .heading3)
        case .paragraph: .paragraph
        case .codeFence: .codeFence
        case .blockquote: .blockquote
        case let .list(list): list.isOrdered ? .orderedList : .unorderedList
        case .table: .table
        case .rule: .rule
        case .image: .image
        case .shields: .shields
        case .plainText: .plainText
        }
    }

    public enum Kind: String, CaseIterable, Sendable {
        case heading1, heading2, heading3
        case paragraph, codeFence, blockquote
        case orderedList, unorderedList
        case table, rule, image, shields
        case plainText
    }
}

/// A bulleted or numbered list. One level: the mock draws no nesting, and a nested list arrives as
/// the parent item's own text rather than being dropped.
public struct MarkdownList: Equatable, Sendable {
    public var isOrdered: Bool
    /// Where a numbered list starts. Taken from the first marker, so `3.` counts from three.
    public var start: Int
    public var items: [MarkdownInline]

    public init(isOrdered: Bool, start: Int = 1, items: [MarkdownInline]) {
        self.isOrdered = isOrdered
        self.start = start
        self.items = items
    }
}

/// A GFM table: one header row, an alignment per column, and the body.
///
/// Rows are padded and truncated to the header's width at parse time, so a ragged table cannot
/// make the view index past the end of a row. A document arriving from a marketplace is exactly
/// where a ragged table comes from.
public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: String, Equatable, Sendable {
        case leading, center, trailing
    }

    public var header: [MarkdownInline]
    public var alignments: [Alignment]
    public var rows: [[MarkdownInline]]

    public init(header: [MarkdownInline], alignments: [Alignment], rows: [[MarkdownInline]]) {
        self.header = header
        self.alignments = alignments
        self.rows = rows
    }

    public var columnCount: Int { header.count }
}

/// An image the document points at, before anything has decided whether it may be shown.
///
/// The reference is kept **as written**. Resolving it is `PackageImageResolver`'s job and it
/// happens away from the view, so the type a view receives cannot be talked into a fetch by having
/// a URL on it.
public struct MarkdownImage: Equatable, Sendable {
    public var alternateText: String
    public var reference: String

    public init(alternateText: String, reference: String) {
        self.alternateText = alternateText
        self.reference = reference
    }
}
