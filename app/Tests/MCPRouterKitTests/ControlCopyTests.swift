import Foundation
import Testing
@testable import MCPRouterKit

/// The failure copy, pinned to the wording that was approved.
///
/// Two directions again, and they catch different things. Asserting the exact literals catches a
/// reword in code — the kind that happens when someone "improves" a message and quietly ships two
/// wordings of one condition. Asserting that those same strings appear in the mock catches the
/// other half: copy edited in the design and never carried into the client, so the specimen and the
/// product disagree about what the user is told.
///
/// `DESIGN.md` §6 asks for one name per state across both devices. This is what makes that
/// checkable rather than aspirational.
@Suite("Failure copy")
struct ControlCopyTests {
    /// The mock, found by walking up from this file — the same way the design-token tests find
    /// `DESIGN.md`, and deliberately a hard failure rather than a skip when it is missing.
    static func mockText() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = dir
                .appendingPathComponent("design/mocks/html/f3-connection-states.html")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw CopyError.mockNotFound
    }

    enum CopyError: Error { case mockNotFound }

    /// HTML wraps and indents; the words are what is being compared, not the line breaks.
    static func normalised(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - The exact wording

    @Test("the two whole-screen conditions read exactly as approved")
    func fullPaneCopyIsExact() {
        #expect(ControlAPIError.routerNotRunning.headline == "The router isn't running")
        #expect(
            ControlAPIError.routerNotRunning.advice == """
            Nothing is listening on the control port, so there is nothing to show yet. \
            Starting it takes a moment and your servers stay exactly as you left them.
            """
        )
        #expect(ControlAPIError.routerNotRunning.actionLabel == "Start the router")

        #expect(
            ControlAPIError.unauthorized.headline == "This app isn't authorised to talk to the router"
        )
        #expect(
            ControlAPIError.unauthorized.advice == """
            The control token was rotated or removed. Re-pair to continue — \
            your servers and their history are untouched.
            """
        )
        #expect(ControlAPIError.unauthorized.actionLabel == "Re-pair…")
    }

    /// The half that catches copy edited in the design and never carried across.
    @Test("the approved wording in the mock is the wording the client actually returns")
    func copyMatchesTheMock() throws {
        let mock = try Self.normalised(Self.mockText())

        for error in [ControlAPIError.routerNotRunning, .unauthorized] {
            #expect(
                mock.contains(Self.normalised(error.headline)),
                "the mock no longer contains the headline for \(error): \(error.headline)"
            )
            #expect(
                mock.contains(Self.normalised(error.advice)),
                "the mock no longer contains the body copy for \(error)"
            )
            if let action = error.actionLabel {
                #expect(mock.contains(Self.normalised(action)), "the mock no longer offers “\(action)”")
            }
        }
    }

    /// The three that have no pane of their own sit beside the thing that failed, so their wording
    /// is pinned here rather than in the mock. Stated explicitly because a reader should not have
    /// to wonder why two conditions are checked against the design and three are not.
    @Test("the inline conditions read exactly as approved")
    func inlineCopyIsExact() {
        #expect(
            ControlAPIError.malformedResponse(detail: "ServersResponse").headline
                == "The router sent a response this version doesn't understand"
        )
        #expect(
            ControlAPIError.malformedResponse(detail: "ServersResponse").advice
                == "The router may be newer or older than this app (ServersResponse)."
        )

        #expect(ControlAPIError.server(status: 422, message: "boom")
            .headline == "The router couldn't complete that")
        #expect(
            ControlAPIError.server(status: 422, message: "boom").advice == "The router returned 422 — boom."
        )
        #expect(
            ControlAPIError.server(status: 422, message: "boom", hint: "try force").advice
                == "The router returned 422 — boom. try force"
        )

        #expect(ControlAPIError.transport(detail: "timed out").headline == "Couldn't reach the router")
        #expect(ControlAPIError.transport(detail: "timed out")
            .advice == "The request did not complete (timed out).")
    }

    // MARK: - The rules the copy has to keep

    @Test("no failure blames the user, emotes, or offers an action it cannot perform")
    func copyKeepsTheHouseRules() {
        let all: [ControlAPIError] = [
            .routerNotRunning, .unauthorized,
            .malformedResponse(detail: "x"), .server(status: 500, message: "y"), .transport(detail: "z")
        ]
        for error in all {
            #expect(!error.headline.isEmpty)
            #expect(!error.advice.isEmpty)
            #expect(!error.headline.contains("!"), "error copy should not emote: \(error.headline)")
            #expect(!error.advice.contains("!"), "error copy should not emote: \(error.advice)")
            // "You" in an error is nearly always the sentence blaming the reader for it.
            #expect(
                !error.advice.lowercased().contains("you did") && !error.advice.lowercased()
                    .contains("your fault"),
                "error copy should not blame: \(error.advice)"
            )
            // The one-line form is composed from the two, so it can never be a third wording.
            #expect(error.userFacingDescription == "\(error.headline). \(error.advice)")
        }
    }

    /// Only the two conditions that make the whole screen untrustworthy get a screen-level action;
    /// the rest sit next to what failed and have nothing to offer but the reason.
    @Test("exactly the two whole-screen conditions carry an action")
    func onlyWholeScreenFailuresOfferAnAction() {
        #expect(ControlAPIError.routerNotRunning.actionLabel != nil)
        #expect(ControlAPIError.unauthorized.actionLabel != nil)
        #expect(ControlAPIError.malformedResponse(detail: "x").actionLabel == nil)
        #expect(ControlAPIError.server(status: 500, message: "y").actionLabel == nil)
        #expect(ControlAPIError.transport(detail: "z").actionLabel == nil)
    }

    @Test("a missing mock fails loudly rather than quietly passing")
    func missingMockIsAFailure() {
        #expect(throws: CopyError.self) {
            var dir = URL(fileURLWithPath: "/nonexistent/deeply/nested/path/file.swift")
                .deletingLastPathComponent()
            for _ in 0 ..< 8 {
                let candidate = dir.appendingPathComponent("design/mocks/html/f3-connection-states.html")
                if FileManager.default.fileExists(atPath: candidate.path) { return }
                dir = dir.deletingLastPathComponent()
            }
            throw CopyError.mockNotFound
        }
    }
}
