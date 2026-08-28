import Foundation
import RouterCore

/// `mcp-router ingest` — **R30**. Take what Claude acquired into the router, reversibly.
///
/// It sits beside `install-entry` and `harnesses`: a capability this binary adds with no arm in
/// `src/index.ts`, dispatched before ``MCPRouterCLI/dispatchReferenceVerb(_:)`` and absent from
/// `Copy.usage`, so `cli-help` keeps comparing four identical help arms at both binaries.
///
/// ## Two things it will not do
///
/// **It does not run itself.** With no `--apply` it prints the plan and touches nothing, and that is
/// the default because the plan is what a person needs before the move, not after it.
///
/// **It does not guess which tree it is pointed at.** Either `--claude-home <path>` names one, or
/// `--live` says the real one out loud. There is no default, so no invocation reaches
/// `~/.claude` by omission — which is the difference between a command that is safe and a command
/// that is safe as long as you remember the flag.
enum IngestVerb {
    /// Exit 0 when the run did what it said, 1 when something it attempted failed, 2 when the
    /// invocation or the environment could not support a run at all.
    ///
    /// A blocked extension is **not** a failure: it is this command's subject. A scan that reports
    /// four unidentifiable directories and moves nothing exits 0, because the report is the answer.
    static func run(_ arguments: [String]) throws {
        let options = try Flags(arguments)
        if options.has("undo") { return try undo(options) }
        let tree = try resolveTree(options)
        let home = RouterHome()
        let store = DiskExtensionStore(root: home.extensionsPath)
        let settleSeconds = try options.number("settle-seconds") ?? 60
        let settle = Double(settleSeconds) * 1000
        let scan = ClaudeExtensionScan.scan(
            tree: tree, store: store, settleMilliseconds: settle,
            now: SystemClock().nowMilliseconds
        )
        guard options.has("apply") else {
            Out.print(IngestReport.plan(scan, json: options.has("json"), settleMilliseconds: settle))
            return
        }
        let ingest = ExtensionIngest(store: store, tree: tree)
        let run = ingest.apply(
            scan.candidates, options: ExtensionIngest.Options(linkBack: options.has("link-back"))
        )
        Out.print(IngestReport.applied(run, scan: scan, json: options.has("json")))
        let failed = run.outcomes.contains { $0.state == .refused }
        if failed || run.settingsFailure != nil || run.manifestPath == nil { exit(1) }
    }

    // MARK: - Which tree

    static func resolveTree(_ options: Flags) throws -> ClaudeTree {
        if let path = options.value("claude-home"), !path.isEmpty {
            guard !options.has("live") else {
                throw CLIError("--claude-home and --live name two different trees; pass one")
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { throw CLIError("--claude-home \(path) is not a directory") }
            return ClaudeTree(root: path)
        }
        guard options.has("live") else {
            throw CLIError(
                "ingest needs a tree: --claude-home <path> for a copy, or --live for "
                    + "\(ClaudeTree().root). There is no default, because the default would be "
                    + "the real one"
            )
        }
        return ClaudeTree()
    }

    // MARK: - undo

    static func undo(_ options: Flags) throws {
        guard let path = options.value("undo"), !path.isEmpty else {
            throw CLIError("--undo needs the path of a run manifest")
        }
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8),
              let manifest = IngestManifestJSON.parse(text)
        else { throw CLIError("\(path) is not an ingest run manifest") }
        let store = DiskExtensionStore(root: manifest.storeRoot)
        let report = ExtensionIngestUndo.undo(
            manifest, store: store, fileSystem: RealFileSystem(), clock: SystemClock()
        )
        Out.print(IngestReport.undone(report, json: options.has("json")))
        if report.settingsFailure != nil || report.outcomes.contains(where: { $0.state == .skipped }) {
            exit(1)
        }
    }
}
