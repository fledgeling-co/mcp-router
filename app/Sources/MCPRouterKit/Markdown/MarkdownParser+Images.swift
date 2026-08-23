import Foundation

/// Paragraphs, and the two things a run of images can turn out to be.
///
/// A run that is nothing but images is either a shield row — the badges that open almost every
/// document of this kind, re-drawn rather than loaded — or figures. A sentence that merely
/// contains an image stays a paragraph, where the system parser keeps the prose around it.
extension MarkdownParser {
    // MARK: - Paragraphs, images and shields

    /// Reads to the next blank line, then decides what the run actually is.
    static func readParagraph(
        _ lines: [String],
        from index: Int,
        into blocks: inout [MarkdownBlock]
    ) -> Int {
        var run: [String] = []
        var cursor = index
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            // A paragraph ends where a block that is not a paragraph begins, so a heading directly
            // under a line of prose is still a heading — and so is a heading level the ladder
            // cannot draw, which is a block of its own here rather than more of this paragraph.
            if cursor > index,
               fenceMarker(trimmed) != nil || isThematicBreak(trimmed)
               || hashLine(trimmed).startsABlock || trimmed.hasPrefix(">") || listMarker(trimmed) != nil
            {
                break
            }
            run.append(trimmed)
            cursor += 1
        }
        let text = run.joined(separator: " ")
        if text.isEmpty { return max(cursor - index, 1) }

        let images = inlineImages(in: text)
        if !images.isEmpty, isOnlyImages(text, images: images) {
            let shields = images.compactMap { Shield.parse($0.reference) }
            if shields.count == images.count {
                blocks.append(.shields(shields))
            } else {
                for image in images {
                    blocks.append(.image(image))
                }
            }
        } else {
            blocks.append(.paragraph(MarkdownInline(markdown: text)))
        }
        return max(cursor - index, 1)
    }

    /// Every `![alt](reference)` in a run, in order.
    ///
    /// Hand-scanned rather than regexed because a reference may contain balanced parentheses —
    /// Wikipedia URLs and generated badge paths both do — and the obvious `\(([^)]*)\)` closes on
    /// the first one and yields a reference that is not the one the document wrote.
    static func inlineImages(in text: String) -> [MarkdownImage] {
        var images: [MarkdownImage] = []
        var index = text.startIndex
        while let bang = text[index...].firstIndex(of: "!") {
            let afterBang = text.index(after: bang)
            guard afterBang < text.endIndex, text[afterBang] == "[" else {
                index = afterBang
                continue
            }
            guard let closeBracket = text[afterBang...].firstIndex(of: "]") else { break }
            let openParen = text.index(after: closeBracket)
            guard openParen < text.endIndex, text[openParen] == "(" else {
                index = openParen
                continue
            }
            var depth = 0
            var cursor = openParen
            var closeParen: String.Index?
            while cursor < text.endIndex {
                if text[cursor] == "(" { depth += 1 }
                if text[cursor] == ")" {
                    depth -= 1
                    if depth == 0 { closeParen = cursor; break }
                }
                cursor = text.index(after: cursor)
            }
            guard let closeParen else { break }
            let alt = String(text[text.index(after: afterBang) ..< closeBracket])
            // A title after the reference — `(a.png "caption")` — is not carried: nothing draws it,
            // and keeping it would make the reference unresolvable.
            let inside = String(text[text.index(after: openParen) ..< closeParen])
            let reference = inside.split(separator: " ", maxSplits: 1).first.map(String.init) ?? inside
            images.append(MarkdownImage(alternateText: alt, reference: reference))
            index = text.index(after: closeParen)
        }
        return images
    }

    /// Whether a run is images and whitespace and nothing else.
    ///
    /// This is what separates the shield row at the top of a README — four badges on one line —
    /// from a sentence that happens to contain an inline image. Only the first becomes its own
    /// block; the second stays a paragraph, where the system parser keeps the surrounding prose.
    static func isOnlyImages(_ text: String, images: [MarkdownImage]) -> Bool {
        var remainder = text
        for image in images {
            let alt = image.alternateText
            // Reconstructed rather than range-tracked so the check reads against the same spelling
            // the scan produced; a reference the scan trimmed a title from will not match, which
            // correctly leaves that run a paragraph.
            let spelling = "![\(alt)](\(image.reference))"
            guard let found = remainder.range(of: spelling) else { return false }
            remainder.removeSubrange(found)
        }
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
