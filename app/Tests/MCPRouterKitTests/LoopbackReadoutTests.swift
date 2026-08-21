import Foundation
import Testing
@testable import MCPRouterKit

/// M27 — the sidebar foot's loopback line: where the address comes from, and what it may say.
///
/// The finding this closes is that the design of record draws the line on every board and the build
/// drew it on none. The two clauses that make restoring it correct rather than merely present are
/// both about *provenance*: the port is the observed one, and the address is composed in exactly one
/// place, so the two surfaces that render it cannot come to disagree.
@Suite("Sidebar foot — the loopback address")
struct LoopbackReadoutTests {
    /// The harness's own failure, not the product's. `ControlAPIError` stood here for one revision
    /// and an out-of-family review was right to object: that type means "the control API said
    /// something we could not use", and a test that cannot find a file on disk has not been told
    /// anything by a router.
    private enum OracleError: Error {
        case fileNotFound(String)
    }

    /// The repository root, found by walking up until a known path resolves. The same search
    /// `repoFile` does, hoisted so a caller that needs to enumerate rather than read one file can
    /// use it.
    private func repoRoot(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let marker = dir.appendingPathComponent("app/Sources/MCPRouterKit")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: marker.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw OracleError.fileNotFound("app/Sources/MCPRouterKit")
    }

    private func repoFile(_ relativePath: String, from filePath: String = #filePath) throws -> String {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = dir.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw OracleError.fileNotFound(relativePath)
    }

    // MARK: - The address is composed once, from the observed port

    @Test("the foot's address and Settings' endpoint are one composition")
    func oneCompositionForBothSurfaces() {
        let facts = SettingsPresentation.RouterFacts(
            port: 9999,
            idleMs: 300_000,
            since: "2026-08-14T00:46:50.436Z",
            home: URL(fileURLWithPath: "/tmp")
        )
        // The structural claim: the compact form the sidebar draws is literally inside the form
        // Settings draws, for the same port. Two independently written strings could agree today
        // and diverge on the next edit; these cannot.
        #expect(facts.endpoint.contains(LoopbackAddress.hostPort(9999)))
        #expect(facts.endpoint == "http://127.0.0.1:9999/mcp")
        #expect(LoopbackAddress.hostPort(9999) == "127.0.0.1:9999")
    }

    @Test("no surface spells the loopback address a second time")
    func addressIsSpelledInOnePlace() throws {
        // The failure mode this guards is not a wrong value — it is a second value. A view that
        // writes its own "127.0.0.1:\(port)" is a second place for the host to be wrong and a
        // second place a hard-coded port can be reintroduced, which is precisely how the mock's
        // `:8879` got there.
        //
        // **It walks the presentation trees rather than a list of four files, and it forbids a
        // composed address rather than the bare host.** Both narrowings were found by out-of-family
        // review and both are the same mistake: a guard against a literal appearing *somewhere*
        // that only looks where it has already appeared, and only in one spelling. A new board was
        // outside it, and so was `"http://127.0.0.1:8879"` inside it, because the opening quote
        // there precedes the scheme.
        //
        // Scope is the two trees that RENDER an address to a person. `RouterCore` and
        // `MCPRouterCLI` bind and dial the socket and are supposed to name the host; so is
        // `Control/LiveControlAPIClient`, whose default base URL is a dial target rather than a
        // reading. What is forbidden is `host:` — the composed form — so
        // `StateContainer`'s honest prose sentence "Nothing is listening on 127.0.0.1." stays
        // legal, which it should: it is a sentence about the loopback interface, not an endpoint
        // the user is being told to reach for.
        let root = try repoRoot()
        let composed = LoopbackAddress.host + ":"
        var offenders: [String] = []
        var scanned = 0
        for tree in ["app/Sources/MCPRouterUI", "app/Sources/MCPRouterKit/Shell"] {
            let base = root.appendingPathComponent(tree)
            let paths = try FileManager.default.subpathsOfDirectory(atPath: base.path)
                .filter { $0.hasSuffix(".swift") }
            #expect(!paths.isEmpty, "\(tree) enumerated no Swift files — the guard would be vacuous")
            for relative in paths where relative != "LoopbackReadout.swift" {
                scanned += 1
                let source = try String(
                    contentsOf: base.appendingPathComponent(relative),
                    encoding: .utf8
                )
                // Comments are stripped rather than exempted by name: several of these files
                // discuss the mock's `127.0.0.1:8879` in prose, and a guard carrying a list of them
                // would go stale the same way the four-file list did.
                let code = source
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { line -> Substring in
                        guard let comment = line.range(of: "//") else { return line }
                        return line[line.startIndex ..< comment.lowerBound]
                    }
                    .joined(separator: "\n")
                if code.contains(composed) { offenders.append("\(tree)/\(relative)") }
            }
        }
        // The one file allowed to compose it is outside both trees' exclusion by name; assert the
        // scan actually reached files, so a moved directory reports as a broken guard rather than
        // as a clean one.
        #expect(scanned > 10, "only \(scanned) files scanned — the presentation trees moved")
        #expect(LoopbackAddress.hostPort(8971).contains(composed))
        #expect(
            offenders.isEmpty,
            "these compose the loopback address themselves instead of naming LoopbackAddress: \(offenders)"
        )
    }

    @Test("a successful poll shows the port it observed, whatever that port is")
    func loadedShowsAnArbitraryObservedPort() async {
        // Every other `.loaded` case in this suite runs on the recording's own 8971, and an
        // out-of-family review was right that this leaves the one mutation that matters alive: a
        // view that hard-codes 8971 for a successful poll while honouring `state.port` on a stale
        // one passes every unit, UI and on-glass gate in this branch, and tells a user who moved
        // the port to reach for the wrong one. 51234 is neither the recording's port nor the mock's.
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated), stream: nil)
        let observed = try? await FixtureControlAPIClient(.populated).servers()
        guard var response = observed else {
            Issue.record("the populated recording did not decode")
            return
        }
        response.port = 51234
        await tracker.apply(poll: response)
        #expect(await LoopbackFoot.reading(for: tracker.state()) == .address("127.0.0.1:51234"))
    }

    @Test("the fixture router's own port reaches the line, not the mock's constant")
    func theObservedPortIsTheOneShown() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated), stream: nil)
        let response = try await FixtureControlAPIClient(.populated).servers()
        await tracker.apply(poll: response)
        let reading = await LoopbackFoot.reading(for: tracker.state())
        // 8971 is what the recording carries; 8879 is what `prototype.html` draws. A line that read
        // the constant would be wrong here and wrong on any machine that moved the port.
        #expect(reading == .address("127.0.0.1:\(response.port)"))
        #expect(reading.address?.hasSuffix(":8879") == false)
    }

    // MARK: - The four load states

    @Test("no poll has answered yet, so the line holds its place with no address")
    func loadingHoldsItsPlace() {
        let state = ServerStateTracker.TrackerState(load: .loading, stream: .notConfigured)
        #expect(LoopbackFoot.reading(for: state) == .awaitingFirstAnswer)
        #expect(LoopbackFoot.reading(for: nil) == .awaitingFirstAnswer)
    }

    @Test("nothing ever answered, so there is no address and the line is not drawn")
    func failedDrawsNothing() {
        let state = ServerStateTracker.TrackerState(load: .failed(.routerNotRunning), stream: .notConfigured)
        #expect(LoopbackFoot.reading(for: state) == .absent)
        #expect(LoopbackFoot.reading(for: state).address == nil)
    }

    @Test("a failed refresh does not erase the address the router answered on")
    func staleKeepsTheObservedAddress() {
        // `TrackerState.port` is documented as surviving a failure, for the reason the servers do:
        // a refresh that did not complete is not evidence that the router moved. The line follows
        // that rather than re-deciding it.
        // A port that is **neither** the recording's 8971 nor the mock's 8879, deliberately: with
        // either of those the assertion would also pass against a composition that had quietly
        // gone back to a constant, which is the one defect this whole element is about.
        let state = ServerStateTracker.TrackerState(
            load: .stale([], .transport(detail: "connection reset")),
            stream: .notConfigured,
            port: 51234
        )
        #expect(LoopbackFoot.reading(for: state) == .address("127.0.0.1:51234"))
    }

    // MARK: - What the line may say

    @Test("the line names no state, because ControlAPIError already owns those words")
    func theLineCarriesNoStatusWording() {
        // `DESIGN.md` §6: one wording per state, taken from one source. A foot reading "answering"
        // or "not answering" would be a second name for a state the readout above already renders
        // verbatim — and it would be a false one for `.unauthorized`, where the router answers 401
        // and the poll still fails.
        let strings = [
            LoopbackFootCopy.accessibilityLabel(address: "127.0.0.1:8971"),
            LoopbackAddress.hostPort(8971),
            LoopbackAddress.controlEndpoint(8971)
        ]
        for forbidden in [
            "answering", "connected", "disconnected", "online", "offline",
            "running", "reachable", "unreachable", "live", "down", "up"
        ] {
            for string in strings {
                #expect(
                    !string.lowercased().contains(forbidden),
                    "'\(string)' names a state ControlAPIError already words"
                )
            }
        }
    }

    @Test("the foot's view puts no status word on screen either")
    func theViewCarriesNoStatusWording() throws {
        // The suite above reads `LoopbackFootCopy` and `LoopbackAddress`, which an out-of-family
        // review pointed out is the wrong population for the claim: a literal `Text("connected")`
        // added to `SidebarFoot` is a status word on screen and invisible to a check that only
        // looks at the copy enum. This reads the view's own string literals instead.
        let source = try repoFile("app/Sources/MCPRouterUI/Shell/SidebarFoot.swift")
        // Comments carry the reasoning for this very rule and are full of these words, so the
        // population is string literals in code rather than the file.
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let comment = line.range(of: "//") else { return line }
                return line[line.startIndex ..< comment.lowerBound]
            }
            .joined(separator: "\n")
        var literals: [String] = []
        var rest = Substring(code)
        while let open = rest.firstIndex(of: "\"") {
            let after = rest.index(after: open)
            guard let close = rest[after...].firstIndex(of: "\"") else { break }
            literals.append(String(rest[after ..< close]))
            rest = rest[rest.index(after: close)...]
        }
        for forbidden in [
            "answering", "connected", "disconnected", "online", "offline",
            "reachable", "unreachable", "live", "down"
        ] {
            for literal in literals {
                #expect(
                    !literal.lowercased().contains(forbidden),
                    "SidebarFoot draws '\(literal)', which names a state ControlAPIError already words"
                )
            }
        }
    }

    @Test("a screen reader is told what the number is before it is told the number")
    func theLabelNamesWhatTheNumberIs() {
        // A35's rule, applied to the one element in the shell that is otherwise a bare numeral: a
        // reader hearing "127.0.0.1:8971" alone has to guess what it is an address of.
        #expect(
            LoopbackFootCopy.accessibilityLabel(address: "127.0.0.1:8971")
                == "Router endpoint, 127.0.0.1:8971"
        )
    }
}
