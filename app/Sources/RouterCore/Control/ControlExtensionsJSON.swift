import Foundation

/// The JSON the extension routes answer with.
///
/// Split from the dispatch in `ControlExtensions.swift` so neither file carries both, and built
/// out of ``JSONValue`` members in a fixed order rather than through an encoder — the constraint
/// `scripts/lint/no-wire-codable.sh` enforces over this half of the router, and the reason is that
/// a reordering encoder makes a byte comparison meaningless.
///
/// **Every member is always present, and an unobserved figure is `null` rather than `0`.** A count
/// the router could not take reads `null` beside the sentence saying why, because a zero there is
/// a measurement and this is an absence (`DESIGN.md` §6). A decoder can therefore treat the shape
/// as fixed and the values as optional, instead of inferring an empty store from a missing key.
extension ControlHandler {
    /// One kind's collection.
    static func listingValue(_ listing: ExtensionListing) -> JSONValue {
        .object([
            JSONMember(key: JSString("kind"), value: .string(JSString(listing.kind.rawValue))),
            JSONMember(key: JSString("root"), value: .string(JSString(listing.root))),
            JSONMember(
                key: JSString("count"),
                value: listing.unreadable == nil
                    ? .number(Double(listing.records.count)) : .null
            ),
            JSONMember(
                key: JSString("unreadable"),
                value: listing.unreadable.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(
                key: JSString("entries"), value: .array(listing.records.map(recordValue))
            )
        ])
    }

    static func recordValue(_ record: ExtensionRecord) -> JSONValue {
        .object([
            JSONMember(key: JSString("name"), value: .string(JSString(record.name))),
            JSONMember(
                key: JSString("title"),
                value: record.title.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(
                key: JSString("description"),
                value: record.description.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(key: JSString("files"), value: .number(Double(record.files))),
            JSONMember(key: JSString("bytes"), value: .number(Double(record.bytes))),
            // Present and null on a clean entry, so a reader distinguishes "read fine" from a key
            // it failed to find. An entry with a problem is still listed and still counted.
            JSONMember(
                key: JSString("problem"),
                value: record.problem.map { JSONValue.string(JSString($0)) } ?? .null
            )
        ])
    }

    /// A refusal carries its slug beside its sentence.
    ///
    /// Two members rather than the single `{"error": …}` every ported route answers with, and the
    /// precedent is `GET /servers/:name/document`, which already adds a `reason` for the same
    /// purpose: the sentence is for a person and the slug is what a caller branches on. Adding a
    /// member is safe here in a way it is not on a ported route, because no reference body exists
    /// for this family to diverge from.
    static func refusalValue(_ refusal: ExtensionRefusal) -> ControlAPIResponse {
        .json(refusal.status, .object([
            JSONMember(key: JSString("error"), value: .string(JSString(refusal.message))),
            JSONMember(key: JSString("reason"), value: .string(JSString(refusal.reason)))
        ]))
    }

    /// `GET /extensions` — what is installed, across all four kinds, in one request.
    ///
    /// Servers come from the **live upstream map**, which is the same source `GET /servers` reads,
    /// so the two can never disagree about how many there are. The other three are read off disk on
    /// this call. Neither number is remembered anywhere.
    func inventory(_ store: any ExtensionStoring, _ deps: ControlDeps) -> ControlAPIResponse {
        let listings = ExtensionKind.allCases.map { store.list($0) }
        var counts: [JSONMember] = [
            JSONMember(
                key: JSString("servers"), value: .number(Double(deps.upstreams.count))
            )
        ]
        var kinds: [JSONMember] = []
        for listing in listings {
            counts.append(JSONMember(
                key: JSString(listing.kind.rawValue),
                value: listing.unreadable == nil
                    ? .number(Double(listing.records.count)) : .null
            ))
            kinds.append(JSONMember(
                key: JSString(listing.kind.rawValue), value: Self.listingValue(listing)
            ))
        }
        var members: [JSONMember] = [
            JSONMember(key: JSString("counts"), value: .object(counts)),
            // Name and transport only. `GET /servers` is where a server's own row lives, and
            // repeating it here would be a second copy of a body that already exists.
            JSONMember(key: JSString("servers"), value: .array(deps.upstreams.map { entry in
                .object([
                    JSONMember(key: JSString("name"), value: .string(entry.name)),
                    JSONMember(
                        key: JSString("transport"),
                        value: .string(JSString(entry.upstream.transport.rawValue))
                    )
                ])
            }))
        ]
        members.append(contentsOf: kinds)
        return .json(200, .object(members))
    }
}
