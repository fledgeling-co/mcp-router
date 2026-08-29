import Foundation

/// The `/profiles` family — F8.
///
/// It **diverges from `src/control.ts`**, which answers every path here 404, in exactly the way
/// R28's `/extensions` family does. Declared in `planning/parity/surface.tsv` rather than left to
/// be discovered, because a Swift-only route demands no row anywhere by derivation and is invisible
/// to every mechanical check in that file.
///
/// **Nothing here writes anything a harness owns.** `GET /profiles/:name/projection` reads the
/// skill roots and renders what a profile would require; no route in this family, and no type it
/// reaches, creates, links, moves or removes a path outside the router's own home.
extension ControlHandler {
    func routeProfiles(
        _ path: String, _ request: ControlAPIRequest, _ deps: ControlDeps
    ) -> ControlAPIResponse? {
        guard path == "/profiles" || path.hasPrefix("/profiles/") else { return nil }
        guard let store = deps.profiles else {
            // The shape `/extensions` uses when its one dependency is absent: name the missing
            // capability rather than answering an empty list, which is indistinguishable from a
            // router holding no profiles.
            return .error(503, "profiles are unavailable: this router has no profile store")
        }
        let rest = String(path.dropFirst("/profiles".count))
        if rest.isEmpty {
            guard request.method == "GET" else { return nil }
            return .json(200, Self.profileListingValue(store.list()))
        }
        let segments = rest.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard let rawName = segments.first, !rawName.isEmpty else {
            return .error(404, "no profile named \"\"")
        }
        // Percent-decoded where `ServerRoute` decodes a server name, and refused the same way: a
        // malformed escape is a 400 rather than a 404, because the router cannot say whether a name
        // it could not read exists.
        guard let name = String(rawName).removingPercentEncoding else {
            return .error(400, "URI malformed")
        }
        switch segments.count {
        case 1: return item(name, store, request)
        case 2 where segments[segments.startIndex + 1] == "projection":
            guard request.method == "GET" else { return nil }
            return projection(name, store, deps)
        // Deeper, or a sub-path this router does not serve. Returning nil lets `handle` answer its
        // own 405, which is the honest reply for a path this router claims and does not route.
        default: return nil
        }
    }

    private func item(
        _ name: String, _ store: any ProfileStoring, _ request: ControlAPIRequest
    ) -> ControlAPIResponse? {
        switch request.method {
        case "GET":
            guard let row = store.read(name: name) else {
                return .error(404, "no profile named \"\(name)\"")
            }
            return .json(200, Self.profileRowValue(row))
        case "POST":
            return write(name, store, request)
        case "DELETE":
            switch store.remove(name: name) {
            case let .removed(path):
                return .json(200, .object([
                    JSONMember(key: JSString("removed"), value: .string(JSString(name))),
                    // Where the bytes went, on the wire rather than in a log — the same contract
                    // `DELETE /extensions/:kind/:name` answers with. This route deletes nothing.
                    JSONMember(key: JSString("restorePath"), value: .string(JSString(path)))
                ]))
            case let .refused(refusal):
                return Self.refusalValue(refusal)
            }
        default:
            return nil
        }
    }

    /// `POST` and not `PUT`, and the method was chosen by a failing test rather than by taste.
    ///
    /// `ControlAPIRequest.isMutating` — the property the token and content-type gate reads — is
    /// `POST || DELETE || PATCH`, ported from `src/control.ts`. **PUT is not in it.** No route
    /// served PUT before this one, so nothing was exposed; this family would have been the first,
    /// and an untokened `PUT /profiles/x` measured 200 while the suite was otherwise green. Adding
    /// PUT to `isMutating` would have widened a ported gate that `parity-manifest-check.sh` derives
    /// from the reference in both directions, to buy a verb. `C6` holds the invariant for whoever
    /// adds the next route here.
    ///
    /// A profile is a selection somebody edits, so writing one that already exists **replaces** it.
    /// An extension entry is bytes somebody supplied and `POST /extensions/:kind` refuses a
    /// duplicate; making this route do the same would mean deleting a profile to change it.
    private func write(
        _ name: String, _ store: any ProfileStoring, _ request: ControlAPIRequest
    ) -> ControlAPIResponse {
        let body = request.bodyObject
        // Four named locals rather than a keyed map. `scripts/lint/no-wire-codable.sh` refuses a
        // Swift `Dictionary` anywhere that can reach the wire, because it loses member order and
        // code-unit key identity (S4, S5, B24) — and the selection's order is what lets a refusal
        // name a position.
        var selections: [[String]] = []
        for key in ["servers", "skills", "plugins", "marketplaces"] {
            switch Self.namesMember(body, key) {
            case let .problem(message): return .error(400, message)
            case let .names(names): selections.append(names)
            }
        }
        let record = ProfileRecord(
            name: name,
            title: body.first { $0.key == JSString("title") }?.value.asString?.string,
            servers: selections[0],
            skills: selections[1],
            plugins: selections[2],
            marketplaces: selections[3]
        )
        switch store.write(record) {
        case let .written(written): return .json(200, Self.profileValue(written))
        case let .refused(refusal): return Self.refusalValue(refusal)
        }
    }

    /// `GET /profiles/:name/projection` — what this profile would require, harness by harness.
    ///
    /// Two dependencies rather than one, and each absence is reported separately: a router with no
    /// skill-root reader can still say what its store holds, and answering an empty projection would
    /// claim every harness is satisfied.
    private func projection(
        _ name: String, _ store: any ProfileStoring, _ deps: ControlDeps
    ) -> ControlAPIResponse {
        guard let row = store.read(name: name), let profile = row.record else {
            return .error(404, "no profile named \"\(name)\"")
        }
        guard let extensions = deps.extensions else {
            return .error(503, "extension storage is unavailable: this router has no store")
        }
        guard let roots = deps.skillRoots else {
            return .error(503, "skill roots are unavailable: this router cannot read them")
        }
        let projected = ProfileProjector.project(
            profile: profile,
            store: extensions,
            roots: roots.inventories(),
            upstreamNames: deps.upstreams.map(\.name.string),
            clientsWithoutRoot: roots.clientsWithoutRoot()
        )
        return .json(200, Self.projectionValue(projected))
    }

    /// A named member that must be absent, null, or an array of strings.
    ///
    /// A member that is present and is something else is a **refusal**, not an empty list. "This
    /// profile selects nothing" and "this request said something this router does not understand"
    /// are different facts, and answering 200 to the second would record the first.
    static func namesMember(
        _ body: [JSONMember], _ key: String
    ) -> ProfileDocument.NamesReading {
        guard let value = body.first(where: { $0.key == JSString(key) })?.value else {
            return .names([])
        }
        if case .null = value { return .names([]) }
        guard let entries = value.asArray else {
            return .problem("\(key) must be an array of strings")
        }
        var names: [String] = []
        for (position, entry) in entries.enumerated() {
            guard let text = entry.asString?.string else {
                return .problem("\(key)[\(position)] must be a string")
            }
            names.append(text)
        }
        return .names(names)
    }
}
