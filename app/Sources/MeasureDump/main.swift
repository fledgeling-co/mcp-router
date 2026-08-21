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
import Foundation

#if MEASURE && os(macOS)

    import AppKit
    import MCPRouterKit
    import MCPRouterUI
    import SwiftUI

    /// A surface this tool knows how to render.
    enum Surface: String, CaseIterable {
        case servers
    }

    /// The drawn state to render it in.
    ///
    /// Four rather than one, because the mock draws four Servers frames and `DESIGN.md` §5 is that
    /// a populated-only screen is a third of a design. A breadth ledger filled against the ideal
    /// frame alone would report the three unhappy states as neither present nor absent, which is
    /// the omission the M23 brief calls an unaudited surface rather than a passed one.
    enum State: String, CaseIterable {
        case ideal
        case empty
        case loading
        case error

        var fixture: FixtureControlAPIClient.Scenario {
            switch self {
            case .ideal: .populated
            case .empty: .empty
            case .loading: .loading
            case .error: .offline
            }
        }

        /// Whether to poll before rendering.
        ///
        /// `loading` deliberately does not: its fixture is a request that never returns, so awaiting
        /// it would hang the tool rather than render the placeholder. The board reads a nil tracker
        /// state as loading, which is the state this frame is for.
        var polls: Bool { self != .loading }
    }

    struct Arguments {
        var surface: Surface = .servers
        var state: State = .ideal
        var appearance: ColorScheme = .dark
        var appearanceName = "dark"
        var width = 1280.0
        var height = 820.0
        var output = "planning/fidelity/servers.dump.json"
        /// How long the run loop is spun for the layout to settle, in seconds.
        var settle = 1.5
        /// Every argument this could not honour, in the words it would report them in.
        ///
        /// Collected rather than defaulted away. An unreadable `--surface` used to fall back to the
        /// only surface there is and an unreadable `--state` to `ideal`, so `--state loadng` wrote a
        /// dump of the ideal frame into `servers.loadng.json` and the tool exited 0 — a measurement
        /// of a surface nobody asked for, reported as a success. That is the same shape as a layer
        /// that could not run reading as agreement, one level below the gate, and the fix is the
        /// same: say what could not be honoured and exit 3.
        var rejected: [String] = []

        /// A number a frame can actually be laid out at.
        private static func positive(_ text: String) -> Double? {
            guard let value = Double(text), value > 0 else { return nil }
            return value
        }

        /// A duration. Zero is allowed: it means "read whatever one layout pass produced".
        private static func nonNegative(_ text: String) -> Double? {
            guard let value = Double(text), value >= 0 else { return nil }
            return value
        }

        static func parse(_ argv: [String]) -> Arguments {
            var out = Arguments()
            var i = 0
            while i < argv.count {
                let key = argv[i]
                let value = i + 1 < argv.count ? argv[i + 1] : nil
                i += out.apply(key, value) ? 2 : 1
            }
            return out
        }

        /// Applies one argument, or records why it could not be.
        ///
        /// - Returns: whether `value` was consumed, so the caller knows how far to step.
        private mutating func apply(_ key: String, _ value: String?) -> Bool {
            /// Reads `value` through `convert`, or records why it could not be and returns nil.
            func take<T>(_ expected: String, _ convert: (String) -> T?) -> T? {
                guard let value else {
                    rejected.append("\(key) was given no value")
                    return nil
                }
                guard let converted = convert(value) else {
                    rejected.append("\(key) '\(value)' is not \(expected)")
                    return nil
                }
                return converted
            }

            switch key {
            case "--surface":
                surface = take(Self.oneOf(Surface.allCases), Surface.init(rawValue:)) ?? surface
            case "--state":
                state = take(Self.oneOf(State.allCases), State.init(rawValue:)) ?? state
            case "--appearance":
                let parsed = take(Self.oneOf(Appearance.allCases), Appearance.init(rawValue:))
                appearance = parsed.map { $0 == .light ? .light : .dark } ?? appearance
                appearanceName = parsed?.rawValue ?? appearanceName
            case "--width":
                width = take("a positive number", Self.positive) ?? width
            case "--height":
                height = take("a positive number", Self.positive) ?? height
            case "--out":
                output = take("a path", Self.nonEmpty) ?? output
            case "--settle":
                settle = take("a non-negative number", Self.nonNegative) ?? settle
            default:
                rejected.append("'\(key)' is not an argument this tool takes")
                return false
            }
            return true
        }

        /// A path. The empty string is refused rather than treated as "wherever the default was".
        private static func nonEmpty(_ text: String) -> String? {
            text.isEmpty ? nil : text
        }

        /// The values an enum-backed argument accepts, in the words the refusal prints them in.
        private static func oneOf(_ cases: some Collection<some RawRepresentable<String>>) -> String {
            "one of " + cases.map(\.rawValue).joined(separator: ", ")
        }
    }

    /// The appearance to resolve every dynamic colour in. Named rather than compared as a string so
    /// an unreadable value is refused by the same path every other argument is.
    enum Appearance: String, CaseIterable {
        case light
        case dark
    }

    /// The rendered surface, wrapped in the harness's coordinate space.
    @MainActor
    struct MeasuredSurface: View {
        let surface: Surface
        let surfaceName: String
        let size: CGSize
        let shell: ShellModel
        let board: ServersBoardModel
        let appearance: ColorScheme

        var body: some View {
            Group {
                switch surface {
                case .servers:
                    ServersBoard(shell: shell, board: board)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.colorScheme, appearance)
            .measureSurface(surfaceName)
        }
    }

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

        let client = FixtureControlAPIClient(args.state.fixture)
        let shell = ShellModel(client: client)
        if args.state.polls { await shell.refresh(at: Date()) }
        let board = ServersBoardModel(client: client, tracker: shell.tracker)
        return render(args, shell: shell, board: board)
    }

    /// Hosts the surface, lets the layout settle, and writes the dump.
    ///
    /// Synchronous on purpose: `RunLoop.run(until:)` is unavailable from an async context, and the
    /// alternative — blocking a thread on a semaphore around a `Task` — is forbidden outright by
    /// `SWIFT_PRACTICES.md` §1 because it deadlocks the cooperative pool.
    @MainActor
    func render(_ args: Arguments, shell: ShellModel, board: ServersBoardModel) -> Int32 {
        SurfaceRecorder.shared.reset()

        let size = NSSize(width: args.width, height: args.height)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let host = NSHostingView(rootView: MeasuredSurface(
            surface: args.surface,
            surfaceName: "\(args.surface.rawValue).\(args.state.rawValue)",
            size: size, shell: shell, board: board, appearance: args.appearance
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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = URL(fileURLWithPath: args.output)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try encoder.encode(dump).write(to: url)
        } catch {
            FileHandle.standardError.write(Data("measure-dump: could not write \(url.path): \(error)\n".utf8))
            return 3
        }

        print("measure-dump: \(dump.allNodes.count) nodes, \(args.appearanceName), \(url.path)")
        for layer in dump.inconclusive {
            print("measure-dump: INCONCLUSIVE \(layer.layer) — \(layer.evidence)")
        }
        return 0
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
