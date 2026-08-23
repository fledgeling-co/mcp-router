import Foundation

/// What a harness's calls look like to the router when they arrive — and **who established it**.
///
/// The router does not observe which harness made a call. It observes the peer process:
/// ``LibProcPeerResolver`` reads `proc_name` of the pid holding the other end of the loopback
/// connection, and that string lands on ``UsageRecord/client``. Turning `claude` into *Claude Code*
/// is therefore a naming claim, not a measurement, and this repository already has the pattern for
/// one — ``HTTPCapability`` puts the provenance in the case rather than in a comment, so a reader
/// can tell a probe from an assumption without trusting any prose.
///
/// It matters here more than it does there, because the Insights board's calls-by-harness chart is
/// the one whose **zero row is the finding**: a harness at zero is one still using its own servers.
/// A zero produced by a wrong name would be a fabricated finding, which is worse than no chart.
public enum ClientProcessName: Sendable, Hashable {
    /// Established by inspecting the shipped artifact. `probe` is what was run so the claim can be
    /// re-taken, and `on` is the day, because an install is upgraded.
    case measured(name: String, probe: String, on: String)
    /// The process name is real and **does not identify one harness**: two harnesses share it, or
    /// it is a language runtime that anything can be. Counted against nobody.
    case ambiguous(name: String, reason: String)
    /// Nobody has looked. The honest answer, and the reason a row for such a harness reports no
    /// figure rather than a zero.
    case unknown

    /// The name to match a usage record's `client` against, or nil when no count may be attributed.
    ///
    /// `.ambiguous` deliberately returns nil even though it carries a name: the name is what makes
    /// it ambiguous, and matching on it would credit one harness with another's calls.
    public var attributableName: String? {
        switch self {
        case let .measured(name, _, _): name
        case .ambiguous, .unknown: nil
        }
    }

    /// Why this harness has no count, in the words a surface can show. Nil when it has one.
    public var unattributableReason: String? {
        switch self {
        case .measured: nil
        case let .ambiguous(name, reason): "calls arrive as \(name) — \(reason)"
        case .unknown: "nothing has established what this harness's calls look like to the router"
        }
    }
}

public extension ClientProcessName {
    /// The per-harness record, measured on 2026-08-22 with `file $(command -v <binary>)` and, for
    /// the two wrappers, by reading the script's own `exec` line.
    ///
    /// The measurement that matters is not "is the binary installed" but **what `proc_name` returns
    /// for the process that opens the socket**, which is the executable's own name. A shell wrapper
    /// that `exec`s a bundled interpreter is that interpreter, whatever `argv[0]` was set to.
    static func known(for client: MCPClient) -> ClientProcessName {
        switch client {
        case .claudeCode:
            .measured(
                name: "claude",
                probe: "file $(command -v claude) — Mach-O 64-bit executable arm64",
                on: "2026-08-22"
            )
        case .geminiCLI:
            .measured(
                name: "agy",
                probe: "file $(command -v agy) — Mach-O 64-bit executable arm64",
                on: "2026-08-22"
            )
        case .grokCLI:
            .measured(
                name: "grok",
                probe: "file $(command -v grok) — Mach-O 64-bit executable arm64",
                on: "2026-08-22"
            )
        // One binary, two harness entries. `~/.codex/config.toml` and `~/.chatgpt/config.toml` are
        // separate rows on the Harnesses board and the calls behind them are indistinguishable
        // here, so neither may claim the total and neither may be shown a zero.
        case .codexCLI, .chatGPTCLI:
            .ambiguous(
                name: "codex",
                reason: "the Codex and ChatGPT entries are the same binary, so a count cannot be split"
            )
        // A bash wrapper that runs `exec -a "$0" "$SCRIPT_DIR/node" … index.js`. `argv[0]` is the
        // wrapper's path and `proc_name` is the executable's, which is `node`.
        case .cursor:
            .ambiguous(
                name: "node",
                reason: "cursor-agent execs a bundled node, which every node MCP process shares"
            )
        // `#!/opt/homebrew/opt/node/bin/node`, so the same argument one spelling along.
        case .opencode:
            .ambiguous(
                name: "node",
                reason: "opencode is a node script, which every node MCP process shares"
            )
        case .claudeDesktop:
            .unknown
        }
    }
}
