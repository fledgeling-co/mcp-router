import Foundation

/// A capability's documentation, parsed and ready to draw.
///
/// Three tabs over one panel rather than one long scroll: "what changed" and "what does it do" are
/// asked at different moments, and `spec-M19.md` §2's third assumption records that as the shape.
///
/// **A tab with no entry here was not published, and that is different from empty.** The dictionary
/// is the distinction: a capability that ships a read me and no changelog has one key, and the
/// panel says which document is missing rather than drawing a blank pane under a tab that
/// implies one exists.
///
/// **The images are already bytes.** Nothing downstream of this type holds a path or a URL, so no
/// view can be talked into a fetch by a document that names one. Resolution — including every
/// refusal — happened in `PackageImageResolver` before this value was built, which is what keeps
/// `MCPRouterUI` free of the filesystem that `SWIFT_PRACTICES.md` §8 and A36 both require.
public struct CapabilityDocument: Equatable, Sendable {
    /// The three tabs the panel's titlebar carries, in the mock's order.
    public enum Tab: String, CaseIterable, Hashable, Sendable, Identifiable {
        case readMe
        case changelog
        case capabilities

        public var id: String { rawValue }

        /// Sentence case, as `DESIGN.md` §6 requires, and the mock's own words.
        public var title: String {
            switch self {
            case .readMe: "Read me"
            case .changelog: "Changelog"
            case .capabilities: "Capabilities"
            }
        }

        /// What the panel says when this tab has nothing behind it. Names the document rather than
        /// saying "no content", and says the other tabs are still there — the reader arrived to
        /// make a decision and one missing document does not end it.
        public var absentSentence: String {
            switch self {
            case .readMe:
                "This capability ships no read me. Its changelog and capabilities are still here."
            case .changelog:
                "This capability ships no changelog. Its read me and capabilities are still here."
            case .capabilities:
                "This capability declares no capability list. Its read me and changelog are still here."
            }
        }
    }

    /// Who published this and what it says it is — the product header's contents.
    public struct Identity: Equatable, Sendable {
        public var name: String
        public var version: String?
        /// **Optional for the same reason a fact is absent rather than empty.** A marketplace names
        /// a publisher; a server declared in a config file has none the router observes, and an
        /// empty `Text` in the header's stack reserves layout for a fact nobody has.
        public var publisher: String?
        /// Whether the marketplace this came from marks the publisher as official.
        public var publisherIsVerified: Bool
        /// The one-line pitch, where something observed one. See ``publisher``.
        public var pitch: String?
        /// Where the capability says it lives, and only when it is `https`.
        ///
        /// Filtered at construction rather than at the press, so no view holds a URL this app would
        /// not open — the same rule `MarkdownInline` applies to a link inside the body, and the same
        /// one `DiscoverDetailSheet` applies to a registry entry's repository.
        public let repository: URL?

        public init(
            name: String,
            version: String? = nil,
            publisher: String? = nil,
            publisherIsVerified: Bool = false,
            pitch: String? = nil,
            repository: URL? = nil
        ) {
            self.name = name
            self.version = version
            self.publisher = publisher
            self.publisherIsVerified = publisherIsVerified
            self.pitch = pitch
            self.repository = repository.flatMap { MarkdownInline.isPermittedLink($0) ? $0 : nil }
        }
    }

    /// One cell of the facts strip: a label and the reading under it.
    ///
    /// A list rather than five named fields, because a fact nobody observed must be **absent**
    /// rather than empty. `DESIGN.md` §6's rule is that nothing is displayed that the router does
    /// not observe, and five fixed properties would put five cells on screen whatever was known.
    public struct Fact: Equatable, Sendable, Identifiable {
        public var label: String
        public var value: String

        public var id: String { label }

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public var identity: Identity
    public var facts: [Fact]
    /// The blocks per tab. A missing key means the capability published no such document.
    public var tabs: [Tab: [MarkdownBlock]]
    /// Image reference, exactly as the document wrote it, to the bytes that were found for it.
    public var images: [String: Data]
    /// Image reference to the reason it is not in `images`. Drawn as a placeholder that says so.
    public var refusedImages: [String: PackageImageResolver.Refusal]

    public init(
        identity: Identity,
        facts: [Fact] = [],
        tabs: [Tab: [MarkdownBlock]] = [:],
        images: [String: Data] = [:],
        refusedImages: [String: PackageImageResolver.Refusal] = [:]
    ) {
        self.identity = identity
        self.facts = facts
        self.tabs = tabs
        self.images = images
        self.refusedImages = refusedImages
    }

    /// The blocks for one tab, or nil where the capability published no such document.
    public func blocks(for tab: Tab) -> [MarkdownBlock]? {
        tabs[tab]
    }

    /// Which tabs have something behind them. The titlebar draws all three regardless — a tab that
    /// disappeared would make the panel's shape depend on the capability, and a reader could not
    /// tell "no changelog" from "this app does not show changelogs".
    public var publishedTabs: [Tab] { Tab.allCases.filter { tabs[$0] != nil } }
}
