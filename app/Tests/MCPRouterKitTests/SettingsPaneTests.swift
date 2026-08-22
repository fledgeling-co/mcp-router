import Foundation
import Testing
@testable import MCPRouterKit

/// The Settings window's seven areas, held to the mock rather than to a literal in this file.
@Suite("Settings panes")
struct SettingsPaneTests {
    enum OracleError: Error {
        case fileNotFound(String)
        case noPanes
    }

    /// The mock's own `data-pane` sequence, read at test time.
    ///
    /// **The expected value comes from the design of record, not from a list written here**, which
    /// is the same mechanism `MenuCommandTests.inventory()` uses against `spec-M1.md`. A hand-copied
    /// order would agree with the code by construction: whoever reordered the enum would reorder the
    /// literal in the same sitting, and the test would pass through the change it exists to catch.
    static func mockPaneOrder() throws -> [String] {
        let mock = try repoFile("design/mcp-router-console.html")
        var panes: [String] = []
        for fragment in mock.components(separatedBy: "data-pane=\"").dropFirst() {
            guard let value = fragment.split(separator: "\"", maxSplits: 1).first else { continue }
            let name = String(value)
            if !panes.contains(name) { panes.append(name) }
        }
        // An empty parse is a broken reader, never a mock with no panes — the same rule every
        // oracle in this repository states about its own emptiness.
        guard !panes.isEmpty else { throw OracleError.noPanes }
        return panes
    }

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

    @Test("the mock's pane list parses at all — an empty oracle is a failure, not a pass")
    func mockOrderParses() throws {
        #expect(try Self.mockPaneOrder().count == 7)
    }

    @Test("the seven panes are the mock's seven, in the mock's order")
    func panesFollowTheMock() throws {
        #expect(try SettingsPane.ordered.map(\.rawValue) == (Self.mockPaneOrder()))
        #expect(SettingsPane.allCases.count == 7)
    }

    /// The brief's prose and the brief's own table disagree about where Menu bar sits, and the mock
    /// settles it. Stated on its own because it is the one ordering decision anybody would revisit.
    @Test("Menu bar is sixth, which is the mock's answer rather than the brief's sentence")
    func menuBarIsSixth() {
        #expect(SettingsPane.ordered[5] == .menuBar)
        #expect(SettingsPane.ordered.last == .advanced)
    }

    @Test("a stored pane this build no longer has falls back rather than blanking")
    func restorationFallsBack() {
        #expect(SettingsPane.restoring("security") == .security)
        #expect(SettingsPane.restoring("menubar") == .menuBar)
        #expect(SettingsPane.restoring("a-pane-that-was-removed") == .router)
        #expect(SettingsPane.restoring(nil) == .router)
        #expect(SettingsPane.fallback == .router)
    }

    @Test("every pane names an icon, and no two panes share one")
    func iconNamesAreDistinct() {
        let names = SettingsPane.allCases.map(\.iconName)
        #expect(Set(names).count == names.count, "two panes draw the same icon")
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    /// §3.2 — sentence case, and the fix for a tracked upper-case label is to remove it.
    @Test("pane titles and subtitles are sentence case and carry no transform")
    func copyIsSentenceCase() {
        for pane in SettingsPane.allCases {
            #expect(pane.title != pane.title.uppercased(), "\(pane.title) is upper case")
            #expect(pane.title.first?.isUppercase == true)
            #expect(pane.subtitle.first?.isUppercase == true)
        }
    }
}
