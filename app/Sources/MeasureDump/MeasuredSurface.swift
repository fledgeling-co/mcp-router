//
//  The view the harness hosts, and the board models read before it exists.
//
//  Split out of `main.swift` when that file passed 400 lines. This is everything SwiftUI sees: what
//  each surface builds, and the pre-read that stops a board being measured mid-load.
//
#if MEASURE && os(macOS)

    import Foundation
    import MCPRouterKit
    import MCPRouterUI
    import SwiftUI

    /// The board models M22's two surfaces are rendered from, built and **read** before the view
    /// exists.
    ///
    /// Their own load runs from `.task`, and a hosting view in a window that is never ordered in
    /// does not reliably fire one — the first run of this measured nine nodes, which is the header
    /// and a loading skeleton, and wrote it out as the ideal frame. The Servers surface never had
    /// the problem because `ShellModel.refresh` is awaited in `run()` before anything renders; this
    /// is the same arrangement for boards that own their own read.
    ///
    /// `loading` is deliberately **not** pre-read: its whole subject is the frame before an answer,
    /// and the fixture for it never returns.
    @MainActor
    struct PreparedBoards {
        var harnesses: HarnessesBoardModel
        var insights: InsightsBoardModel

        init(client: any ControlAPIClient) {
            harnesses = HarnessesBoardModel(client: client)
            insights = InsightsBoardModel(client: client)
        }

        func read(_ surface: Surface) async {
            switch surface {
            case .harnesses: await harnesses.load()
            case .insights: await insights.load()
            // `.readme` joins these rather than loading: `CapabilityDocumentSheet` is built from
            // `FixtureCapabilityDocumentSource` synchronously in `body`, so there is no board model
            // to poll. It was added to `Surface` without being added here, and because every other
            // switch in this file uses a wildcard, this one was the only place the omission could
            // surface — as `switch must be exhaustive`, which took the whole MCP_ROUTER_MEASURE
            // build down and with it every rung that depends on a dump.
            case .servers, .settings, .popover, .readme: break
            }
        }
    }

    /// The rendered surface, wrapped in the harness's coordinate space.
    ///
    /// **Each surface builds its own model inside its own arm.** `board: ServersBoardModel` used to
    /// be a stored property, which made every surface pay for the Servers board's model and made a
    /// second surface impossible to add without constructing one it does not use. What is stored now
    /// is the shell, which every surface genuinely shares because it is the poll they all read.
    @MainActor
    struct MeasuredSurface: View {
        let surface: Surface
        let surfaceName: String
        let size: CGSize
        let shell: ShellModel
        let client: any ControlAPIClient
        let appearance: ColorScheme
        let boards: PreparedBoards
        /// What the `.readme` arm draws.
        ///
        /// Resolved in `run()` rather than here, because the live source is an `await` and a view's
        /// `body` cannot make one — and because a `.task` on a hosting view in a window that is
        /// never ordered in does not reliably fire, which is the same trap `PreparedBoards` above
        /// exists to avoid. It defaults to M19's fixture, so every existing invocation renders
        /// exactly what it rendered before.
        let readme: CapabilityDocumentSheet.Content
        /// Which of the panel's three tabs the `.readme` arm opens on.
        ///
        /// Switching tabs is a press on `@State`, which a headless render cannot perform, so the
        /// tab has to be chosen before the view is built. `.readMe` keeps every existing dump
        /// byte-for-byte what it was.
        var readmeTab: CapabilityDocument.Tab = .readMe

        var body: some View {
            Group {
                switch surface {
                case .servers:
                    ServersBoard(
                        shell: shell,
                        board: ServersBoardModel(client: client, tracker: shell.tracker)
                    )
                case .readme:
                    CapabilityDocumentSheet(content: readme, initialTab: readmeTab)
                case .popover:
                    MenuBarPopover(shell: shell)
                case .harnesses:
                    HarnessesBoard(board: boards.harnesses)
                case .insights:
                    InsightsBoard(board: boards.insights)
                case .settings:
                    // The **in-memory** token store, not the default keychain one: this is an
                    // unsigned SwiftPM executable with no keychain access group, where
                    // `SecItemCopyMatching` returns -34018 rather than errSecItemNotFound. The
                    // Makefile already documents that for the iOS lane; here it would render the
                    // keychain-refused state on every run and report it as the ideal frame.
                    SettingsWindow(
                        model: shell,
                        buildIdentity: .measured,
                        store: InMemoryTokenStore(),
                        restoration: ShellRestoration(defaults: Self.scratchDefaults)
                    )
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.colorScheme, appearance)
            .measureSurface(surfaceName)
        }

        /// A scratch defaults domain, so the pane the *developer* last looked at cannot decide which
        /// pane this run measures. A dump whose contents depend on the machine it ran on is not a
        /// measurement of the surface.
        static let scratchDefaults = UserDefaults(suiteName: "mcprouter.measure") ?? .standard
    }

#endif
