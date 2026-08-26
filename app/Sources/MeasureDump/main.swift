//
//  The driver for M23's measurement harness: renders one surface, reads what it reports about
//  itself, and writes the dump the conversion gate diffs.
//
//  It is an executable rather than a test for the reason `ControlDiff` is one: this needs a real
//  layout pass in a hosted view, and a unit suite that quietly does nothing when it cannot get one
//  reports the same success as a suite that measured everything.
//
//  It never comes to the front. `UI_VERIFICATION.md` rule 1 is binding on anything in this repo
//  that renders, and the activation policy below is what makes it true rather than hoped for: the
//  process is `.prohibited`, the window is never ordered front, and nothing is activated.
//
//  The vocabulary (`Surface`, `State`, `Appearance`), the command line (`Arguments`) and the view
//  (`MeasuredSurface`, `PreparedBoards`) sit in their own files beside this one. What is left here
//  is the run itself: parse, poll, host, settle, write.
//
import Foundation

#if MEASURE && os(macOS)

    import AppKit
    import MCPRouterKit
    import MCPRouterUI
    import SwiftUI

    @MainActor
    func run() async -> Int32 {
        let args = Arguments.parse(Array(CommandLine.arguments.dropFirst()))
        guard args.rejected.isEmpty else {
            let reasons = args.rejected.map { "              - " + $0 }.joined(separator: "\n")
            let refusal = """
            measure-dump: refusing to render, because these arguments could not be honoured:
            \(reasons)
                          Exiting 3 (inconclusive). Rendering the defaults instead would write a
                          dump of a surface nobody asked for under the name that was asked for.\n
            """
            FileHandle.standardError.write(Data(refusal.utf8))
            return 3
        }

        // `.prohibited` rather than `.accessory`: this process must never appear, never activate and
        // never take the key window from whatever the person at the machine is actually doing.
        NSApplication.shared.setActivationPolicy(.prohibited)

        let client = FixtureControlAPIClient(args.state.fixture(for: args.surface))
        // **The scratch domain, not the developer's own preferences.** `MeasuredSurface` already
        // hands the Settings window a scratch `ShellRestoration` for this reason; the popover reads a
        // preference off the *model* — whether the band may draw its `Approve` — so the model needs
        // the same treatment or the dump depends on which machine it ran on, which is not a
        // measurement of the surface.
        let shell = ShellModel(
            client: client,
            store: ShellRestoration(defaults: MeasuredSurface.scratchDefaults),
            inboxService: args.state.inbox(for: args.surface)
        )
        let boards = PreparedBoards(client: client)
        if args.state.polls {
            await shell.refresh(at: Date())
            if args.surface == .popover { await shell.inboxBoard.load() }
            await boards.read(args.surface)
        }
        return await render(args, shell: shell, client: client, boards: boards, readme: readme(args))
    }

    /// What the `.readme` surface draws, and the one place this tool will talk to a real router.
    ///
    /// Without `--document-from` it is M19's fixture, unchanged — which is what M23 measured and
    /// what every existing dump is a picture of. With it, the panel is driven by
    /// `ControlAPICapabilityDocumentSource` against a router that is running now, so what lands on
    /// the screen is a package's own bytes rather than a JSON file in this repository.
    ///
    /// A failure is rendered rather than swallowed. `CapabilityDocumentSheet` draws every
    /// `CapabilityDocumentError` as one of its own states, and the refusal frame is exactly what a
    /// server declaring no `cwd` produces — the state every upstream on this machine is in — so it
    /// is a subject worth capturing rather than an error to exit on.
    @MainActor
    func readme(_ args: Arguments) async -> CapabilityDocumentSheet.Content {
        guard let base = args.documentFrom else {
            return FixtureCapabilityDocumentSource.build()
                .map(CapabilityDocumentSheet.Content.document)
                ?? .unavailable(.notFound(capability: "trawl"))
        }
        let source = ControlAPICapabilityDocumentSource(
            client: LiveControlAPIClient(
                baseURL: base,
                session: URLSession(configuration: .ephemeral),
                // The token comes from the router's own file under `MCP_ROUTER_HOME`, which is how
                // `ControlProbe` is pointed at a throwaway router rather than the real one.
                store: InMemoryTokenStore(nil),
                tokenFile: RouterTokenFile()
            )
        )
        do {
            return try await .document(source.document(for: args.documentServer))
        } catch {
            return .unavailable(error)
        }
    }

    /// Hosts the surface, lets the layout settle, and writes the dump.
    ///
    /// Synchronous on purpose: `RunLoop.run(until:)` is unavailable from an async context, and the
    /// alternative — blocking a thread on a semaphore around a `Task` — is forbidden outright by
    /// `SWIFT_PRACTICES.md` §1 because it deadlocks the cooperative pool.
    @MainActor
    func render(
        _ args: Arguments,
        shell: ShellModel,
        client: any ControlAPIClient,
        boards: PreparedBoards,
        readme: CapabilityDocumentSheet.Content
    ) -> Int32 {
        SurfaceRecorder.shared.reset()

        let size = NSSize(width: args.width, height: args.height)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let host = NSHostingView(rootView: MeasuredSurface(
            surface: args.surface,
            surfaceName: "\(args.surface.rawValue).\(args.state.rawValue)",
            size: size, shell: shell, client: client, appearance: args.appearance, boards: boards,
            readme: readme
        ))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.appearance = NSAppearance(named: args.appearance == .dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()

        // SwiftUI resolves preferences on the run loop, not inside `layoutSubtreeIfNeeded`. Spinning
        // it briefly is what lets the instrumented views report. The node count is asserted below
        // rather than assumed, so a settle that was too short fails loudly instead of writing a
        // half-built tree.
        RunLoop.main.run(until: Date().addingTimeInterval(args.settle))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(args.settle))

        // The picture, before the node dump, because a run that renders nothing measurable should
        // still hand back what it drew — that image is how somebody sees *why* the recorder found
        // nothing.
        if let path = args.png, let failure = capture(host, to: path) { return failure }

        guard let dump = SurfaceRecorder.shared.dump(
            surface: "\(args.surface.rawValue).\(args.state.rawValue)",
            appearance: args.appearanceName, size: size
        ) else {
            FileHandle.standardError.write(Data("""
            measure-dump: the recorder collected no nodes for '\(args.surface.rawValue).\(args.state
                .rawValue)'.
                          That is inconclusive, not clean — the structure and geometry layers
                          produced nothing to read.\n
            """.utf8))
            return 3
        }

        let url = URL(fileURLWithPath: args.output)
        if let failure = writeDump(dump, to: url) { return failure }

        print("measure-dump: \(dump.allNodes.count) nodes, \(args.appearanceName), \(url.path)")
        for layer in dump.inconclusive {
            print("measure-dump: INCONCLUSIVE \(layer.layer) — \(layer.evidence)")
        }
        return 0
    }

    /// Writes a PNG of what the hosting view drew, and reports the exit code if it could not.
    ///
    /// Written off the view's own backing store: no window is ever ordered in, so there is no screen
    /// to take and nothing on top of the subject to photograph by mistake.
    ///
    /// - Returns: nil when the picture was written, or the code to exit with when it was not.
    @MainActor
    func capture(_ host: NSView, to path: String) -> Int32? {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            FileHandle.standardError.write(
                Data("measure-dump: the hosting view offered no backing store to capture\n".utf8)
            )
            return 3
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(
                Data("measure-dump: the view's backing store would not encode as PNG\n".utf8)
            )
            return 3
        }
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url)
            print("measure-dump: wrote \(rep.pixelsWide)x\(rep.pixelsHigh) to \(url.path)")
        } catch {
            FileHandle.standardError.write(
                Data("measure-dump: could not write \(url.path): \(error)\n".utf8)
            )
            return 3
        }
        return nil
    }

    /// Encodes the dump and writes it, and reports the exit code if it could not.
    ///
    /// The formatting is part of the artifact rather than a preference: the gate diffs these files,
    /// and sorted keys are what make two runs of the same surface comparable line by line.
    ///
    /// - Returns: nil when the dump was written, or the code to exit with when it was not.
    func writeDump(_ dump: some Encodable, to url: URL) -> Int32? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try encoder.encode(dump).write(to: url)
        } catch {
            FileHandle.standardError.write(
                Data("measure-dump: could not write \(url.path): \(error)\n".utf8)
            )
            return 3
        }
        return nil
    }

    await exit(run())

#else

    FileHandle.standardError.write(Data("""
    measure-dump: built without MEASURE, so the harness is not compiled in and nothing was measured.
                  Build with MCP_ROUTER_MEASURE=1 to switch it on. Exiting 3 (inconclusive) rather
                  than 0, because a tool that measured nothing must not report a clean surface.\n
    """.utf8))
    exit(3)

#endif
