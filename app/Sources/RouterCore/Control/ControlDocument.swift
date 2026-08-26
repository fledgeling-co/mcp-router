import Foundation

/// `GET /servers/:name/document` — the route that reads a package's own files.
///
/// The Swift half of the arm in `src/control.ts`, and a `control` row rather than a divergence:
/// both routers answer it, which is what lets `parity-manifest-check.sh`'s two-way derivation from
/// the reference speak for it.
///
/// **The package root is the server's declared `cwd` and nothing else.** It is the one directory a
/// wire type carries, and the router already uses it — it is what the child process is started in.
/// Deriving a root from `args[0]`'s directory was considered and refused: it is a guess about a
/// packaging convention this router does not otherwise use, and `DESIGN.md` §6 turns on where a
/// figure came from rather than on how plausible it is.
///
/// The response carries bytes and never a path, so nothing the app receives can be opened.
extension ControlHandler {
    func documentResponse(
        upstream: UpstreamConfig,
        name: JSString,
        deps: ControlDeps
    ) -> ControlAPIResponse {
        guard upstream.isStdio, let root = upstream.cwd, !root.isEmpty else {
            return refusal(
                404, "noPackageDirectory", name,
                "this server declares no directory, so there is no package to read documentation from"
            )
        }
        guard (try? deps.fileSystem.contentsOfDirectory(atPath: root)) != nil else {
            return refusal(
                404, "packageUnreadable", name,
                "the directory this server declares is not there: \(root)"
            )
        }

        var documents: [JSONMember] = []
        for entry in DocumentPackage.files {
            let path = URL(fileURLWithPath: root, isDirectory: true)
                .appendingPathComponent(entry.file).path
            guard let data = try? deps.fileSystem.readFile(atPath: path) else { continue }
            if DocumentPackage.documentOverCap(data.count) {
                return tooLarge(name, file: entry.file, actual: data.count)
            }
            // Lossy, matching `readFileSync(path, 'utf8')`. A strict decode would return nil on the
            // first malformed byte and drop a document the reference happily serves with a
            // replacement character in it — a divergence visible only on a package nobody thought
            // to test.
            let text = String(decoding: data, as: UTF8.self)
            documents.append(JSONMember(key: JSString(entry.tab), value: .string(JSString(text))))
        }
        guard !documents.isEmpty else {
            return refusal(
                404, "noDocuments", name,
                "the package carries no read me, changelog or capability list"
            )
        }

        let (images, refused) = resolveImages(documents: documents, root: root, deps: deps)
        return .json(200, .object([
            JSONMember(key: "server", value: .string(name)),
            JSONMember(key: "facts", value: .array(facts(upstream, deps.manifest.entry(named: name.string)))),
            // At most the three fixed keys, in tab order. A key that is absent means the package
            // published no such file, which is a different thing from an empty one — and the panel
            // says which document is missing rather than drawing a blank pane under a tab that
            // implies one exists.
            JSONMember(key: "documents", value: .object(documents)),
            JSONMember(key: "images", value: .array(images)),
            JSONMember(key: "refusedImages", value: .array(refused))
        ]))
    }

    /// Every reference the documents name, resolved once, then spent against the shared budget.
    ///
    /// Resolution and the cap arithmetic are two passes rather than one loop, because the budget is
    /// a property of the whole response: `DocumentPackage.imageCapDecisions` is the pure function a
    /// vector can pin, and a running total buried in a read loop is not.
    private func resolveImages(
        documents: [JSONMember],
        root: String,
        deps: ControlDeps
    ) -> (images: [JSONValue], refused: [JSONValue]) {
        var refused: [JSONValue] = []
        var readable: [(reference: String, data: Data, media: String)] = []
        var seen: Set<String> = []

        for document in documents {
            guard case let .string(text) = document.value else { continue }
            for reference in DocumentPackage.imageReferences(in: text.string) where !seen.contains(reference) {
                seen.insert(reference)
                switch DocumentPackage.resolve(reference, inPackageAt: root, fileSystem: deps.fileSystem) {
                case let .refused(refusal):
                    refused.append(Self.refusedImage(reference, refusal))
                case let .readable(path):
                    guard let data = try? deps.fileSystem.readFile(atPath: path),
                          let media = DocumentPackage.mediaType(
                              forExtension: "." + URL(fileURLWithPath: path).pathExtension
                          )
                    else {
                        refused.append(Self.refusedImage(reference, .notInPackage))
                        continue
                    }
                    readable.append((reference: reference, data: data, media: media))
                }
            }
        }

        var images: [JSONValue] = []
        let decisions = DocumentPackage.imageCapDecisions(sizes: readable.map(\.data.count))
        for (index, entry) in readable.enumerated() {
            switch decisions[index] {
            case .tooLarge:
                refused.append(Self.refusedImage(
                    entry.reference, .tooLarge(limit: DocumentPackage.Caps.imageBytes)
                ))
            case .budgetExhausted:
                refused.append(Self.refusedImage(entry.reference, .budgetExhausted))
            case .send:
                images.append(.object([
                    JSONMember(key: "reference", value: .string(JSString(entry.reference))),
                    JSONMember(key: "media", value: .string(JSString(entry.media))),
                    JSONMember(key: "base64", value: .string(JSString(entry.data.base64EncodedString())))
                ]))
            }
        }
        return (images, refused)
    }

    /// The facts strip, built only from what this router actually observed.
    ///
    /// `DESIGN.md` §6 forbids displaying a figure the router does not observe, and `spec-M30.md`
    /// answers the mock's five cells one at a time: `Kind` survives, and `Version`, `Licence`,
    /// `Runs in` and `Reads` are all derivations this router cannot make honestly — no wire type
    /// carries a version for an installed upstream, identifying a licence from a file's text is
    /// inference, nothing observes which harnesses could run a capability, and nothing observes
    /// what a child process reads.
    ///
    /// The two below `Kind` are here because they are observed, not because the mock drew them: the
    /// tool count is the length of the list this router connected and read, and the project list is
    /// the visibility restriction this router itself applies.
    private func facts(_ upstream: UpstreamConfig, _ entry: CachedServer?) -> [JSONValue] {
        var facts: [JSONValue] = [Self.fact("Kind", upstream.transport.rawValue)]
        if let entry, !entry.hasError {
            facts.append(Self.fact("Tools", String(entry.tools.count)))
        }
        if let projects = upstream.projects, !projects.isEmpty {
            facts.append(Self.fact("Served to", projects.joined(separator: ", ")))
        }
        return facts
    }

    private static func fact(_ label: String, _ value: String) -> JSONValue {
        .object([
            JSONMember(key: "label", value: .string(JSString(label))),
            JSONMember(key: "value", value: .string(JSString(value)))
        ])
    }

    private static func refusedImage(_ reference: String, _ refusal: DocumentPackage.Refusal) -> JSONValue {
        var members = [
            JSONMember(key: "reference", value: .string(JSString(reference))),
            JSONMember(key: "reason", value: .string(JSString(refusal.reason)))
        ]
        switch refusal {
        case let .remote(scheme):
            members.append(JSONMember(key: "scheme", value: .string(JSString(scheme))))
        case let .unsupportedType(ext):
            members.append(JSONMember(key: "extension", value: .string(JSString(ext))))
        case let .tooLarge(limit):
            members.append(JSONMember(key: "limit", value: .number(Double(limit))))
        case .absolutePath, .escapesPackage, .notInPackage, .budgetExhausted:
            break
        }
        return .object(members)
    }

    /// A refusal body: the sentence a surface renders, and the machine-readable reason beside it.
    ///
    /// Both, and not one or the other. A 404 with no `reason` is what an older router answers for a
    /// route it has never heard of, and the app reads that as version skew — so this route's own
    /// 404s must be tellable apart from it, and the `reason` member is the thing that tells them.
    private func refusal(_ status: Int, _ reason: String, _ name: JSString, _ message: String) -> ControlAPIResponse {
        .json(status, .object([
            JSONMember(key: "error", value: .string(JSString(message))),
            JSONMember(key: "reason", value: .string(JSString(reason))),
            JSONMember(key: "server", value: .string(name))
        ]))
    }

    private func tooLarge(_ name: JSString, file: String, actual: Int) -> ControlAPIResponse {
        let limit = DocumentPackage.Caps.documentBytes
        return .json(413, .object([
            JSONMember(key: "error", value: .string(JSString(
                "\(file) is \(actual) bytes, over the \(limit)-byte transport cap for one document"
            ))),
            JSONMember(key: "reason", value: .string("documentTooLarge")),
            JSONMember(key: "cap", value: .string("documentBytes")),
            JSONMember(key: "limit", value: .number(Double(limit))),
            JSONMember(key: "actual", value: .number(Double(actual))),
            JSONMember(key: "file", value: .string(JSString(file))),
            JSONMember(key: "server", value: .string(name))
        ]))
    }
}
