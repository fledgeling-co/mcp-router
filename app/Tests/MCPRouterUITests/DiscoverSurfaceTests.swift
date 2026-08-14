#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// M5 · Discover — the source-level claims, and the nine states.
    ///
    /// Split from `DiscoverBoardTests` for length. These are **source-level** gates rather than
    /// rendered assertions, for the reason `ActivityBoardRulesTests` gives: a rule like "no colour is
    /// named literally" is a property of the whole surface, and checking it by rendering one view
    /// leaves the rest unchecked.
    @Suite("M5 · the Discover surface")
    @MainActor
    struct DiscoverSurfaceTests {
        // MARK: - A9 · tokens and the native floor

        @Test("no Discover source names a colour or a size literally")
        func discoverSourcesUseTokensOnly() throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/MCPRouterUI/Boards")
            let files = ["DiscoverBoard.swift", "DiscoverBoardRow.swift",
                         "DiscoverDetailSheet.swift", "DiscoverBoardMetrics.swift",
                         "DiscoverBoardModel.swift"]

            for file in files {
                let text = try String(contentsOf: root.appending(path: file), encoding: .utf8)
                #expect(!text.contains("Color(red:"), "\(file) builds a colour by hand")
                #expect(!text.contains("Color(hex"), "\(file) builds a colour by hand")
                #expect(!text.contains(".font(.system("), "\(file) sets a font off the token scale")
                for named in [".foregroundStyle(.red", ".foregroundStyle(.blue", ".fill(.green"] {
                    #expect(!text.contains(named), "\(file) uses a stock colour rather than a token")
                }
            }
        }

        /// `--attn` is reserved for what genuinely wants a human decision. On this board that is
        /// exactly one thing: a repository GitHub reported as archived.
        @Test("attention colour is used for the archived warning and nothing else")
        func attentionIsReservedForArchived() throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/MCPRouterUI/Boards")
            let row = try String(
                contentsOf: root.appending(path: "DiscoverBoardRow.swift"),
                encoding: .utf8
            )
            let uses = row.components(separatedBy: "ColorToken.attention").count - 1
            #expect(uses == 1, "the row tints exactly one thing in attention, and it is `archived`")
        }

        // MARK: - The nine states are each accounted for

        @Test("every SurfaceState names where this board meets it")
        func everyStateIsAccountedFor() {
            for state in SurfaceState.allCases {
                let treatment = DiscoverBoardStates.treatment(for: state)
                #expect(!treatment.isEmpty, "\(state) has no stated treatment")
            }
            // Offline is not the same condition as error: one is the router being absent, the other
            // is the router answering while the indexes did not.
            #expect(DiscoverBoardStates.treatment(for: .offline)
                != DiscoverBoardStates.treatment(for: .error))
        }

        /// The argv is drawn as separate cells so it cannot be read as a shell line — and was then
        /// announced as one. `accessibilityLabel("Command: \(tokens.joined(separator: " "))")` handed a
        /// screen-reader user exactly the single-line command the visual design refuses to draw,
        /// erasing the token boundaries that made the block honest for the one user who cannot see the
        /// cells.
        @Test("the spoken command keeps the token boundaries the drawn one has")
        func spokenCommandIsNotAShellLine() {
            let spoken = FlowingTokens.spokenCommand(["npx", "-y", "@scope/server", "--allow-write"])

            // The joined line must not be recoverable from the announcement.
            #expect(!spoken.contains("npx -y @scope/server --allow-write"))
            // Every token is still announced, and its role is named.
            #expect(spoken.contains("program npx"))
            #expect(spoken.contains("argument 1, -y"))
            #expect(spoken.contains("argument 3, --allow-write"))
            // The count is stated, so a token dropped in speech is detectable by the listener.
            #expect(spoken.contains("4 parts"))
            #expect(FlowingTokens.spokenCommand([]) == "No command")
        }
    }
#endif
