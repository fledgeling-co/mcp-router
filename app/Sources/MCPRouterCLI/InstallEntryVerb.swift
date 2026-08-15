import Foundation
import RouterCore

/// `mcp-router install-entry` — the installer's `~/.claude.json` step, in the binary.
///
/// **This verb is deliberately absent from `Copy.usage`, and that is a compromise rather than a
/// necessity (P2-D2).** `cli-help` is a proven parity row, and `scripts/acceptance/parity-cli.sh`
/// compares `help`, `--help`, `-h` and the unknown-verb arm between the two binaries: a line added
/// to the Swift usage block reddens it. The alternatives were to ship no verb at all — leaving
/// R4-C's shell script with a library function it cannot call — or to amend the lane to ignore a
/// line, which is weakening a test to make a change pass. It is also true on its own terms that an
/// installer-internal step does not belong in a user-facing verb list, and that is the honest half
/// of the reason rather than the whole of it.
///
/// Thin by construction: `MCPRouterCLI` has no test target, so every rule lives in
/// ``ClaudeStagingEntry`` where `swift test` can reach it.
enum InstallEntryVerb {
    /// The one line this verb will say about itself.
    ///
    /// It exists because the verb is **absent from `Copy.usage`** (P2-D2) and rewrites ~268 KB of
    /// live session state. Without it, the single affordance a curious user has for asking what an
    /// undocumented command does — typing `--help` — would fall straight through `Flags`, which
    /// does not special-case it, and rewrite their real `~/.claude.json`. An accepted, destructive
    /// answer to a question is the worst shape available here.
    static let synopsis = """
    mcp-router install-entry [--port <n>] [--claude-json <path>]
      Point Claude Code at the router: add the mcp-router HTTP entry to ~/.claude.json,
      backing the file up first and keeping its permissions. Run by the installer.
    """

    static func run(_ arguments: [String]) throws {
        if arguments.contains("--help") || arguments.contains("-h") {
            Out.print(synopsis + "\n")
            return
        }
        let options = try Flags(arguments)
        let paths = ImportPaths()
        let path = options.value("claude-json") ?? paths.claudeJSON
        let port = try options.number("port") ?? RouterHome.defaultPort

        let outcome = try ClaudeStagingEntry.apply(
            atPath: path,
            port: port,
            fileSystem: RealFileSystem(),
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            now: Date()
        )

        switch outcome {
        case .noStagingFile:
            // The reference's rewrite step is inside `if [[ -f "$CLAUDE_JSON" ]]` and says nothing
            // at all when the file is absent (`install.sh:161`). This line is therefore THIS verb's,
            // not the installer's — said here so the next reader does not go looking for it in
            // install.sh, and harmless to parity because `install-claude-json` compares the file
            // rather than stdout.
            Out.print("no \(path) — nothing to point at the router\n")
        case let .rewritten(backup, addedEntry):
            Out.print("backed up \(path) -> \(backup)\n")
            if addedEntry {
                Out.print("added the router entry to \(path)\n")
            } else {
                // A non-object root: JavaScript's property write is a silent no-op, so the file was
                // re-stringified and nothing gained an entry. Claiming otherwise would be a false
                // sentence about the one file this verb exists to change.
                Out.print("\(path) is not a JSON object, so no entry could be added\n")
            }
        }
    }
}
