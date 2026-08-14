import Foundation
import RouterCore

/// `mcp-router watch` — the launchd-fired one-shot that adopts servers out of `~/.claude.json`.
///
/// A thin argv shell over ``WatchRunner``, like every other verb here. `--verbose` is the only flag
/// the reference's arm accepts (`src/index.ts`), and the two lines it prints are the reference's, on
/// the reference's stream.
enum WatchVerb {
    static func run(_ arguments: [String]) async throws {
        let options = try Flags(arguments)
        // `emit` is supplied here rather than defaulted inside `RouterCore`: that target may never
        // name stdout, because it is linked into a process whose stdout is an MCP transport.
        try await WatchRunner(emit: { Out.print($0) }).run(verbose: options.has("verbose"))
    }
}
