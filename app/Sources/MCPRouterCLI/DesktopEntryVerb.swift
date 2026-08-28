import Foundation
import RouterCore

/// `mcp-router desktop-entry` — **R32**.
///
/// Registers the router with Claude Desktop, and reports the two things that registration does not
/// do. It sits beside `install-entry` and `harnesses`: dispatched ahead of the arm list that mirrors
/// `src/index.ts`, and absent from `Copy.usage` so `cli-help` keeps comparing four identical help
/// arms at both binaries.
///
/// **Dry run by default.** `--apply` is the only thing that writes, and it is never taken on the
/// caller's behalf. That is the item's rule rather than a nicety: the file is the owner's, Claude
/// Desktop may be running with a conversation in it, and the change does not reach a running Desktop
/// anyway — see ``ReloadPath/claudeDesktopConfigChange``, which this verb prints in both modes.
///
/// Thin by construction, like every verb here: `MCPRouterCLI` has no test target, so the rules live
/// in ``DesktopEntry`` and ``DesktopEntryWriter`` where `swift test` reaches them.
enum DesktopEntryVerb {
    static let synopsis = """
    mcp-router desktop-entry [--port <n>] [--config <path>]
                             [--bridge <absolute path>] [--bridge-arg <arg>]... [--apply]
      Register the router in Claude Desktop's config. Prints the diff and changes nothing
      unless --apply is given. Desktop's config takes a command to launch, never a url, so
      --bridge names the stdio-to-HTTP bridge it should run; the router does not ship one.
    """

    /// Exit 1 means the router was not registered and the output says why. Exit 0 covers both a dry
    /// run that produced a plan and an apply that landed, because in both the command answered the
    /// question it was asked.
    static func run(_ arguments: [String]) throws {
        if arguments.contains("--help") || arguments.contains("-h") {
            Out.print(synopsis + "\n")
            return
        }
        let options = try Flags(arguments)
        let port = try options.number("port") ?? RouterHome.defaultPort
        let path = options.value("config") ?? resolvedConfigPath()
        let fileSystem = RealFileSystem()

        Out.print("Claude Desktop\n  \(path)\n")
        Out.print("  reload: \(ReloadPath.claudeDesktopConfigChange.summary)\n\n")

        guard let bridge = bridge(from: arguments) else {
            return refuse(DesktopEntry.Refusal.noBridge(url: DesktopEntry.url(port: port)))
        }
        if let problem = bridge.problem(using: fileSystem) {
            return refuse(problem)
        }
        guard fileSystem.fileExists(atPath: path) else {
            return refuse(DesktopEntry.Refusal.noConfigFile(path: path))
        }

        let before: String
        let document: JSONValue
        do {
            let bytes = try fileSystem.readFile(atPath: path)
            // Failable rather than lossy: `String(decoding:as:)` turns an invalid byte into U+FFFD
            // and carries on, so a config that is not UTF-8 would be re-encoded on the way through
            // and the diff would show a change nobody made.
            guard let text = String(bytes: bytes, encoding: .utf8) else {
                return refuse(DesktopEntry.Refusal.unparseable(path: path, reason: "not UTF-8"))
            }
            before = text
            document = try JSONParser.parse(bytes)
        } catch {
            return refuse(DesktopEntry.Refusal.unparseable(path: path, reason: "\(error)"))
        }

        let rewritten: JSONValue
        do {
            rewritten = try DesktopEntry.rewritten(document, bridge: bridge)
        } catch let refusal as DesktopEntry.Refusal {
            return refuse(refusal)
        }

        let after = JSStringify.prettyTwoSpace(rewritten) + "\n"
        let diff = UnifiedDiff.between(before, after, fromLabel: path, toLabel: "\(path) (proposed)")
        report(diff: diff, dropped: DesktopEntry.conformance(of: DesktopEntry.entry(bridge: bridge)))

        guard options.has("apply") else {
            Out.print(
                diff.isEmpty
                    ? "Nothing to do: the entry is already there, byte for byte.\n"
                    : "Dry run — nothing was written. Re-run with --apply to make this change.\n"
            )
            return
        }
        try applying(document: after, toPath: path, fileSystem: fileSystem)
    }

    private static func applying(
        document: String, toPath path: String, fileSystem: RealFileSystem
    ) throws {
        let applied = try DesktopEntryWriter.apply(
            document: document,
            toPath: path,
            fileSystem: fileSystem,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            now: Date()
        )
        Out.print("backed up \(path) -> \(applied.backup)\n")
        Out.print(
            "wrote \(applied.bytesAfter) bytes (was \(applied.bytesBefore)) at mode "
                + String(format: "%04o", applied.mode) + "\n"
        )
        Out.print(
            "\nClaude Desktop will not pick this up on its own. Nothing here restarts it: it is "
                + "your foreground application and may be mid-conversation. When you are ready, "
                + "either use Developer ▸ Reload MCP Configuration or restart it — and note that "
                + "menu item was read out of the shipped bundle and has not been driven here, so "
                + "if it does not take, a restart is the path that is known to.\n"
        )
    }

    /// The diff and the schema verdict, printed together because they answer one question between
    /// them: what would change, and what of it Claude Desktop would actually read.
    private static func report(diff: String, dropped: DesktopEntry.Conformance) {
        if !dropped.dropped.isEmpty {
            Out.print(
                "  note: Desktop's schema does not declare "
                    + dropped.dropped.map { "\"\($0)\"" }.joined(separator: ", ")
                    + ", so it is discarded rather than rejected — the entry loads without it.\n\n"
            )
        }
        Out.print(diff.isEmpty ? "" : diff + "\n")
    }

    private static func refuse(_ refusal: DesktopEntry.Refusal) {
        Out.error("mcp-router: \(refusal.description)\n")
        exit(1)
    }

    /// `--bridge <path>` plus every `--bridge-arg <arg>` in the order they were given.
    ///
    /// Parsed here rather than through ``Flags``, which returns the **first** occurrence of a flag —
    /// correct for `--port`, and silently wrong for an argument list, where it would build a command
    /// line out of one of the arguments the user typed.
    static func bridge(from arguments: [String]) -> DesktopBridge? {
        guard let index = arguments.firstIndex(of: "--bridge"), index + 1 < arguments.count else {
            return nil
        }
        var args: [String] = []
        var cursor = arguments.startIndex
        while cursor < arguments.endIndex {
            if arguments[cursor] == "--bridge-arg", cursor + 1 < arguments.count {
                args.append(arguments[cursor + 1])
                cursor += 2
                continue
            }
            cursor += 1
        }
        return DesktopBridge(command: arguments[index + 1], arguments: args)
    }

    /// Where Claude Desktop's config lives, asked of the one type that knows.
    ///
    /// Split out so this verb reads the path from R7's inventory rather than spelling it, which is
    /// also what keeps `no-harness-config-writes.sh` rule 2 meaningful here: the file that resolves
    /// a harness path is not the file that writes one.
    private static func resolvedConfigPath() -> String {
        ClientConfigs.path(
            for: .claudeDesktop,
            homeDirectory: RouterHome.resolvedHomeDirectory(),
            projectDirectory: nil
        ) ?? ""
    }
}
