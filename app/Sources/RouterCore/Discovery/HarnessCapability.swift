import Foundation

/// Whether a harness can speak streamable HTTP MCP without a bridge — and **who established it**.
///
/// The provenance is in the case rather than in a comment, because this is the one fact in the
/// item that the router cannot observe for itself. `DESIGN.md` §6 forbids displaying a number the
/// router does not observe; this is not a number, and the rule behind that sentence — do not
/// present an inference as an observation — is honoured by making a reader able to tell a probe
/// from a document without trusting any prose.
///
/// It changes the **remedy**, never the state. A harness on a shim is on a shim whatever its
/// capability; what moves is whether the fix is "switch to the HTTP key" or "find out whether
/// there is one". That separation came out of the out-of-family review recorded in
/// `planning/evidence/R7-review-codex.md`.
public enum HTTPCapability: Sendable, Hashable {
    /// Established by probing the shipped artifact. `probe` is what was run or read, so the claim
    /// can be re-taken; `on` is the day it was taken, because a binary is upgraded.
    case measured(binary: String, probe: String, on: String)
    /// Taken on documentation. Weaker, and labelled so rather than presented as the first case.
    case documented(source: String)
    /// Not established. The honest answer for a harness nothing has probed, and the reason the
    /// remedy for a shim on such a harness is a question rather than an instruction.
    case unknown

    /// One line for a report, leading with the provenance rather than the verdict.
    public var summary: String {
        switch self {
        case let .measured(binary, probe, on):
            "speaks streamable HTTP — measured on \(binary), \(on): \(probe)"
        case let .documented(source):
            "speaks streamable HTTP — taken on documentation: \(source)"
        case .unknown:
            "streamable HTTP support not established"
        }
    }

    public var isEstablished: Bool {
        if case .unknown = self { return false }
        return true
    }
}

public extension HTTPCapability {
    /// The per-harness record, transcribed from `planning/specs/spec-R7.md` §1.2.
    ///
    /// Every entry names the instrument. `opencode` is `.unknown` and stays that way until
    /// somebody probes it (R7-C3) — a default of "probably yes, they all do" is exactly the
    /// fabrication this table exists to refuse.
    static func known(for client: MCPClient) -> HTTPCapability {
        switch client {
        case .claudeCode:
            .measured(
                binary: "claude",
                probe: "~/.claude.json carries type:http and the router serves this "
                    + "repository's own sessions through it",
                on: "2026-08-21"
            )
        case .codexCLI, .chatGPTCLI:
            .measured(
                binary: "codex 0.146.0",
                probe: "`codex mcp add <NAME> --url <URL>` documents a streamable HTTP MCP "
                    + "server; links rmcp-1.8.0 streamable_http_client",
                on: "2026-08-21"
            )
        case .cursor:
            .measured(
                binary: "cursor-agent 2026.08.11",
                probe: "shipped bundle selects type \"streamableHttp\" when the mcp.json entry carries a url",
                on: "2026-08-21"
            )
        case .geminiCLI:
            .measured(
                binary: "agy 1.1.17",
                probe: "embeds mcp.StreamableClientTransport from the Go MCP SDK; server "
                    + "config struct carries json:\"httpUrl\"",
                on: "2026-08-21"
            )
        case .grokCLI:
            .measured(
                binary: "grok 1.0.5",
                probe: "links rmcp-2.1.0 streamable_http_client and documents [mcp_servers.<name>] url",
                on: "2026-08-21"
            )
        case .claudeDesktop:
            .documented(source: "Anthropic's desktop MCP documentation; no binary was probed here")
        case .opencode:
            .unknown
        }
    }
}
