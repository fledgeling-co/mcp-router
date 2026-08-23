import Foundation

/// The inline runs inside one block — emphasis, strong, code spans and links.
///
/// `AttributedString(markdown:)` does this part and does it well, which is the whole reason the
/// custom work here is only structural. What it does **not** do is decide what is safe to keep: the
/// parser will attach a `link` to any URL the document writes, `imageURL` to any image it names,
/// and whatever else a future toolchain adds to the same scope. A README arrives from a marketplace
/// into an app that rewrites other tools' configuration, so this type takes the parser's output and
/// keeps an explicit allowlist of attributes rather than dropping a denylist.
///
/// The allowlist is two entries:
///
/// - `inlinePresentationIntent`, which carries emphasis, strong and code and no destination.
/// - `link`, and only where the scheme is `https`. `DiscoverDetailSheet.swift`'s repository row
///   already applies that rule to a registry-supplied URL; this is the same rule one level in,
///   where the URL is supplied by the document body instead.
///
/// Everything else — `imageURL` included — is not carried over. Rebuilding the string run by run
/// rather than removing attributes from it is deliberate: a removal list silently stops covering an
/// attribute somebody adds later, and a rebuild cannot.
public struct MarkdownInline: Equatable, Sendable {
    /// The sanitised runs. Safe to hand straight to a `Text`.
    public let attributed: AttributedString

    /// The characters, with no attributes — what the copy layer of the fidelity gate compares.
    public var text: String { String(attributed.characters) }

    public var isEmpty: Bool { attributed.characters.isEmpty }

    /// Text with no markup at all. The fallback path, and the way a caller says *this is already
    /// literal* rather than asking for it to be parsed again.
    public init(literal: String) {
        attributed = AttributedString(literal)
    }

    /// Parses one run of Markdown and sanitises whatever came back.
    ///
    /// **The failure path renders the source rather than nothing.** `SWIFT_PRACTICES.md` §3 forbids
    /// `try?`-and-default, and this is the other option it leaves: the error is handled, and what
    /// it is handled *into* is the literal text the document contained. A run that could not be
    /// parsed is still a run somebody wrote, and showing it is the same rule as
    /// `MarkdownBlock.plainText` — visible beats dropped.
    public init(markdown source: String) {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .throwError
        )
        do {
            attributed = try Self.sanitized(AttributedString(markdown: source, options: options))
        } catch {
            attributed = AttributedString(source)
        }
    }

    /// Whether this app is willing to make a link out of a URL a document supplied.
    ///
    /// `https` and nothing else. Not `http`, which is a downgrade a document should not be able to
    /// ask for; not `file`, which would put a local path behind a press; not a custom scheme, which
    /// is a request to hand the press to whichever app claimed it.
    public static func isPermittedLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
    }

    /// Rebuilds the string from its runs, keeping only what the allowlist above names.
    static func sanitized(_ parsed: AttributedString) -> AttributedString {
        var clean = AttributedString()
        for run in parsed.runs {
            var piece = AttributedString(String(parsed[run.range].characters))
            if let intent = run.inlinePresentationIntent {
                piece.inlinePresentationIntent = intent
            }
            if let link = run.link, isPermittedLink(link) {
                piece.link = link
            }
            clean.append(piece)
        }
        return clean
    }
}
