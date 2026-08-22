import Foundation
import Testing
@testable import RouterCore

/// What a harness's calls look like to the router, and who established it.
///
/// The suite exists because the Insights board's calls-by-harness chart is the one whose **zero row
/// is the finding**. A zero produced by a wrong name would be a fabricated finding, so the rule
/// under test is not "is the table right" but "does a row that cannot be counted refuse to show a
/// number at all".
@Suite("Client process attribution")
struct ClientProcessNameTests {
    @Test("every harness has an arm, so a new one cannot arrive unattributed by accident")
    func everyClientIsAnswered() {
        for client in MCPClient.allCases {
            let naming = ClientProcessName.known(for: client)
            switch naming {
            case let .measured(name, probe, on):
                #expect(!name.isEmpty)
                #expect(!probe.isEmpty, "a measured claim states the instrument")
                #expect(!on.isEmpty, "and the day, because an install is upgraded")
            case let .ambiguous(name, reason):
                #expect(!name.isEmpty)
                #expect(!reason.isEmpty)
            case .unknown:
                break
            }
        }
    }

    @Test("only a measured name may be counted against")
    func onlyMeasuredNamesAttribute() {
        #expect(ClientProcessName.known(for: .claudeCode).attributableName == "claude")
        #expect(ClientProcessName.known(for: .geminiCLI).attributableName == "agy")
        #expect(ClientProcessName.known(for: .grokCLI).attributableName == "grok")

        // Every one of these carries a real process name and still refuses to attribute, which is
        // the whole point: the name is what makes it ambiguous.
        for client in [MCPClient.cursor, .opencode, .codexCLI, .chatGPTCLI, .claudeDesktop] {
            let naming = ClientProcessName.known(for: client)
            #expect(naming.attributableName == nil, "\(client) must not claim a count")
            #expect(naming.unattributableReason != nil, "and must say why, in words a surface shows")
        }
    }

    @Test("two harness entries behind one binary are both refused, not split")
    func oneBinaryTwoEntries() {
        // `~/.codex/config.toml` and `~/.chatgpt/config.toml` are separate rows on the Harnesses
        // board and the calls behind them are indistinguishable here. Crediting either would
        // invent the split; crediting both would double the total.
        guard case let .ambiguous(codex, _) = ClientProcessName.known(for: .codexCLI),
              case let .ambiguous(chat, _) = ClientProcessName.known(for: .chatGPTCLI)
        else {
            Issue.record("both entries behind the codex binary must be ambiguous")
            return
        }
        #expect(codex == chat)
        #expect(codex == "codex")
    }

    @Test("a wrapper that execs an interpreter is that interpreter")
    func wrappersAreTheirInterpreter() {
        guard case let .ambiguous(cursor, _) = ClientProcessName.known(for: .cursor),
              case let .ambiguous(opencode, _) = ClientProcessName.known(for: .opencode)
        else {
            Issue.record("both node-backed harnesses must be ambiguous")
            return
        }
        #expect(cursor == "node")
        #expect(opencode == "node")
    }
}
