#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// M37 — the control that switches a server off, and the three claims it makes ordinary.
    ///
    /// The state and every serving consequence of it are M29's and shipped. What did not exist was
    /// a route into `disabled` for an ordinary server: the only *disable* in the product was the
    /// held-change sheet's destructive footer button, reachable only while the router is holding a
    /// changed tool description, while the row's `Enable` reversed it from anywhere. A one-way
    /// reversal with no forward.
    ///
    /// **This file is the app half of the witness.** The router half is
    /// ``ControlPauseVectorTests``, and the two share `Vectors/pause-action.json` rather than a
    /// process, because no target links both `MCPRouterUI` and `RouterCore` — `Package.swift` keeps
    /// the app out of the router's dependency graph deliberately. Asserting only that the model
    /// sends `{"disabled":true}` would ask the recording client to confirm what the model handed
    /// it, which is the shape K5 measured at the router: deleting the whole `disabled` arm from
    /// `applyPatchFields` left 688 tests in 106 suites green, because every suite that mentioned
    /// the field started from a fixture already switched off.
    @Suite("M37 — the switch the inspector offers")
    struct ServersPauseAffordanceTests {
        typealias RecordingClient = ServersBoardRecordingClient

        // MARK: - Fixtures

        /// The five conditions a server can be in when an operator wants to switch it off.
        ///
        /// Four of them occupy the row's single action slot — enable, reset, review held change,
        /// sign in — which is why the row could not be the affordance's home and why this set is
        /// enumerated rather than exemplified.
        enum Condition: String, CaseIterable {
            case healthy, tripped, holdingAChange, unauthorised, alreadyDisabled
        }

        private static func server(_ condition: Condition, tools: Int = 7) throws -> MCPServer {
            var decoded = try FixtureControlAPIClient.decodeFixture(
                "server-stdio", as: MCPServer.self
            )
            decoded.name = "sift"
            decoded.tools = tools
            decoded.disabled = false
            decoded.placard = nil
            decoded.pendingChange = nil
            decoded.auth = ServerAuth(supported: false, authorized: false)
            switch condition {
            case .healthy:
                break
            case .tripped:
                decoded.placard = Placard(reason: "It failed twice")
            case .holdingAChange:
                decoded.pendingChange = PendingChange(seenAt: "2026-08-29T10:00:00.000Z", count: 2)
            case .unauthorised:
                decoded.auth = ServerAuth(supported: true, authorized: false)
            case .alreadyDisabled:
                decoded.disabled = true
            }
            return decoded
        }

        @MainActor
        private static func board(_ client: RecordingClient) -> ServersBoardModel {
            ServersBoardModel(
                client: client,
                tracker: ServerStateTracker(client: client, stream: nil),
                openURL: { _ in },
                chooseDirectory: { "/tmp/project" }
            )
        }

        // MARK: - The pinned request, read from the file the router half is driven with

        /// One row of the pinned corpus. Flat rather than nested inside `PauseVector` because the
        /// linter caps nesting at one level, and the two types are read separately anyway.
        struct PauseCase: Decodable {
            let id: String
            let method: String
            let body: String
            let servedAfter: Bool
        }

        struct PauseVector: Decodable {
            let cases: [PauseCase]
        }

        /// The file `RouterCoreTests` is driven with, read out of the tree rather than out of a
        /// bundle: it is a resource of the *other* test target, and this is the idiom this suite
        /// already uses to read `app/project.yml` and the board sources.
        ///
        /// `Pins/` rather than `Vectors/` because `Vectors/` is the parity corpus and
        /// `planning/pin-class-gate.py` holds every file in it to a generator importing a named
        /// export of the TypeScript reference. This pins a request the app composes; there is no
        /// export to import and no second implementation, so it is not a parity vector.
        static func vector() throws -> PauseVector {
            let text = try ShellTestSupport.repoFile(
                "app/Tests/RouterCoreTests/Pins/pause-action.json"
            )
            return try JSONDecoder().decode(PauseVector.self, from: Data(text.utf8))
        }

        static func body(_ id: String) throws -> String {
            let loaded = try Self.vector()
            return try #require(
                loaded.cases.first { $0.id == id }?.body,
                "the vector no longer carries a '\(id)' case, so this asserts nothing"
            )
        }

        /// Oracles 4 and 14 — what the control puts on the wire is what the router is driven with.
        ///
        /// The bytes are compared against the vector rather than against a literal written here.
        /// A literal in each suite is two suites that can drift apart while both stay green; the
        /// file is the one thing neither half owns.
        @MainActor
        @Test("the switch sends the pinned bytes, in both directions")
        func theSwitchSendsThePinnedBytes() async throws {
            let client = RecordingClient()
            client.patchResponse = try Self.server(.healthy)
            let board = Self.board(client)

            await board.setDisabled("sift", to: true)
            #expect(client.calls.last?.operation == "patch")
            #expect(client.calls.last?.server == "sift")
            #expect(try client.calls.last?.body == Self.body("disable"))

            await board.setDisabled("sift", to: false)
            #expect(try client.calls.last?.body == Self.body("enable"))
        }

        /// The vector has to disagree with itself across the two directions, or the test above
        /// passes on one string compared with itself.
        @Test("the two pinned bodies are different bytes")
        func thePinnedBodiesDiffer() throws {
            #expect(try Self.body("disable") != Self.body("enable"))
            #expect(try Self.vector().cases.allSatisfy { $0.method == "PATCH" })
        }

        // MARK: - The copy, over the whole set of conditions

        /// Oracle 7 — the brief says *pause*; the product says *disabled*, and this is what holds
        /// it there. `DESIGN.md` §6 asks for one name per state from one source, and the state
        /// already had four shipped spellings before this item added a fifth surface.
        @Test("no string this item adds says 'pause'")
        func theWordIsNeverPause() throws {
            var strings = [ServerInspector.disableToggleTitle]
            for disabled in [true, false] {
                strings.append(ServerInspector.disableToggleHelp(disabled: disabled))
            }
            for condition in Condition.allCases {
                let server = try Self.server(condition)
                strings.append(ServerInspector.headerDetail(server))
                strings.append(ServerInspector.projectScopeHelp(server))
                if let note = ServerInspector.toolsNotServedNote(server) { strings.append(note) }
            }
            #expect(strings.count == 14, "the population shrank; this sweep would look clean")
            for text in strings {
                #expect(
                    !text.lowercased().contains("pause"),
                    "a second word for one state reached a surface: \(text)"
                )
            }
            // The control: the sweep can see the word it is looking for.
            #expect("Pause this server".lowercased().contains("pause"))
        }

        /// Oracle 2, at runtime. The copy resolves for every condition, and says the same thing
        /// about the switch whichever else is true of the server — the switch is about the whole
        /// server, not about what is currently wrong with it.
        @Test("the switch's own copy is the same in all five conditions")
        func theCopyDoesNotVaryByCondition() throws {
            for condition in Condition.allCases {
                let server = try Self.server(condition)
                let help = ServerInspector.disableToggleHelp(disabled: server.disabled)
                #expect(!help.isEmpty)
                #expect(
                    help == ServerInspector.disableToggleHelp(disabled: condition == .alreadyDisabled),
                    "\(condition) changed the switch's sentence for a reason other than its state"
                )
            }
            #expect(
                ServerInspector.disableToggleHelp(disabled: true)
                    != ServerInspector.disableToggleHelp(disabled: false),
                "both directions read the same, so the sentence says nothing about the state"
            )
            #expect(ServerInspector.disableToggleTitle == "Disable this server")
        }

        // MARK: - Oracles 8, 9, 10 — the three claims the control makes ordinary

        @Test("the header withholds the count on a disabled server and reports it on a live one")
        func theHeaderWithholdsTheCount() throws {
            let off = try Self.server(.alreadyDisabled, tools: 41)
            let on = try Self.server(.healthy, tools: 41)
            #expect(ServerInspector.headerDetail(off) == "stdio · tools withheld")
            #expect(ServerInspector.headerDetail(on) == "stdio · 41 tools")
            // Withheld, not zeroed: the router still knows the count, so a `0` would claim the
            // server has no tools — which is the reading `ServerRowModel.tools` refuses for the
            // same figure one surface over.
            #expect(!ServerInspector.headerDetail(off).contains("0 tools"))
        }

        @Test("the scope toggle never claims a session sees a disabled server's tools")
        func theScopeHelpStopsClaimingReach() throws {
            for scoped in [true, false] {
                var off = try Self.server(.alreadyDisabled, tools: 41)
                var on = try Self.server(.healthy, tools: 41)
                off.projects = scoped ? ["/tmp/a"] : []
                on.projects = scoped ? ["/tmp/a"] : []
                #expect(
                    ServerInspector.projectScopeHelp(off)
                        == "No session sees its tools while it is disabled, whatever this is set to.",
                    "scoped=\(scoped): the disabled branch did not win"
                )
                #expect(
                    !ServerInspector.projectScopeHelp(off).contains("41"),
                    "scoped=\(scoped): the sentence still reports a reach"
                )
                #expect(ServerInspector.projectScopeHelp(on) != ServerInspector.projectScopeHelp(off))
            }
            var live = try Self.server(.healthy, tools: 41)
            live.projects = []
            #expect(ServerInspector.projectScopeHelp(live) == "Every session sees its 41 tools.")
        }

        @Test("the tool list carries the not-served sentence exactly when the server is disabled")
        func theToolListSaysWhenNothingIsServed() throws {
            for condition in Condition.allCases {
                let server = try Self.server(condition)
                let note = ServerInspector.toolsNotServedNote(server)
                #expect(
                    (note != nil) == server.disabled,
                    "\(condition): the note and the state disagree"
                )
            }
            let off = try Self.server(.alreadyDisabled)
            #expect(
                ServerInspector.toolsNotServedNote(off)
                    == "None of these is being served while this server is disabled."
            )
        }

        // MARK: - Oracles 1, 2, 5, 6 — the binding, which is a fact about the source

        /// There is no accessor for a `Toggle`'s label or binding on this host, so the binding is
        /// read the way spec-M29 oracle 12's button label is: out of the source. A function that
        /// returns the right string proves nothing if the view stopped calling it, and a mutation
        /// that inlines the literal would leave every test above green.
        @Test("the Behaviour section carries the switch, first, wired to the named copy")
        func theSwitchIsWiredIntoTheSection() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/ServerInspectorSections.swift"
            )
            let body = try ShellTestSupport.declarationBody(of: "var behaviour: some View", in: source)

            // The scoping has to actually scope, or every assertion below passes on an empty
            // string. Both ends are pinned.
            #expect(body.contains("section(\"Behaviour\")"), "the extracted body starts short")
            #expect(body.contains("board.signOut(server.name)"), "the extracted body stops short")

            // Oracle 6 — it reads the named functions rather than literals.
            #expect(body.contains("title: ServerInspector.disableToggleTitle"))
            #expect(
                body.contains(
                    "help: ServerInspector.disableToggleHelp(disabled: server.disabled)"
                )
            )
            #expect(
                !body.contains("\"Disable this server\""),
                "the switch carries a literal title, which is the drift this guards"
            )

            // Oracle 3 — bound to the wire field itself, not to its inverse.
            #expect(body.contains("isOn: server.disabled"))
            #expect(!body.contains("isOn: !server.disabled"), "the switch is backwards")

            // Oracle 4 — and it writes both ways from one closure rather than a fixed value.
            #expect(body.contains("Task { await board.setDisabled(server.name, to: off) }"))

            // Oracle 1 and 2 — unconditional and first, so it reaches a tripped, held or
            // unauthorised server whose row action slot is already taken.
            let beforeFirstToggle = try #require(
                body.components(separatedBy: "ToggleRow(").first,
                "the section declares no ToggleRow at all"
            )
            #expect(
                !beforeFirstToggle.contains("if ") && !beforeFirstToggle.contains("guard "),
                "the switch sits behind a condition, so some server cannot reach it"
            )
            let order = ["disableToggleTitle", "\"Keep warm\"", "\"Only load in named projects\""]
            var cursor = body.startIndex
            for marker in order {
                let found = try #require(
                    body.range(of: marker, range: cursor ..< body.endIndex),
                    "\(marker) is out of order, or gone, in the Behaviour section"
                )
                cursor = found.upperBound
            }

            // Oracle 5 — the switch takes the section's own reason (writing, router not
            // answering) and nothing else. A reason that fires on `server.disabled` here would
            // dim the one control that turns a server back on, on a server that is off.
            //
            // **Sliced to this toggle's own declaration**, and that is the arm's doing rather
            // than foresight: the first version of this assertion searched the whole section, so
            // `Keep warm`'s identical `disabledReason: disabledReason` satisfied it and PAU-4
            // passed against a switch that dimmed itself. The mutation is the only reason that
            // is known.
            let declaration = try Self.disableToggleDeclaration(in: body)
            #expect(
                declaration.contains("disabledReason: disabledReason"),
                "the switch's own reason is no longer the section's: \(declaration)"
            )
            #expect(
                !declaration.contains("server.disabled ?"),
                "the switch dims itself once it is on, so it cannot be switched back"
            )
            #expect(
                !declaration.contains(".disabled("),
                "the switch carries its own dim rather than the section's reason"
            )
        }

        /// The disable switch's own declaration, sliced out of the section.
        ///
        /// The section holds three `ToggleRow`s with the same argument labels, so an assertion
        /// over the whole body is satisfied by any of them. PAU-4 proved that is not theoretical:
        /// a switch that dimmed itself on `server.disabled` passed, because `Keep warm`'s
        /// `disabledReason: disabledReason` two declarations below still matched.
        static func disableToggleDeclaration(in body: String) throws -> String {
            let start = try #require(
                body.range(of: "title: ServerInspector.disableToggleTitle"),
                "the section no longer declares the switch at all"
            )
            let rest = body[start.upperBound...]
            let end = rest.range(of: "ToggleRow(")
            let slice = String(end.map { rest[..<$0.lowerBound] } ?? rest)
            // The slice has to end before the next control, or it is the whole section again.
            #expect(!slice.contains("Keep warm"), "the slice ran past the switch's declaration")
            #expect(slice.contains("isOn:"), "the slice stops before the switch's own arguments")
            return slice
        }

        /// The other two call sites, in the other file.
        @Test("the header and the tool list read the named copy rather than their own text")
        func theOtherTwoClaimsAreWired() throws {
            let header = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/ServerInspector.swift"
            )
            #expect(header.contains("Text(Self.headerDetail(server))"))
            #expect(
                !header.contains("\\(server.tools) tools"),
                "the header still interpolates a count it may not be entitled to claim"
            )

            let sections = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/ServerInspectorSections.swift"
            )
            let tools = try ShellTestSupport.declarationBody(of: "var tools: some View", in: sections)
            #expect(tools.contains("ServerInspector.toolsNotServedNote(server)"))
            #expect(tools.contains("FlowingTags(names: server.toolNames)"), "the extraction is short")
        }
    }
#endif
