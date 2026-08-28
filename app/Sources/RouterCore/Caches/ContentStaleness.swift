import Foundation

/// What comparing an upstream's recorded content against its current content produced.
public enum ContentVerdict: Sendable, Hashable {
    /// Nothing was recorded for this server, so there is nothing to compare against. **Not
    /// movement** — the first index after this ships would otherwise re-derive every manifest row
    /// on a machine that had no defect.
    case firstSight(ContentIdentity)
    case same(ContentIdentity)
    case moved(before: String, after: ContentIdentity)
    /// The router cannot say what this upstream runs. Also **not movement**, and the reason
    /// travels so a reader can see which of the two greens they are looking at.
    case unresolvable(String)

    public var identity: ContentIdentity? {
        switch self {
        case let .firstSight(identity): identity
        case let .same(identity): identity
        case let .moved(_, identity): identity
        case .unresolvable: nil
        }
    }

    /// The one state that costs a re-index.
    public var hasMoved: Bool {
        if case .moved = self { return true }
        return false
    }
}

/// The content half of staleness, kept **separate from** ``ToolUnion/isStale(_:_:)``.
///
/// Two reasons it is not folded in, and the second is the load-bearing one.
///
/// `ToolUnion.isStale` is a byte-faithful port of the reference's `isStale`, compared against it by
/// the parity harness; changing what it answers would move a shared behaviour rather than add a
/// Swift-only one.
///
/// And staleness is consulted in two very different places. `mcp-router index` asks it once per
/// run, off a cold command line, and re-deriving a manifest row there costs one child process for
/// the length of a `tools/list`. `serve` asks it at start-up, for every upstream at once — so a
/// content probe wired into *that* path would spawn every configured server the first time a router
/// met a manifest written before this existed, which is exactly the cost the router exists to
/// remove. **The content component is therefore consulted by the deliberate paths — `index`, and
/// the invalidation route — and never by `serve`.**
public enum ContentStaleness {
    /// The member name the reading is recorded under, alongside `hash`, `digest` and `builtAt`.
    public static let member = "content"

    public static func verdict(
        manifest: Manifest, upstream: UpstreamConfig, probe: any CacheProbing
    ) -> ContentVerdict {
        verdict(recorded: manifest.entry(named: upstream.name), upstream: upstream, probe: probe)
    }

    public static func verdict(
        recorded: CachedServer?, upstream: UpstreamConfig, probe: any CacheProbing
    ) -> ContentVerdict {
        let current = ContentResolution.resolve(upstream, probe: probe)
        guard let digest = current.digest else {
            return .unresolvable(current.reason ?? "the reason was not recorded")
        }
        guard let previous = recordedDigest(recorded) else { return .firstSight(current) }
        return previous == digest ? .same(current) : .moved(before: previous, after: current)
    }

    /// The digest an entry carries, or `nil` when it carries none.
    ///
    /// An entry written before this member existed reads `nil` here, which routes it to
    /// `firstSight`. That is deliberate: a manifest the reference wrote — or one this router wrote
    /// last week — must not read as "everything moved".
    public static func recordedDigest(_ entry: CachedServer?) -> String? {
        guard let entry, let content = entry.member(member) else { return nil }
        guard let digest = content.member("digest")?.asString, !digest.string.isEmpty else { return nil }
        return digest.string
    }

    /// The reading, as the members it is written to disk as.
    ///
    /// Every member is present and an unresolved reading carries `null` digest and source beside
    /// its sentence, rather than being omitted — the shape `GET /extensions` uses, so a reader
    /// distinguishes "not resolved" from "key not written" (`DESIGN.md` §6).
    public static func value(_ identity: ContentIdentity) -> JSONValue {
        .object([
            JSONMember(key: JSString("class"), value: .string(JSString(identity.contentClass.rawValue))),
            JSONMember(
                key: JSString("digest"),
                value: identity.digest.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(
                key: JSString("source"),
                value: identity.source.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(
                key: JSString("reason"),
                value: identity.reason.map { JSONValue.string(JSString($0)) } ?? .null
            )
        ])
    }

    /// Writes the reading onto an entry, in place.
    public static func record(_ identity: ContentIdentity, on entry: inout CachedServer) {
        entry.set(member, value(identity))
    }
}
