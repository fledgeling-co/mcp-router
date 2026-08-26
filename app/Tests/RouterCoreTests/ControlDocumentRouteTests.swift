import Foundation
import Testing
@testable import RouterCore

/// `GET /servers/:name/document`, **through `ControlHandler.handle`**.
///
/// Through the handler rather than by calling `documentResponse`, for the reason
/// `ControlBoardRoutesTests` gives in its own words: a missing dispatch arm is not a broken
/// function, and a test that calls the function cannot fail when the arm is deleted.
///
/// This route is a new surface on a trust boundary, so the refusals are tested as hard as the
/// success. `Skill.path` and a server's `cwd` are both real resolved paths on disk, and a document
/// naming `../../../etc/passwd` is the request this route exists to refuse.
@Suite("M30 · the document route")
struct ControlDocumentRouteTests {
    typealias Support = ControlAuthSupport

    /// A package on disk, torn down by the caller.
    struct Package {
        let root: URL

        static func make(
            readMe: String? = nil,
            changelog: String? = nil,
            capabilities: String? = nil,
            images: [(String, Int)] = []
        ) throws -> Package {
            let manager = FileManager.default
            let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("m30-\(UUID().uuidString)", isDirectory: true)
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            for (name, text) in [
                ("README.md", readMe), ("CHANGELOG.md", changelog), ("CAPABILITIES.md", capabilities)
            ] {
                guard let text else { continue }
                try Data(text.utf8).write(to: root.appendingPathComponent(name))
            }
            for (name, bytes) in images {
                let file = root.appendingPathComponent(name)
                try manager.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data(repeating: 0x41, count: bytes).write(to: file)
            }
            return Package(root: root)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A one-server config declared with `cwd`, which is the package root the route reads.
    private static func config(cwd: String?, projects: [String] = []) -> String {
        let cwdMember = cwd.map { #""cwd": "\#($0)","# } ?? ""
        let projectMember = projects.isEmpty
            ? ""
            : #""projects": [\#(projects.map { "\"\($0)\"" }.joined(separator: ","))],"#
        return """
        { "mcpServers": { "pkg": {
            "command": "node", "args": ["x.js"], \(cwdMember)\(projectMember) "env": {}
        } } }
        """
    }

    private static func answer(_ path: String, _ deps: inout ControlDeps) async -> (Int, String) {
        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: "GET", encodedPath: path, query: [], headers: [], body: nil
            ),
            &deps
        )
        guard case let .bytes(bytes) = response.body else { return (response.status, "") }
        // swiftlint:disable:next optional_data_string_conversion
        return (response.status, String(decoding: bytes, as: UTF8.self))
    }

    private static func deps(for package: Package, projects: [String] = []) throws -> ControlDeps {
        try Support.makeDeps(
            fileSystem: RealFileSystem(),
            config: config(cwd: package.root.path, projects: projects)
        )
    }

    // MARK: - The success path

    @Test("A1 — the package's own three files reach the wire, keyed by tab")
    func servesThePackagesFiles() async throws {
        let package = try Package.make(
            readMe: "# pkg\n\nWhat it does.",
            changelog: "1.2.0 — fixed a thing.",
            capabilities: "| tool | what |\n| --- | --- |\n| a | b |"
        )
        defer { package.remove() }
        var deps = try Self.deps(for: package)

        let (status, body) = await Self.answer("/servers/pkg/document", &deps)
        #expect(status == 200)
        #expect(body.contains(##""readMe":"# pkg\n\nWhat it does.""##))
        #expect(body.contains("\"changelog\":\"1.2.0 \u{2014} fixed a thing.\""))
        #expect(body.contains(#""capabilities":"#))
        // The package root is never sent. The app may not open a file, so a payload carrying a path
        // would be handing it the one thing A36 exists to keep out of reach.
        #expect(!body.contains(package.root.path))
    }

    @Test("A2 — the facts strip carries only what the router observed")
    func factsAreObservedOnly() async throws {
        let package = try Package.make(readMe: "# pkg")
        defer { package.remove() }
        var deps = try Self.deps(for: package, projects: ["/Users/x/Dev/one"])

        let (status, body) = await Self.answer("/servers/pkg/document", &deps)
        #expect(status == 200)
        #expect(body.contains(#"{"label":"Kind","value":"stdio"}"#))
        #expect(body.contains(#"{"label":"Served to","value":"/Users/x/Dev/one"}"#))
        // The four the mock draws and this router cannot observe. `spec-M30.md` answers each by
        // name; this is the assertion that keeps the answer from being re-litigated in code.
        for absent in ["Version", "Licence", "Runs in", "Reads"] {
            #expect(!body.contains(#""label":"\#(absent)""#), "\(absent) is not observed")
        }
        // The manifest holds no entry for this server, so there is no tool count to state. An
        // absent fact, not a zero — a zero would be a figure nobody measured.
        #expect(!body.contains(#""label":"Tools""#))
    }

    @Test("A3 — an image inside the package travels as bytes")
    func imagesTravelAsBytes() async throws {
        let package = try Package.make(
            readMe: "# pkg\n\n![figure](docs/a.png)", images: [("docs/a.png", 8)]
        )
        defer { package.remove() }
        var deps = try Self.deps(for: package)

        let (status, body) = await Self.answer("/servers/pkg/document", &deps)
        #expect(status == 200)
        #expect(body.contains(#""reference":"docs/a.png""#))
        #expect(body.contains(#""media":"image/png""#))
        // Eight 0x41 bytes, base64. Asserted as the value rather than as "some base64", so a route
        // that sent an empty string for every image would fail here.
        #expect(body.contains(#""base64":"QUFBQUFBQUE=""#))
    }

    // MARK: - The refusals

    @Test("A4 — a reference climbing out of the package is refused, with no bytes")
    func traversalIsRefused() async throws {
        let package = try Package.make(
            readMe: """
            # pkg

            ![up](../../../../etc/passwd)

            ![abs](/etc/passwd)

            ![remote](https://example.com/a.png)

            ![deep](docs/../../escape.png)
            """
        )
        defer { package.remove() }
        var deps = try Self.deps(for: package)

        let (status, body) = await Self.answer("/servers/pkg/document", &deps)
        #expect(status == 200)
        #expect(body.contains(#""reference":"../../../../etc/passwd","reason":"escapesPackage""#))
        #expect(body.contains(#""reference":"/etc/passwd","reason":"absolutePath""#))
        #expect(body.contains(
            #""reference":"https://example.com/a.png","reason":"remote","scheme":"https""#
        ))
        #expect(body.contains(#""reference":"docs/../../escape.png","reason":"escapesPackage""#))
        // The whole point: nothing was read. An empty images array is the observable form of that.
        #expect(body.contains(#""images":[]"#))
    }

    @Test("A5 — a server declared without a directory says so under its own reason")
    func noPackageDirectory() async throws {
        var deps = try Support.makeDeps(
            fileSystem: RealFileSystem(), config: Self.config(cwd: nil)
        )
        let (status, body) = await Self.answer("/servers/pkg/document", &deps)
        #expect(status == 404)
        #expect(body.contains(#""reason":"noPackageDirectory""#))
        #expect(body.contains("this server declares no directory"))
    }

    @Test("A5 — a directory that is gone is a different reason from one that never existed")
    func packageUnreadable() async throws {
        var deps = try Support.makeDeps(
            fileSystem: RealFileSystem(),
            config: Self.config(cwd: "/tmp/m30-no-such-directory-\(UUID().uuidString)")
        )
        let (status, body) = await Self.answer("/servers/pkg/document", &deps)
        #expect(status == 404)
        #expect(body.contains(#""reason":"packageUnreadable""#))
    }

    @Test("A5 — a package with none of the three files says which is missing, not that it failed")
    func noDocuments() async throws {
        let package = try Package.make()
        defer { package.remove() }
        var deps = try Self.deps(for: package)

        let (status, body) = await Self.answer("/servers/pkg/document", &deps)
        #expect(status == 404)
        #expect(body.contains(#""reason":"noDocuments""#))
        #expect(body.contains("no read me, changelog or capability list"))
    }

    @Test("A6 — a document over the transport cap refuses 413 and names the cap it hit")
    func documentOverTheCap() async throws {
        let package = try Package.make(
            readMe: String(repeating: "x", count: DocumentPackage.Caps.documentBytes + 1)
        )
        defer { package.remove() }
        var deps = try Self.deps(for: package)

        let (status, body) = await Self.answer("/servers/pkg/document", &deps)
        #expect(status == 413)
        #expect(body.contains(#""reason":"documentTooLarge""#))
        // Which cap, its value, what was actually there, and which file. "Too large" alone tells a
        // reader nothing they could act on, and `MarkdownLimits` is a different cap in a different
        // process — naming it is what keeps the two from being confused.
        #expect(body.contains(#""cap":"documentBytes""#))
        #expect(body.contains(#""limit":524288"#))
        #expect(body.contains(#""actual":524289"#))
        #expect(body.contains(#""file":"README.md""#))
    }

    @Test("A6 — one oversized image is refused and the document still travels")
    func imageOverTheCap() async throws {
        let package = try Package.make(
            readMe: "# pkg\n\n![big](big.png)\n\n![small](small.png)",
            images: [
                ("big.png", DocumentPackage.Caps.imageBytes + 1),
                ("small.png", 4)
            ]
        )
        defer { package.remove() }
        var deps = try Self.deps(for: package)

        let (status, body) = await Self.answer("/servers/pkg/document", &deps)
        #expect(status == 200)
        #expect(body.contains(#""reference":"big.png","reason":"tooLarge","limit":2097152"#))
        // The small one still arrives: an oversized image is refused on its own terms and does not
        // spend the shared budget, which is what stops one big figure hiding every other.
        #expect(body.contains(#""reference":"small.png""#))
        #expect(body.contains(#""base64":"QUFBQQ==""#))
    }

    @Test("A6 — once the shared image budget is spent, the next figure is refused for the budget")
    func imageBudgetExhausted() async throws {
        // Four figures each exactly at the per-image cap spend the shared budget to the byte, so
        // the fifth is refused by the budget rather than by its own size — which is the one caps
        // decision the vectors exercise and no route test did. Reaching it needs the real budget
        // spent, so this test is deliberately the heavy one in the suite.
        let full = DocumentPackage.Caps.imageBytes
        let package = try Package.make(
            readMe: "# pkg\n\n![a](a.png)\n\n![b](b.png)\n\n![c](c.png)\n\n![d](d.png)\n\n![e](e.png)",
            images: [("a.png", full), ("b.png", full), ("c.png", full), ("d.png", full), ("e.png", 4)]
        )
        defer { package.remove() }
        var deps = try Self.deps(for: package)

        let (status, body) = await Self.answer("/servers/pkg/document", &deps)
        #expect(status == 200)
        // Its own reason, not `tooLarge`: four bytes is nowhere near the per-image cap, and a
        // reader told "too large" about a 4-byte figure would go looking in the wrong place.
        #expect(body.contains(#""reference":"e.png","reason":"budgetExhausted""#))
        // The four that fit still travel, so exhaustion truncates rather than failing the response.
        #expect(body.contains(#""reference":"a.png""#))
        #expect(body.contains(#""reference":"d.png""#))
        #expect(!body.contains(#""base64":"QUFBQQ==""#))
    }

    @Test("the unknown-server 404 still has no reason, so version skew stays tellable apart")
    func unknownServerCarriesNoReason() async throws {
        let package = try Package.make(readMe: "# pkg")
        defer { package.remove() }
        var deps = try Self.deps(for: package)

        let (status, body) = await Self.answer("/servers/nope/document", &deps)
        #expect(status == 404)
        #expect(body.contains(#"no server named \"nope\""#))
        #expect(!body.contains(#""reason""#))
    }

    @Test("the route is GET-only; anything else falls through to the 405")
    func onlyGET() async throws {
        let package = try Package.make(readMe: "# pkg")
        defer { package.remove() }
        var deps = try Self.deps(for: package)

        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: "DELETE", encodedPath: "/servers/pkg/document", query: [],
                headers: [(name: "x-mcpr-token", value: Support.token)], body: nil
            ),
            &deps
        )
        #expect(response.status == 405)
    }
}
