import Foundation

/// The document a Debug build and the measurement harness render.
///
/// **Invented data, labelled as such**, exactly as `SkillFixtures` is: there is no captured session
/// to be faithful to, because nothing serves a document at all (`CapabilityDocumentSource`). A
/// Release build never reaches this — `ShellClientFactory` returns the live client unconditionally
/// outside Debug — and no shipped surface presents the panel, so this cannot render in front of a
/// user.
///
/// It is a real package on disk rather than a Swift string, and that is the point of it. The files
/// are copied into the bundle by `Package.swift`'s existing `Control/Authored` resource, the
/// directory holding them **is** the package root the image resolver is given, and `docs/matches.png`
/// is a real file inside it. So "images resolve from inside the downloaded package" is a path this
/// fixture exercises rather than a sentence describing one.
///
/// This is also the only type in the item that touches the filesystem. It lives in the kit for the
/// reason `SWIFT_PRACTICES.md` §8 gives: the presentation layer must not reach past the control
/// API, so what reaches a view is a `CapabilityDocument` whose images are already bytes.
public struct FixtureCapabilityDocumentSource: CapabilityDocumentSource {
    /// The one capability the fixture package holds.
    public static let capabilityName = "trawl"

    /// Where the fixture package sits inside the resource bundle.
    static let packageSubdirectory = "Authored/capability-documents/trawl"

    private let limits: MarkdownLimits

    public init(limits: MarkdownLimits = .standard) {
        self.limits = limits
    }

    public func document(for name: String) async throws(CapabilityDocumentError) -> CapabilityDocument {
        guard name == Self.capabilityName, let document = Self.build(limits: limits) else {
            throw .notFound(capability: name)
        }
        return document
    }

    /// The parsed fixture, or nil when the resource bundle does not carry the package.
    ///
    /// **Nil rather than a partial document.** A bundle missing its resources is a build problem,
    /// and a fixture that silently degraded to "this capability ships no read me" would report a
    /// packaging failure as a product state — which is the empty-result failure mode
    /// `SWIFT_PRACTICES.md` §2 names as the worst one available.
    public static func build(limits: MarkdownLimits = .standard) -> CapabilityDocument? {
        guard let root = packageRoot() else { return nil }

        var tabs: [CapabilityDocument.Tab: [MarkdownBlock]] = [:]
        var images: [String: Data] = [:]
        var refused: [String: PackageImageResolver.Refusal] = [:]

        for (tab, file) in [
            (CapabilityDocument.Tab.readMe, "README.md"),
            (CapabilityDocument.Tab.changelog, "CHANGELOG.md"),
            (CapabilityDocument.Tab.capabilities, "CAPABILITIES.md")
        ] {
            guard let source = try? String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            else { continue }
            let blocks = MarkdownParser.blocks(from: source, limits: limits)
            tabs[tab] = blocks
            resolveImages(in: blocks, root: root, into: &images, refused: &refused)
        }
        guard !tabs.isEmpty else { return nil }

        return CapabilityDocument(
            identity: CapabilityDocument.Identity(
                name: "trawl",
                version: "1.4.2",
                publisher: "Fledgeling",
                publisherIsVerified: true,
                pitch: "Mine your own past agent sessions for evidence about what happened.",
                repository: URL(string: "https://github.com/fledgeling-co/fledgeling-plugins")
            ),
            // The mock's five cells. Every one of them is a fact about the *package*, which is
            // what a document source would have to serve alongside the files — they are here for
            // the same reason the files are, and they are invented for the same reason.
            facts: [
                .init(label: "Kind", value: "Skill · no server"),
                .init(label: "Version", value: "1.4.2 · 1.5.0 held"),
                .init(label: "Licence", value: "MIT"),
                .init(label: "Runs in", value: "All 4 harnesses"),
                .init(label: "Reads", value: "4 session stores, locally")
            ],
            tabs: tabs,
            images: images,
            refusedImages: refused
        )
    }

    /// Every image the blocks name, resolved against the package once.
    ///
    /// Recursive, because a quote can hold one. A reference that resolves is read into memory here;
    /// a reference that does not keeps its refusal, so the placeholder can say which of the four
    /// things happened rather than "image missing".
    private static func resolveImages(
        in blocks: [MarkdownBlock],
        root: URL,
        into images: inout [String: Data],
        refused: inout [String: PackageImageResolver.Refusal]
    ) {
        for block in blocks {
            switch block {
            case let .image(image):
                guard images[image.reference] == nil, refused[image.reference] == nil else { continue }
                switch PackageImageResolver.resolve(image.reference, inPackageAt: root) {
                case let .success(url):
                    if let data = try? Data(contentsOf: url) {
                        images[image.reference] = data
                    } else {
                        refused[image.reference] = .notInPackage
                    }
                case let .failure(refusal):
                    refused[image.reference] = refusal
                }
            case let .blockquote(inner):
                resolveImages(in: inner, root: root, into: &images, refused: &refused)
            default:
                continue
            }
        }
    }

    /// The package directory inside the resource bundle.
    ///
    /// Located through a file it is known to contain, because `Bundle.url(forResource:)` answers
    /// for files and not for directories that were copied wholesale.
    static func packageRoot() -> URL? {
        Bundle.module
            .url(forResource: "README", withExtension: "md", subdirectory: packageSubdirectory)?
            .deletingLastPathComponent()
    }
}
