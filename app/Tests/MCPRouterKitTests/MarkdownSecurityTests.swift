import Foundation
import Testing
@testable import MCPRouterKit

/// The untrusted-input boundary, which is the whole reason M19 has constraints rather than just a
/// renderer. A README arrives from a marketplace into an app that rewrites other tools'
/// configuration: nothing in it may run, load, or reach the network.
@Suite("A document is data — M19's untrusted-input rules")
struct MarkdownSecurityTests {
    private func links(in inline: MarkdownInline) -> [URL] {
        inline.attributed.runs.compactMap(\.link)
    }

    // MARK: - Links

    @Test("an https link survives")
    func httpsSurvives() {
        let inline = MarkdownInline(markdown: "[home](https://example.com/a)")
        #expect(links(in: inline).map(\.absoluteString) == ["https://example.com/a"])
    }

    /// The one that matters. `DiscoverDetailSheet` already refuses a non-https repository URL from
    /// the registry; this is the same rule where the URL comes from the document body instead.
    @Test("every other scheme is stripped, and the words stay")
    func otherSchemesStripped() {
        for spelling in [
            "[x](javascript:alert(1))",
            "[x](file:///etc/passwd)",
            "[x](data:text/html;base64,PHNjcmlwdD4=)",
            "[x](http://example.com)",
            "[x](mcprouter://install?server=evil)",
            "[x](vbscript:msgbox)"
        ] {
            let inline = MarkdownInline(markdown: spelling)
            #expect(links(in: inline).isEmpty, "\(spelling) kept a link")
            #expect(inline.text == "x", "\(spelling) lost its words")
        }
    }

    /// An image is not an inline attribute here — it is a block the resolver decides about — so no
    /// `imageURL` may reach a view, where it would be one `Text` initialiser away from a fetch.
    @Test("no image attribute survives an inline run")
    func imageAttributeStripped() {
        let inline = MarkdownInline(markdown: "![pixel](https://tracker.example/p.gif)")
        #expect(inline.attributed.runs.allSatisfy { $0.imageURL == nil })
    }

    /// Pinned rather than assumed. If a toolchain change starts interpreting inline HTML, this goes
    /// red here instead of a `<script>` quietly acquiring meaning somewhere downstream.
    @Test("inline HTML acquires no attribute of any kind")
    func htmlIsInert() {
        for spelling in [
            "<script>alert(1)</script>",
            "<img src=x onerror=alert(1)>",
            "<a href=\"javascript:alert(1)\">press</a>",
            "<span class=\"pill\">available</span>"
        ] {
            let inline = MarkdownInline(markdown: spelling)
            #expect(links(in: inline).isEmpty, "\(spelling) produced a link")
            #expect(inline.attributed.runs.allSatisfy { $0.imageURL == nil }, "\(spelling) produced an image")
        }
    }

    /// `SWIFT_PRACTICES.md` §3 forbids `try?`-and-default. The error is handled, and what it is
    /// handled into is the run's own source text — visible, like `MarkdownBlock.plainText`.
    @Test("a run the parser refuses renders its own source with no attributes")
    func unparseableRunFallsBackToItsSource() {
        let hostile = String(repeating: "[", count: 400) + "x"
        let inline = MarkdownInline(markdown: hostile)
        #expect(!inline.text.isEmpty)
        #expect(links(in: inline).isEmpty)
    }

    // MARK: - Images

    @Test("a reference inside the package resolves")
    func insidePackageResolves() throws {
        let root = try scratchPackage()
        defer { try? FileManager.default.removeItem(at: root) }
        let resolved = try PackageImageResolver.resolve("docs/a.png", inPackageAt: root).get()
        #expect(resolved.lastPathComponent == "a.png")
    }

    @Test("every route out of the package is refused, each with its own reason")
    func outsidePackageRefused() throws {
        let root = try scratchPackage()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected: [String: PackageImageResolver.Refusal] = [
            "https://tracker.example/p.gif": .remote(scheme: "https"),
            "http://tracker.example/p.gif": .remote(scheme: "http"),
            "data:image/png;base64,AAAA": .remote(scheme: "data"),
            "file:///etc/passwd": .remote(scheme: "file"),
            "/etc/passwd": .absolutePath,
            "~/.ssh/id_rsa": .absolutePath,
            "../../../../etc/passwd": .escapesPackage,
            "docs/../../outside.png": .escapesPackage,
            "docs/missing.png": .notInPackage
        ]
        for (reference, refusal) in expected {
            switch PackageImageResolver.resolve(reference, inPackageAt: root) {
            case .success:
                Issue.record("\(reference) resolved and should not have")
            case let .failure(actual):
                #expect(actual == refusal, "\(reference) refused as \(actual)")
            }
        }
    }

    /// The classic way this check is written wrong: `/pkg-evil` has `/pkg` as a string prefix and
    /// is not inside it. The comparison is on path components for exactly this case.
    @Test("a sibling directory sharing the root's name prefix is outside the package")
    func siblingPrefixIsOutside() throws {
        let root = try scratchPackage()
        defer { try? FileManager.default.removeItem(at: root) }
        let sibling = root.deletingLastPathComponent()
            .appendingPathComponent(root.lastPathComponent + "-evil")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        try Data("x".utf8).write(to: sibling.appendingPathComponent("a.png"))

        let reference = "../\(root.lastPathComponent)-evil/a.png"
        switch PackageImageResolver.resolve(reference, inPackageAt: root) {
        case .success: Issue.record("a sibling directory resolved as inside the package")
        case let .failure(refusal): #expect(refusal == .escapesPackage)
        }
    }

    /// A downloaded archive can ship a symlink pointing out of itself, and standardising a path
    /// does not see one. The resolver resolves both sides before comparing, and this is the check
    /// that says so rather than the comment.
    @Test("a symlink inside the package pointing outside it is refused")
    func symlinkEscapeRefused() throws {
        let root = try scratchPackage()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("m19-outside-\(UUID().uuidString).png")
        try Data("x".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("docs/escape.png"), withDestinationURL: outside
        )

        switch PackageImageResolver.resolve("docs/escape.png", inPackageAt: root) {
        case .success: Issue.record("a symlink out of the package resolved as inside it")
        case let .failure(refusal): #expect(refusal == .escapesPackage)
        }
    }

    /// A refusal is user-facing copy's input, so each one says a different thing that happened
    /// rather than sharing one "invalid" (`DESIGN.md` §6).
    @Test("each refusal carries its own sentence, and none of them blames the reader")
    func refusalCopyIsDistinct() {
        let sentences = [
            PackageImageResolver.Refusal.remote(scheme: "https"),
            .absolutePath, .escapesPackage, .notInPackage
        ].map(\.sentence)
        #expect(Set(sentences).count == sentences.count)
        #expect(sentences.allSatisfy { !$0.lowercased().contains("you ") || $0.contains("your Mac") })
        #expect(sentences.allSatisfy { $0.hasPrefix("Not shown — ") })
    }

    // MARK: - Shields

    /// The structural half of "the shield colours are the token values rather than the badge's
    /// own": a parsed shield has nowhere to put `#4c1`, so a view has nothing to reach for except a
    /// `ColorToken`.
    @Test("a parsed shield carries no colour from the badge")
    func shieldCarriesNoColour() throws {
        let shield = try #require(
            Shield.parse("https://img.shields.io/badge/checks-12%20of%2012-4c1?style=flat&logo=git")
        )
        #expect(shield.key == "checks")
        #expect(shield.value == "12 of 12")
        #expect(shield.tone == .good)
        let mirrored = Mirror(reflecting: shield).children.compactMap(\.label).sorted()
        #expect(mirrored == ["key", "tone", "value"])
    }

    /// A badge's query is read for nothing, which is also what stops `&link=` smuggling a second
    /// destination past the link rule.
    @Test("a badge's query is discarded entirely")
    func queryDiscarded() throws {
        let plain = try #require(Shield.parse("https://img.shields.io/badge/a-b-blue"))
        let decorated = try #require(
            Shield.parse("https://img.shields.io/badge/a-b-blue?link=javascript:alert(1)&style=social")
        )
        #expect(plain == decorated)
    }

    @Test("a badge from another host is not a shield")
    func foreignHostIsNotAShield() {
        #expect(Shield.parse("https://badges.example.com/badge/a-b-blue") == nil)
        #expect(Shield.parse("https://img.shields.io.evil.com/badge/a-b-blue") == nil)
        #expect(Shield.parse("docs/badge.png") == nil)
    }

    private func scratchPackage() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("m19-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("docs"), withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: root.appendingPathComponent("docs/a.png"))
        return root
    }
}
