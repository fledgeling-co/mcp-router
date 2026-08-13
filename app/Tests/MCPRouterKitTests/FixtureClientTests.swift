import Foundation
import Testing
@testable import MCPRouterKit

/// The double every later UI item will test against, held to the same completeness as the real one.
///
/// Two properties, and both matter more than they look. First, it answers **every** operation — a
/// double missing one sends the surface that needs it back to a live router, which is how a test
/// suite quietly acquires a dependency on a daemon. Second, each named scenario asserts a specific
/// observable, because "the double can produce all nine states" is a claim with nothing to check:
/// a scenario that returns the populated case is still a scenario.
@Suite("The fixture-backed double")
struct FixtureClientTests {
    // MARK: - A18: every operation, with no router running

    @Test("every operation on the protocol answers from recordings alone")
    func everyOperationAnswers() async throws {
        let subject = FixtureControlAPIClient(.populated)

        let servers = try await subject.servers()
        #expect(!servers.servers.isEmpty)

        _ = try await subject.server(named: "alpha")
        #expect(try await subject.usage().records.isEmpty == false)
        #expect(try await subject.usageSummary().servers.isEmpty == false)
        #expect(try await subject.heldChanges(for: "alpha").pending)
        #expect(try await subject.searchRegistry(query: "github", limit: 3).results.isEmpty == false)

        let added = try await subject.add(NewServer(name: "beta", command: "/bin/echo"))
        #expect(added.added == "beta")

        #expect(try await subject.remove("beta").removed == "beta")
        #expect(try await subject.reindex("alpha").name == "alpha")
        #expect(try await subject.patch(server: "alpha", ServerPatch(warm: true)).warm == true)
        #expect(try await subject.approvePendingChange(server: "alpha").server == "alpha")
        #expect(try await subject.beginAuthorization(for: "alpha").authorizationURL.isEmpty == false)
        #expect(try await subject.signOut("alpha").server == "alpha")
        #expect(try await subject.resetUsage().ok)
    }

    /// The double and the real client have to answer the *same* set of calls, or a surface written
    /// against the double meets a hole the moment it is pointed at a router.
    @Test("the double satisfies the same protocol the live client does")
    func doubleIsSubstitutable() async throws {
        let clients: [any ControlAPIClient] = try [
            FixtureControlAPIClient(.populated),
            LiveControlAPIClient(baseURL: #require(URL(string: "http://127.0.0.1:1")))
        ]
        // Compiling this array is the assertion: both conform. Only the double is exercised, since
        // the live one has nothing to talk to here.
        #expect(clients.count == 2)
        _ = try await clients[0].servers()
    }

    // MARK: - A19: a named scenario per state, each with its own observable

    @Test("the offline scenario refuses in the one way that has its own surface")
    func offlineIsRouterNotRunning() async {
        await #expect(throws: ControlAPIError.routerNotRunning) {
            _ = try await FixtureControlAPIClient(.offline).servers()
        }
    }

    @Test("the unauthorized scenario is a different refusal from offline")
    func unauthorizedIsDistinct() async {
        await #expect(throws: ControlAPIError.unauthorized) {
            _ = try await FixtureControlAPIClient(.unauthorized).servers()
        }
    }

    @Test("the error scenario carries the router's status, message and advice")
    func errorScenarioCarriesTheHint() async throws {
        do {
            _ = try await FixtureControlAPIClient(.error).servers()
            Issue.record("the error scenario returned successfully")
        } catch {
            guard case let .server(status, message, hint) = error else {
                Issue.record("expected .server, got \(error)")
                return
            }
            #expect(status == 422)
            #expect(message.contains("ENOENT"))
            #expect(hint?.contains("force=1") == true)
        }
    }

    @Test("the empty scenario is genuinely empty rather than merely small")
    func emptyIsEmpty() async throws {
        let response = try await FixtureControlAPIClient(.empty).servers()
        #expect(response.servers.isEmpty)
        #expect(response.pendingAuth == nil)
        #expect(try await FixtureControlAPIClient(.empty).heldChanges(for: "x").pending == false)
    }

    @Test("the partial scenario returns servers where exactly some carry a reason they failed")
    func partialNamesWhatDidNotArrive() async throws {
        let response = try await FixtureControlAPIClient(.partial).servers()
        let failed = response.servers.filter { $0.indexError != nil }

        #expect(!failed.isEmpty, "a partial state with nothing failed is just the populated state")
        #expect(
            failed.count < response.servers.count,
            "a partial state with nothing arrived is the error state"
        )
        for server in failed {
            #expect(
                server.indexError?.isEmpty == false,
                "a failure has to say why, next to the row it belongs to"
            )
        }
    }

    @Test("the overflow scenario returns a name too long for its column")
    func overflowIsActuallyLong() async throws {
        let response = try await FixtureControlAPIClient(.overflow).servers()
        let name = try #require(response.servers.first?.name)
        #expect(name.count > 40, "an overflow fixture that fits its column tests nothing")
    }

    @Test("the success scenario reports a write that worked")
    func successReportsSuccess() async throws {
        let result = try await FixtureControlAPIClient(.success).reindex("alpha")
        #expect(result.error == nil)
        #expect(result.tools > 0)
    }

    /// The loading state is the absence of an answer, so the double holds rather than returning
    /// something quickly. Asserted by cancelling it: a call that returns cannot be held.
    @Test("the loading scenario never answers, and gives up when cancelled")
    func loadingHolds() async throws {
        let task = Task { try await FixtureControlAPIClient(.loading).servers() }
        try await Task.sleep(for: .milliseconds(80))
        #expect(!task.isCancelled)
        task.cancel()

        let finished = await task.result
        if case .success = finished {
            Issue.record("the loading scenario answered; it is supposed to hold")
        }
    }

    @Test("the disabled state is a fact about the data, not a flag the double invents")
    func disabledIsDerivedFromTheData() async throws {
        // A placard is the router's own declaration that a server is inoperative, and it carries
        // the reason and the substitute. That is what a surface dims in place and explains — so
        // the scenario has to produce one, not merely be named after the condition.
        let response = try await FixtureControlAPIClient(.disabled).servers()
        let placarded = try #require(
            response.servers.first(where: { $0.placard != nil }),
            "the disabled scenario produced no server the router had declared inoperative"
        )
        let placard = try #require(placarded.placard)
        #expect(
            placard.reason == "under review while the upstream is rebuilt",
            "the reason has to be the router's, or a surface would be inventing one"
        )
        #expect(placard.substitute == "fixture-tools", "the advice about what to use instead was lost")

        // And nothing else in the populated case is disabled: the state has to be distinguishable.
        let normal = try await FixtureControlAPIClient(.populated).servers()
        #expect(normal.servers.allSatisfy { $0.placard == nil })

        // The other half of the same idea: nothing to approve is what turns the approve control
        // off, and it is readable from the response rather than from a flag.
        let none = try await FixtureControlAPIClient(.empty).heldChanges(for: "alpha")
        #expect(!none.pending, "with nothing pending, the control that approves it has its reason to be off")

        let held = try await FixtureControlAPIClient(.populated).heldChanges(for: "alpha")
        #expect(held.pending)
    }

    // MARK: - The three stream phases

    @Test("each stream scenario ends in the phase it is named for")
    func streamScenariosEndInTheirPhase() throws {
        let live = try FixtureControlAPIClient(.streamLive).streamEvents()
        #expect(live.first == .phase(.live))
        #expect(
            live.contains {
                if case .record = $0 {
                    true
                } else {
                    false
                }
            },
            "a live stream delivers records"
        )
        #expect(live.last != .phase(.disconnected))

        let reconnecting = try FixtureControlAPIClient(.streamReconnecting).streamEvents()
        #expect(reconnecting.last == .phase(.reconnecting))

        let disconnected = try FixtureControlAPIClient(.streamDisconnected).streamEvents()
        #expect(disconnected.last == .phase(.disconnected))
        #expect(
            disconnected.contains(.phase(.reconnecting)),
            "it must have tried before giving up, or the retry policy is not being represented"
        )
    }

    /// The completeness check for the scenario list itself: every case is reachable and asserted
    /// somewhere above. A case added later without a test fails here.
    @Test("every named scenario is covered by a test in this suite")
    func everyScenarioIsCovered() {
        let covered: Set<FixtureControlAPIClient.Scenario> = [
            .populated, .empty, .loading, .partial, .error, .success,
            .offline, .unauthorized, .overflow, .disabled,
            .streamLive, .streamReconnecting, .streamDisconnected
        ]
        let all = Set(FixtureControlAPIClient.Scenario.allCases)
        #expect(
            all == covered,
            "scenarios with no assertion of their own: \(all.subtracting(covered).map(\.rawValue).sorted())"
        )
        // The arithmetic is spelled out because it is what caught the gap: the count used to be 12
        // and read as "the nine states plus three phases", which balanced only because
        // `unauthorized` was silently standing in for the missing `disabled`.
        #expect(all.count == 13, "DESIGN.md §5's nine states, plus unauthorized, plus three stream phases")
    }
}
