import Foundation

/// The pieces of the run that are about `~/.claude.json` itself: which entries are candidates, and
/// which of the adopted ones may be deleted from staging.
///
/// Split from ``WatchRunner`` on the seam the reference already has — decide, index, adopt — rather
/// than to satisfy a line count.
enum WatchStaging {
    /// Never adopted: the router's own entry. `RESERVED` in the reference.
    static let reserved: Set<String> = ["router"]

    /// The port handed to ``SelfReference/isSelfReference(name:raw:port:)``.
    ///
    /// The literal **8879**, not the configured port — `watch.ts:182` hardcodes
    /// `const routerPort = 8879`. Reading the real port would make this skip a self-URL on a
    /// non-default port that the reference happily adopts, which is a divergence nobody declared.
    /// It looks like a bug and it is parity; it is written down here so it is not "fixed" later.
    static let selfReferencePort = 8879

    struct Candidate {
        let name: String
        /// The entry exactly as `~/.claude.json` declared it, kept so the pre-delete comparison
        /// (W5) is against what was indexed rather than against a reconstruction.
        let raw: JSONValue
        let upstream: UpstreamConfig
    }

    /// `candidateOf` over the staged entries, in file order.
    ///
    /// **Every parseable transport is a candidate, not only stdio** (W9). The reference's
    /// `candidateOf` applies no stdio filter; the brief's "new stdio entries" describes the common
    /// case, not the contract.
    static func candidates(in staged: [JSONMember], log: WatchLog) -> [Candidate] {
        var found: [Candidate] = []
        for member in staged {
            let name = member.key.string
            if reserved.contains(name) { continue }
            if SelfReference.isSelfReference(
                name: name, raw: member.value, port: selfReferencePort
            ) { continue }
            switch ServerParser.parse(name: name, raw: member.value) {
            case let .upstream(upstream):
                found.append(Candidate(name: name, raw: member.value, upstream: upstream))
            case let .skipped(reason):
                log.record(.skipped(name: name, reason: reason))
            }
        }
        return found
    }

    /// Which adopted names may be deleted from a **freshly re-read** staging file, and which must be
    /// left alone (W5).
    ///
    /// Indexing spawns a child and waits for it to initialize, so the window is seconds — long
    /// enough for someone to correct the entry they just added. Deleting an edited definition would
    /// throw that edit away with nothing to recover it from: the router would hold the pre-edit
    /// version and the file it was typed into would no longer have it.
    static func removable(
        adopted: [String],
        indexedAs: [String: JSONValue],
        staged: [JSONMember],
        log: WatchLog
    ) -> (remove: Set<String>, stillPending: [String]) {
        var remove: Set<String> = []
        var stillPending: [String] = []
        for name in adopted {
            guard let staging = staged.first(where: { $0.key == JSString(name) })?.value else {
                continue
            }
            if case .skipped = ServerParser.parse(name: name, raw: staging) { continue }
            if reserved.contains(name) { continue }
            let indexed = indexedAs[name] ?? .null
            guard JSStringify.compact(StableHash.stable(staging))
                == JSStringify.compact(StableHash.stable(indexed))
            else {
                // Leaving it puts the name back in `pending`, which withholds the state hash so the
                // next fire re-indexes it.
                log.record(.changedWhileIndexing(name: name))
                stillPending.append(name)
                continue
            }
            remove.insert(name)
        }
        return (remove, stillPending)
    }

    /// The `mcpServers` object of a parsed `~/.claude.json`, or an empty one.
    static func stagedServers(of parsed: JSONValue) -> [JSONMember] {
        guard let root = parsed.asObjectMembers,
              case let .object(members)? = root
              .first(where: { $0.key == JSString("mcpServers") })?.value
        else { return [] }
        return members
    }

    /// Replace the `mcpServers` object of a parsed root, preserving every other top-level member at
    /// the position it already occupied.
    static func replacingStagedServers(
        in root: [JSONMember], with servers: [JSONMember]
    ) -> [JSONMember] {
        var updated = root
        let key = JSString("mcpServers")
        let member = JSONMember(key: key, value: .object(servers))
        if let index = updated.firstIndex(where: { $0.key == key }) {
            updated[index] = member
        } else {
            updated.append(member)
        }
        return updated
    }
}
