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
                    case .featureUnbuilt: "featureUnbuilt"
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

    @Test("the eight menus are exactly the eight the design names, in bar order")
    func eightMenus() {
        // Six until M20. Router and Library sit between View and Window because that is where
        // `design/mcp-router-console.html` draws them, and `mac-shell.sh` reads the order back off
        // the running bar — so this list is a fact about the drawn menu bar rather than a
        // preference, and a reordering here would fail there too.
        #expect(MenuBarMenu.allCases.map(\.rawValue)
            == ["MCP Router", "File", "Edit", "View", "Router", "Library", "Window", "Help"])
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

    @Test("§8 parses, and carries the sixteen bindings the document states")
    func designSectionEightParses() throws {
        let chords = try Self.documentedChords()
        #expect(chords.count == 16, "§8 parsed \(chords.count) rows; the table shape changed")
        for expected in ["⌘N", "⌘F", "⌘R", "⌘⌫", "⌘,", "⌃W", "Return", "Esc", "Space"] {
            #expect(chords[expected] != nil, "§8 no longer states \(expected)")
        }
    }

    /// M20 put the board digits in `DESIGN.md` §8 for the first time, and **the two absences are
    /// the assertion**.
    ///
    /// Until then the accelerator a user presses most was the one part of the map that lived only
    /// in a `switch`, so the both-ways check above covered every chord in the app except those.
    /// `⌘5` and `⌘9` belong to Harnesses and Insights, which M22 ships; a row for either would be
    /// a binding this document states and the app cannot honour, and this fails if one appears
    /// before its board does — or if the seven get packed into `⌘1`–`⌘7`, which would move every
    /// digit a user has learned on the day M22 lands.
    @Test("§8 states seven board digits, and neither of M22's two")
    func designSectionEightStatesTheBoardDigits() throws {
        let chords = try Self.documentedChords()
        for digit in [1, 2, 3, 4, 6, 7, 8] {
            #expect(chords["⌘\(digit)"] != nil, "§8 no longer states ⌘\(digit)")
        }
        for absent in [5, 9] {
            #expect(
                chords["⌘\(absent)"] == nil,
                "§8 states ⌘\(absent), whose board M22 has not shipped"
            )
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
}
