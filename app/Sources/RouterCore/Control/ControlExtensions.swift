import Foundation

/// `GET /extensions`, and the three collections under it.
///
/// The shape is `/servers`' one level down, deliberately rather than a second idiom: a collection
/// answers `GET` and `POST`, an item answers `GET` and `DELETE`, an add that would collide is 409,
/// and an unknown item is `404 no <kind> named "x"` in the same words. What is new is only that the
/// collection is named by a kind — `/extensions/skills`, `/extensions/plugins`,
/// `/extensions/marketplaces` — because there are three of them and one `/servers`.
///
/// It **diverges from `src/control.ts`**, which answers every path here 404. Declared in
/// `planning/parity/surface.tsv` as the `div-r28-*` rows, in the same way `GET /harnesses` and
/// `GET /insights` are, so a Swift-only surface can never become an accidental divergence.
///
/// **Nothing here reads or writes Claude's own directories.** The inventory counts what the router
/// holds; a `~/.claude/skills` this router has never been given is not in it, and saying so is the
/// point — R30 is the item that moves anything across, and a count that quietly included Claude's
/// copies would report that work as already done.
extension ControlHandler {
    func routeExtensions(
        _ path: String, _ request: ControlAPIRequest, _ deps: ControlDeps
    ) -> ControlAPIResponse? {
        guard path == "/extensions" || path.hasPrefix("/extensions/") else { return nil }
        guard let store = deps.extensions else {
            // The shape `/harnesses` and `/registry/search` use when their one dependency is
            // absent: name the missing capability rather than answering an empty inventory, which
            // is indistinguishable from a router holding nothing.
            return .error(503, "extension storage is unavailable: this router has no store")
        }
        let rest = String(path.dropFirst("/extensions".count))
        if rest.isEmpty {
            guard request.method == "GET" else { return nil }
            return inventory(store, deps)
        }
        let segments = rest.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard let kindSegment = segments.first, let kind = ExtensionKind(
            rawValue: String(kindSegment)
        ) else {
            return .error(404, "no extension kind named \"\(segments.first.map(String.init) ?? "")\"")
        }
        switch segments.count {
        case 1: return collection(kind, store, request)
        case 2: return item(kind, String(segments[segments.startIndex + 1]), store, request)
        // Deeper than an item. Returning nil rather than 404 lets `handle` answer its own 405,
        // which is the honest reply for a path this router claims and does not route.
        default: return nil
        }
    }

    // MARK: - The collections

    private func collection(
        _ kind: ExtensionKind, _ store: any ExtensionStoring, _ request: ControlAPIRequest
    ) -> ControlAPIResponse? {
        switch request.method {
        case "GET": .json(200, Self.listingValue(store.list(kind)))
        case "POST": add(kind, store, request)
        default: nil
        }
    }

    private func item(
        _ kind: ExtensionKind,
        _ rawName: String,
        _ store: any ExtensionStoring,
        _ request: ControlAPIRequest
    ) -> ControlAPIResponse? {
        // Percent-decoded exactly where `ServerRoute` decodes a server name, and refused the same
        // way: a malformed escape is a 400 rather than a 404, because the router cannot say
        // whether a name it could not read exists.
        guard let name = rawName.removingPercentEncoding else {
            return .error(400, "URI malformed")
        }
        switch request.method {
        case "GET":
            guard let record = store.read(kind, name: name) else {
                return .error(404, "no \(kind.singular) named \"\(name)\"")
            }
            return .json(200, Self.recordValue(record))
        case "DELETE":
            return remove(kind, name, store)
        default:
            return nil
        }
    }

    // MARK: - Mutations

    private func add(
        _ kind: ExtensionKind, _ store: any ExtensionStoring, _ request: ControlAPIRequest
    ) -> ControlAPIResponse {
        let body = request.bodyObject
        let nameValue = body.first { $0.key == JSString("name") }?.value
        // `!b.name` — truthiness, matching `POST /servers`, so an empty string is "required"
        // rather than a valid name.
        guard let nameValue, nameValue.isTruthy, let name = nameValue.asString else {
            return .error(400, "name is required")
        }
        guard let filesValue = body.first(where: { $0.key == JSString("files") })?.value,
              let rawFiles = filesValue.asArray
        else {
            return .error(400, "files is required, as an array of {path, text}")
        }
        var files: [ExtensionFile] = []
        for entry in rawFiles {
            guard let path = entry.member("path")?.asString?.string, !path.isEmpty,
                  let text = entry.member("text")?.asString?.string
            else {
                return .error(400, "every file needs a non-empty path and a text string")
            }
            files.append(ExtensionFile(path: path, text: text))
        }
        switch store.add(kind, name: name.string, files: files) {
        case let .added(record):
            return .json(201, .object([
                JSONMember(key: JSString("added"), value: .string(name)),
                JSONMember(key: JSString("kind"), value: .string(JSString(kind.rawValue))),
                JSONMember(key: JSString("files"), value: .number(Double(record.files))),
                JSONMember(key: JSString("bytes"), value: .number(Double(record.bytes)))
            ]))
        case let .refused(refusal):
            return Self.refusalValue(refusal)
        }
    }

    private func remove(
        _ kind: ExtensionKind, _ name: String, _ store: any ExtensionStoring
    ) -> ControlAPIResponse {
        switch store.remove(kind, name: name) {
        case let .removed(path):
            .json(200, .object([
                JSONMember(key: JSString("removed"), value: .string(JSString(name))),
                JSONMember(key: JSString("kind"), value: .string(JSString(kind.rawValue))),
                // Where the bytes went, on the wire rather than in a log. A removal that says it
                // moved something aside without saying where is not reversible by anybody reading
                // the reply, and this route deletes nothing.
                JSONMember(key: JSString("restorePath"), value: .string(JSString(path)))
            ]))
        case let .refused(refusal):
            Self.refusalValue(refusal)
        }
    }
}
