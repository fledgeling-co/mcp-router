import Foundation
import Testing
@testable import RouterCore

/// The standing constraints — A35, A36, A38 — as assertions rather than as commands somebody
/// remembered to run.
///
/// Each of these was previously verified by hand with `git diff` and `grep`, which is genuine
/// evidence for the moment it was run and no evidence at all afterwards. An out-of-family review
/// pointed out that the clauses ask for asserted checks and the branch had none; these are they.
/// They are product constraints, not style: the boundary between the app and the router, the SDK
/// pin, and the untouched TypeScript reference are the three things this item must not quietly
/// give up.
@Suite("The standing constraints, asserted")
struct StandingConstraintsTests {
    /// Runs a command from the repo root and returns its output, or nil if it could not run.
    ///
    /// A command that fails to launch must not read as a command that found nothing — those want
    /// opposite responses, and collapsing them is how "git is missing" becomes "the diff is clean".
    private static func run(_ arguments: [String]) throws -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = try RepoTree.root()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    /// A38. The TypeScript router stays the installed default until R4's parity gate passes, so
    /// this branch must not have touched it. Asserted against `main` rather than against a memory
    /// of having been careful.
    @Test("this branch changes nothing under src/, install.sh or package.json")
    func theReferenceIsUntouched() throws {
        guard let result = try Self.run(
            ["git", "diff", "--stat", "main", "--", "src/", "install.sh", "package.json"]
        ) else {
            Issue.record("git could not be run, so the reference is UNVERIFIED, not verified")
            return
        }
        guard result.status == 0 else {
            Issue.record("git diff against main failed (\(result.status)): \(result.output)")
            return
        }
        #expect(
            result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "the TypeScript reference changed on this branch:\n\(result.output)"
        )
    }

    /// A39's second half. The vectors are committed; `dist/` is not — a tracked `dist/` would make
    /// the generated reference part of the branch and the regeneration check meaningless.
    @Test("dist/ is not tracked")
    func distIsNotTracked() throws {
        guard let result = try Self.run(["git", "ls-files", "dist/"]) else {
            Issue.record("git could not be run, so this is UNVERIFIED")
            return
        }
        #expect(
            result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "dist/ is tracked:\n\(result.output)"
        )
    }

    /// A36. The Swift MCP SDK is pre-1.0 and its own README warns a minor bump may break the API,
    /// so the pin is exact and never a range. A range would let a `swift package update` change
    /// the protocol layer underneath this item without a commit saying so.
    @Test("the MCP SDK is pinned to an exact version, and no dependency is a range")
    func theSDKPinIsExact() throws {
        let manifest = try String(
            contentsOf: RepoTree.root().appendingPathComponent("app/Package.swift"),
            encoding: .utf8
        )
        #expect(
            manifest.contains(#"exact: "0.12.1""#),
            "the SDK pin is not the exact version this item was built against"
        )
        // The range spellings, named individually so the failure says which one appeared.
        for range in ["from:", "upToNextMajor", "upToNextMinor", "..<", "branch:", "revision:"] {
            #expect(
                !manifest.contains(".package(url:") || !manifest.contains(range),
                "a dependency uses \(range), which is a range or a moving target, not an exact pin"
            )
        }
    }

    /// A35. The Mac app talks to the router only over the loopback control API, and that boundary
    /// is what lets the router be swapped from TypeScript to Swift underneath without the app
    /// changing.
    ///
    /// The claim is exactly this and no more: it does not make it impossible for an app to read
    /// `servers.json`, it removes the ready-made way, so doing it becomes a visible addition to
    /// this file's expectations rather than an import nobody notices.
    @Test("neither app target links RouterCore, and neither app's sources name the config file")
    func theAppsCannotReachTheRouterCore() throws {
        let root = try RepoTree.root()
        let project = try String(
            contentsOf: root.appendingPathComponent("app/project.yml"), encoding: .utf8
        )
        #expect(
            !project.contains("RouterCore"),
            "app/project.yml names RouterCore, so an app target can link the router's data layer"
        )

        for target in ["MCPRouter", "MCPRouterIOS"] {
            let sources = root.appendingPathComponent("app/\(target)")
            for file in RepoTree.swiftFiles(under: sources) {
                let text = try String(contentsOf: file, encoding: .utf8)
                let reaching = "\(target)/\(file.lastPathComponent) names servers.json — the app "
                    + "is reaching past the control API to the router's own configuration"
                #expect(!text.contains("servers.json"), "\(reaching)")
                #expect(
                    !text.contains("import RouterCore"),
                    "\(target)/\(file.lastPathComponent) imports RouterCore"
                )
            }
        }
    }

    /// A35's other half: `RouterCore` really is its own library target, rather than source folded
    /// into the shared kit both apps link — which would satisfy the check above while giving the
    /// apps the code anyway.
    @Test("RouterCore is its own library target, separate from the kit the apps link")
    func routerCoreIsItsOwnTarget() throws {
        let manifest = try String(
            contentsOf: RepoTree.root().appendingPathComponent("app/Package.swift"),
            encoding: .utf8
        )
        #expect(manifest.contains(#".library(name: "RouterCore", targets: ["RouterCore"])"#))
        #expect(
            manifest.contains(#"name: "MCPRouterKit","#),
            "the shared kit target is gone, so what the apps link is no longer what this asserts"
        )
        // The kit is what both apps link, so the SDK must not reach it — a dependency there would
        // put a pre-1.0 package in the apps' graph, which is the thing the pin exists to contain.
        guard let kitRange = manifest.range(of: #"name: "MCPRouterKit","#),
              let nextTarget = manifest.range(
                  of: ".target(",
                  range: kitRange.upperBound ..< manifest.endIndex
              )
        else {
            Issue.record("could not locate the MCPRouterKit target block in Package.swift")
            return
        }
        let kitBlock = manifest[kitRange.upperBound ..< nextTarget.lowerBound]
        #expect(
            !kitBlock.contains(#".product(name: "MCP""#),
            "MCPRouterKit depends on the MCP SDK, so both apps now carry a pre-1.0 package"
        )
    }
}
