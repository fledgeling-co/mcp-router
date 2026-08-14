import Foundation
import Testing
@testable import MCPRouterKit

/// The menu bar, held to two documents rather than to itself.
///
/// `DESIGN.md` §3.9 makes the menu bar the complete command surface. "Complete" is only checkable
/// against an external list, so this suite compares `MenuCommand` against the inventory table in
/// `planning/specs/spec-M1.md` and against `DESIGN.md` §8 — in both directions each time. A test
/// that walked `allCases` and asserted the model agreed with itself would pass for an empty model.
@Suite("Menu bar")
struct MenuCommandTests {
    enum OracleError: Error { case fileNotFound(String), tableNotFound(String) }

    /// Walks up from this file to the repository root, the way `ControlCopyTests` finds its mock.
    /// A missing document is a hard failure: a parity test that cannot find what it compares
    /// against must not quietly pass.
    static func repoFile(_ relativePath: String, from filePath: String = #filePath) throws -> String {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = dir.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw OracleError.fileNotFound(relativePath)
    }

    // MARK: - The spec's inventory table

    struct InventoryRow: Equatable, Hashable {
        let menu: String
        let title: String
        /// The shortcut as the document writes it, or nil for an em dash.
        let shortcut: String?
        let availability: String
    }

    /// Parses the four-column inventory out of `spec-M1.md`.
    ///
    /// Anchored to the heading rather than to "the first table in the file", so adding a table
    /// above it cannot silently repoint the oracle at the wrong rows.
    static func inventory() throws -> [InventoryRow] {
        let spec = try repoFile("planning/specs/spec-M1.md")
        guard let start = spec.range(of: "## The command inventory") else {
            throw OracleError.tableNotFound("## The command inventory")
        }
        let section = spec[start.lowerBound...]
        let end = section.range(
            of: "\n## ",
            range: section.index(section.startIndex, offsetBy: 10) ..< section.endIndex
        )
        let body = end.map { String(section[..<$0.lowerBound]) } ?? String(section)

        var rows: [InventoryRow] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { continue }
            // "| a | b | c | d |" splits to ["", "a", "b", "c", "d", ""].
            let parts = trimmed
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 6 else { continue }
            let fields = Array(parts[1 ... 4])
            // Skip the header and its separator explicitly rather than by accident of parsing.
            if fields[0] == "Menu" || fields[0].allSatisfy({ $0 == "-" }) { continue }
            rows.append(
                InventoryRow(
                    menu: fields[0],
                    title: fields[1],
                    shortcut: fields[2] == "—" ? nil : fields[2],
                    availability: fields[3]
                )
            )
        }
        return rows
    }

    /// The model, expressed in the inventory's own vocabulary so the two are comparable.
    static func modelRows() -> [InventoryRow] {
        MenuCommand.allCases.map { command in
            InventoryRow(
                menu: command.menu.rawValue,
                title: command.title,
                shortcut: command.shortcut?.display,
                availability: {
                    switch command.availability {
                    case .enabled: "enabled"
                    case .surfaceAbsent: "surfaceAbsent"
                    case .needsServerSelection: "needsServerSelection"
                    }
                }()
            )
        }
    }

    @Test("the inventory is parsed at all — an empty oracle is a failure, not a pass")
    func inventoryParses() throws {
        let rows = try Self.inventory()
        #expect(rows.count >= 30, "parsed only \(rows.count) inventory rows; the table shape changed")
    }

    @Test("every command the spec lists is shipped, and every shipped command is listed")
    func inventoryMatchesTheModelBothWays() throws {
        let specified = try Set(Self.inventory())
        let shipped = Set(Self.modelRows())

        let missing = specified.subtracting(shipped).sorted { $0.title < $1.title }
        let extra = shipped.subtracting(specified).sorted { $0.title < $1.title }

        #expect(missing.isEmpty, "specified but not shipped: \(missing.map(\.title))")
        #expect(extra.isEmpty, "shipped but not specified: \(extra.map(\.title))")
    }

    @Test("the six menus are exactly the six the design names")
    func sixMenus() {
        #expect(MenuBarMenu.allCases.map(\.rawValue)
            == ["MCP Router", "File", "Edit", "View", "Window", "Help"])
        for menu in MenuBarMenu.allCases {
            #expect(!MenuCommand.inMenu(menu).isEmpty, "\(menu.rawValue) has no commands")
        }
    }

    // MARK: - DESIGN.md §8

    /// The ⌘-combinations §8 states, parsed out of the document.
    static func documentedChords() throws -> [String: String] {
        let design = try repoFile("DESIGN.md")
        guard let start = design.range(of: "## 8 · The keyboard") else {
            throw OracleError.tableNotFound("## 8 · The keyboard")
        }
        let section = design[start.lowerBound...]
        let end = section.range(
            of: "\n## ",
            range: section.index(section.startIndex, offsetBy: 10) ..< section.endIndex
        )
        let body = end.map { String(section[..<$0.lowerBound]) } ?? String(section)

        var chords: [String: String] = [:]
        for line in body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { continue }
            // "| a | b |" splits to ["", "a", "b", ""].
            let parts = trimmed
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 4 else { continue }
            let key = parts[1].replacingOccurrences(of: "`", with: "")
            if key == "Key" || key.allSatisfy({ $0 == "-" }) { continue }
            chords[key] = parts[2]
        }
        return chords
    }

    @Test("§8 parses, and carries the eight bindings the document states")
    func designSectionEightParses() throws {
        let chords = try Self.documentedChords()
        #expect(chords.count == 8, "§8 parsed \(chords.count) rows; the table shape changed")
        for expected in ["⌘N", "⌘F", "⌘R", "⌘⌫", "⌘,", "Return", "Esc", "Space"] {
            #expect(chords[expected] != nil, "§8 no longer states \(expected)")
        }
    }

    /// A20. Every ⌘-combination the design states is bound to a menu item, because a ⌘-shortcut
    /// with no menu item is undiscoverable and §3.9 forbids that.
    @Test("every command-key shortcut in §8 is bound to a menu item")
    func everyDocumentedCommandChordIsBound() throws {
        let documented = try Self.documentedChords().keys.filter { $0.contains("⌘") }
        let bound = Set(MenuCommand.allCases.compactMap(\.shortcut).map(\.display))

        for chord in documented {
            #expect(bound.contains(chord), "§8 states \(chord) but no menu item binds it")
        }
    }

    /// A21's model half. The three bare keys belong to the surface that has rows, a default action
    /// or a sheet — the shell must not take one, or that surface can never receive it.
    @Test("the shell claims none of the three keys reserved for content")
    func reservedKeysAreNotClaimed() {
        for command in MenuCommand.allCases {
            guard let shortcut = command.shortcut else { continue }
            #expect(
                !MenuCommand.keysReservedForContent.contains(shortcut.key),
                "\(command.title) claims \(shortcut.key), which belongs to the content surface"
            )
            #expect(!shortcut.modifiers.isEmpty, "\(command.title) has a bare-key shortcut")
        }
    }

    // MARK: - The house rules

    /// `DESIGN.md` §3.4 — `…` means "opens a further view"; its absence means "commits now".
    @Test("the ellipsis is on exactly the commands that open a further view")
    func ellipsisRule() {
        let opening: Set = [
            "Add server…", "Add marketplace…", "Pair iPhone…", "Export library…"
        ]
        for command in MenuCommand.allCases {
            #expect(
                command.opensAFurtherView == opening.contains(command.title),
                "\(command.title) disagrees with the ellipsis rule"
            )
        }
    }

    /// §3.4 — disabled dims in place with a discoverable reason and never disappears.
    @Test("every unavailable command carries a reason, and every available one carries none")
    func disabledCommandsCarryTheirReason() {
        for command in MenuCommand.allCases {
            if command.availability.isEnabled {
                #expect(command.availability.reason == nil)
            } else {
                let reason = command.availability.reason
                #expect(reason?.isEmpty == false, "\(command.title) is disabled with no reason")
                // §6: never blames, never emotes.
                #expect(reason?.contains("!") == false)
                #expect(reason?.lowercased().contains("you did") == false)
            }
        }
        // Exactly two reasons exist, so none can be invented at a call site.
        #expect(CommandAvailability.surfaceAbsent.reason == "This part of the app isn't built yet.")
        #expect(CommandAvailability.needsServerSelection.reason == "Select a server first.")
    }

    /// **Which board each command gates on**, asserted where the shipping registry cannot see it.
    ///
    /// This is the fact M11's derived acceptance oracle gave up. That oracle compiles this very
    /// file, so a change to the gating map moves the expectation with the app and no gate goes red;
    /// `inventoryMatchesTheModelBothWays` above only reads `.none`, where every board-dependent
    /// command answers `surfaceAbsent` and the map is invisible; and with all eight boards
    /// installed *any* required destination yields `.enabled`. So the map is only falsifiable
    /// against **partial** contexts, which is what this builds.
    ///
    /// Repointing `find` at `.evals` instead of `.servers` passes every other test in this repo.
    /// It fails here.
    @Test("each command gates on its own board, not merely on some board")
    func gatingMapIsPerCommand() {
        func context(_ installed: Set<Destination>) -> MenuCommand.CommandContext {
            MenuCommand.CommandContext(installedDestinations: installed, selectedServerIsTripped: nil)
        }
        let serversOnly = context([.servers])
        let skillsOnly = context([.skills])

        // Servers is what these three need, and Skills does not stand in for it.
        for command in [MenuCommand.addServer, .find] {
            #expect(command.availability(in: serversOnly) == .enabled, "\(command.title)")
            #expect(command.availability(in: skillsOnly) == .surfaceAbsent, "\(command.title)")
        }
        // The two that act on a selection get past the surface question and stop at the selection.
        for command in [MenuCommand.resetServer, .removeServer] {
            #expect(command.availability(in: serversOnly) == .needsServerSelection, "\(command.title)")
            #expect(command.availability(in: skillsOnly) == .surfaceAbsent, "\(command.title)")
        }
        // And marketplaces are the Skills board's, which is the pair that would swap silently.
        #expect(MenuCommand.addMarketplace.availability(in: skillsOnly) == .enabled)
        #expect(MenuCommand.addMarketplace.availability(in: serversOnly) == .surfaceAbsent)

        // Owned by nothing that has shipped, so no installed set turns them on.
        for command in [MenuCommand.pairPhone, .exportLibrary] {
            #expect(command.availability(in: context(Set(Destination.allCases))) == .surfaceAbsent)
        }
    }

    @Test("shortcuts render in Apple's modifier order")
    func modifierOrder() {
        #expect(KeyChord("N", [.command, .shift]).display == "⇧⌘N")
        #expect(KeyChord("H", [.command, .option]).display == "⌥⌘H")
        #expect(KeyChord("S", [.command, .control]).display == "⌃⌘S")
        #expect(KeyChord("N").display == "⌘N")
    }

    @Test("no two commands claim the same shortcut")
    func shortcutsAreUnique() {
        let displays = MenuCommand.allCases.compactMap(\.shortcut).map(\.display)
        #expect(Set(displays).count == displays.count, "a shortcut is bound twice: \(displays)")
    }

    @Test("the View menu's destinations track the sidebar exactly")
    func viewMenuTracksTheSidebar() {
        let inView = MenuCommand.inMenu(.view).compactMap { command -> Destination? in
            if case let .selectDestination(destination) = command { return destination }
            return nil
        }
        #expect(inView == Destination.allCases.filter { $0.selectionDigit != nil })
    }
}
