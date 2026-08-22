import Foundation
import Testing
@testable import MCPRouterKit

/// The Settings pane's rules — mostly two: show only what the router observes, and never show the
/// token.
@Suite("Settings presentation")
struct SettingsPresentationTests {
    static let home = URL(fileURLWithPath: "/Users/example/.claude/mcp-router", isDirectory: true)

    static func facts(
        port: Int = 8879,
        idleMs: Int = 300_000,
        since: String = "2026-08-12T09:14:00Z"
    ) -> SettingsPresentation.RouterFacts {
        .init(port: port, idleMs: idleMs, since: since, home: home)
    }

    // MARK: - A6 · the endpoint carries the observed port

    /// The failure this guards is a plausible constant. A build that renders `8879` for a router
    /// listening on 9999 tells the user to point their client at a port nothing is on.
    @Test("the endpoint is composed from the observed port, never a constant")
    func endpointUsesObservedPort() {
        #expect(Self.facts(port: 8879).endpoint == "http://127.0.0.1:8879/mcp")

        let moved = Self.facts(port: 9999)
        #expect(moved.endpoint == "http://127.0.0.1:9999/mcp")
        #expect(!moved.endpoint.contains("8879"), "the default port leaked into a moved router's endpoint")
    }

    @Test("the reaper reads in whole seconds, at the boundary values")
    func reaperFormatsSeconds() {
        #expect(Self.facts(idleMs: 300_000).reaper == "300s")
        #expect(Self.facts(idleMs: 1000).reaper == "1s")
        #expect(Self.facts(idleMs: 0).reaper == "0s")
        // Sub-second truncates rather than rounding up to a horizon the router does not have.
        #expect(Self.facts(idleMs: 999).reaper == "0s")
    }

    @Test("home shortens to a tilde under this user's home and stays whole outside it")
    func homeDisplayShortensOnlyWhereItApplies() {
        let facts = Self.facts()
        #expect(facts.homeDisplay(homeDirectory: "/Users/example") == "~/.claude/mcp-router")
        // A container path, or any home this is not under, is shown in full — the truncation rule
        // for those is a left-side ellipsis at render time, not a wrong tilde here.
        #expect(facts.homeDisplay(homeDirectory: "/Users/someone-else")
            == "/Users/example/.claude/mcp-router")
    }

    @Test("an unparseable since reads as an em dash rather than as a plausible date")
    func sinceIsNotFaked() {
        #expect(Self.facts(since: "nonsense").sinceDisplay() == "—")
    }

    // MARK: - A5 · no memory figure exists to show

    /// `residentMb()` is measured by the router (`src/pool.ts`) and has **zero callers**: it never
    /// reaches `describe()` and never reaches the wire. So there is no honest megabyte figure, and
    /// `WarmSet` has no field that could carry one.
    @Test("the warm set carries names and a declared count, and no memory field")
    func warmSetHasNoMemoryField() {
        let set = SettingsPresentation.WarmSet(names: ["github"], declared: 8)
        let fields = Mirror(reflecting: set).children.compactMap(\.label).sorted()
        #expect(fields == ["declared", "names"])
    }

    @Test("the warm set summarises what is resident, in both its populated and empty forms")
    func warmSetSummary() async throws {
        var servers = try await FixtureControlAPIClient(.populated).servers().servers
        #expect(servers.count >= 2, "the populated fixture is too small; the recording changed")
        for index in servers.indices {
            servers[index].warm = index < 2
        }

        let set = SettingsPresentation.WarmSet(servers: servers)
        #expect(set.names.count == 2)
        #expect(set.declared == servers.count)
        #expect(set.summary == "2 of \(servers.count) servers")
        #expect(!set.isEmpty)

        for index in servers.indices {
            servers[index].warm = false
        }
        let none = SettingsPresentation.WarmSet(servers: servers)
        #expect(none.isEmpty)
        #expect(none.summary == "None of \(servers.count) servers")

        #expect(SettingsPresentation.WarmSet(names: [], declared: 1).summary == "None of 1 server")
    }

    // MARK: - A7 · the token cannot reach a view

    /// Structural rather than behavioural, and deliberately so: a test that renders the pane and
    /// searches the output proves today's code does not leak the token, while this proves there is
    /// nowhere to put one. `TokenStatus` has four cases and the only associated value in any of
    /// them is an `OSStatus`.
    @Test("no TokenStatus case can carry a token")
    func tokenStatusCannotCarryAToken() {
        let secret = "sk-live-do-not-render-this-anywhere"
        let all: [SettingsPresentation.TokenStatus] = [
            .stored, .absent, .rejected, .unavailable(status: -25300)
        ]
        for status in all {
            #expect(!status.value.contains(secret))
            #expect(!(status.banner ?? "").contains(secret))
            // The rendered value is a fixed sentence with no interpolation of anything secret.
            #expect(!status.value.isEmpty)
        }
        #expect(SettingsPresentation.TokenStatus.unavailable(status: -25300).banner?
            .contains("-25300") == true)
    }

    // MARK: - A9 · forget, and when it is available

    @Test("forget is available only when there is something to forget")
    func forgetAvailability() {
        #expect(SettingsPresentation.TokenStatus.stored.canForget)
        #expect(SettingsPresentation.TokenStatus.rejected.canForget)
        #expect(!SettingsPresentation.TokenStatus.absent.canForget)
        #expect(!SettingsPresentation.TokenStatus.unavailable(status: -25300).canForget)
        #expect(SettingsPresentation.forgetDisabledReason == "There is no stored token to forget.")
    }

    /// §3.4 allows one prominent accent-filled action per view. Forget is that action only while
    /// the router is rejecting the stored token, which is the one condition where it is the fix
    /// rather than a maintenance chore.
    @Test("forget is prominent only in the rejected state")
    func forgetIsProminentOnlyWhenItIsTheFix() {
        #expect(SettingsPresentation.TokenStatus.rejected.forgetIsProminent)
        #expect(!SettingsPresentation.TokenStatus.stored.forgetIsProminent)
        #expect(!SettingsPresentation.TokenStatus.absent.forgetIsProminent)
        #expect(!SettingsPresentation.TokenStatus.unavailable(status: -25300).forgetIsProminent)
    }

    @Test("only the keychain failure carries a banner")
    func onlyKeychainFailureBanners() {
        #expect(SettingsPresentation.TokenStatus.stored.banner == nil)
        #expect(SettingsPresentation.TokenStatus.absent.banner == nil)
        #expect(SettingsPresentation.TokenStatus.rejected.banner == nil)
        #expect(SettingsPresentation.TokenStatus.unavailable(status: -25300).banner != nil)
    }

    // MARK: - the window's group headers

    /// **`SettingsPresentation.Group` is gone and this is what replaced it.**
    ///
    /// The enum was the Settings *board's* complete inventory of groups, and a window of seven panes
    /// has no such closed set — the headers now sit on `SettingsPaneCopy` beside the rest of each
    /// pane's copy. What is still capable of being false, and is what M8's clause was actually
    /// about, is that all four headers survived the re-housing and are still sentence case.
    @Test("M8's four group headers all survive the move into the window, in sentence case")
    func groupHeadersSurviveTheMove() {
        let headers = [
            SettingsPaneCopy.routerGroup,
            SettingsPaneCopy.menuBarGroup,
            SettingsPaneCopy.warmSetGroup,
            SettingsPaneCopy.controlTokenGroup
        ]
        #expect(headers == ["Router", "Menu bar", "Warm set", "Control token"])

        // Sentence case, per §3.2 — the loudest web tell is a tracked upper-case header, and the
        // fix is to remove it rather than re-track it. Asserted as: the first character is
        // upper-case and no word after the first begins with one. Every header this window draws,
        // not only M8's four.
        for header in headers + [SettingsPaneCopy.pairedDevicesGroup, SettingsPaneCopy.filesGroup] {
            let words = header.split(separator: " ")
            #expect(words[0].first?.isUppercase == true, "\(header) does not start capitalised")
            for word in words.dropFirst() {
                #expect(
                    word.first?.isLowercase == true,
                    "\(header) is title case; §3.2 asks for sentence case"
                )
            }
        }
    }

    /// The Advanced pane's two paths, derived from the token file's own directory so the paths
    /// shown are the paths used.
    @Test("the router's two files are named off the resolved home, with no size beside either")
    func routerFilesDeriveFromTheHome() {
        let files = SettingsPresentation.RouterFiles(
            home: URL(fileURLWithPath: "/scratch/home/.claude/mcp-router")
        )
        #expect(files.logPath(homeDirectory: "/scratch/home") == "~/.claude/mcp-router/router.log")
        #expect(
            files.configurationPath(homeDirectory: "/scratch/home")
                == "~/.claude/mcp-router/servers.json"
        )
        // Outside this user's home the full path is kept rather than mangled.
        #expect(files.logPath(homeDirectory: "/somewhere/else")
            == "/scratch/home/.claude/mcp-router/router.log")
        // There is no field a byte figure could occupy, which is the enforcement rather than a
        // convention — the same shape `TokenStatus` uses for the token itself.
        #expect(!files.logPath(homeDirectory: "/scratch/home").contains("MB"))
    }

    @Test("the menu bar item is shown by default")
    func menuBarShownByDefault() {
        #expect(SettingsPresentation.menuBarVisibleDefault)
        #expect(SettingsPresentation.menuBarVisibleKey == "shell.menuBarVisible")
    }

    // MARK: - A5 · the guard that outlives this item

    /// The failure mode here is not a bug in today's code — it is a plausible megabyte figure added
    /// later by someone who has not read `DESIGN.md` §6. A test over today's rendered output cannot
    /// see that coming, so this reads the source of every file M8 owns and fails on a memory unit
    /// appearing in a **string literal**.
    ///
    /// Scanning literals rather than whole lines is what makes it both sound and quiet: the doc
    /// comments in these files legitimately use the word "megabyte" while arguing that none may be
    /// shown, and a line-level grep would either flag those or be narrowed until it flagged nothing.
    /// It also catches `"\(n)MB"`, which a `" MB"` search misses.
    @Test("no memory unit appears in any string M8 renders")
    func noMemoryUnitInRenderedCopy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MCPRouterKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // app
        // Every file M8 added or whose copy it owns, including the views — the earlier version of
        // this guard scanned the two presentation files only, which left the surfaces that actually
        // render unguarded.
        let files = [
            "Sources/MCPRouterKit/Shell/SettingsPresentation.swift",
            "Sources/MCPRouterKit/Shell/MenuBarPresentation.swift",
            "Sources/MCPRouterKit/Shell/PopoverContent.swift",
            "Sources/MCPRouterKit/Shell/SchemaDiff.swift",
            // M15 re-housed M8's three board files as the Settings window, and this guard follows
            // them: it is about the copy, and the copy moved. The four pane files join for the same
            // reason — they are where a megabyte figure would actually be typed now.
            "Sources/MCPRouterKit/Shell/SettingsPaneCopy.swift",
            "Sources/MCPRouterUI/Settings/SettingsWindow.swift",
            "Sources/MCPRouterUI/Settings/SettingsParts.swift",
            "Sources/MCPRouterUI/Settings/SettingsWindowModel.swift",
            "Sources/MCPRouterUI/Settings/Panes/RouterPane.swift",
            "Sources/MCPRouterUI/Settings/Panes/SecurityPane.swift",
            "Sources/MCPRouterUI/Settings/Panes/MenuBarPane.swift",
            "Sources/MCPRouterUI/Settings/Panes/AdvancedPane.swift",
            "Sources/MCPRouterUI/Settings/Panes/GovernedElsewherePane.swift",
            "Sources/MCPRouterUI/Shell/MenuBarPopover.swift",
            "Sources/MCPRouterUI/Shell/MenuBarStatusItem.swift"
        ]
        // Units are matched **case-sensitively**, and that is not laziness: a case-insensitive
        // "MB" matches "remembers", which is in this pane's own subtitle. The units only ever
        // appear capitalised in real copy ("240MB"), and the spelled-out words are checked
        // case-insensitively, where no such collision exists.
        let units = ["MB", "KB", "GB", "MiB", "GiB"]
        let words = ["megabyte", "kilobyte", "gigabyte"]

        for relative in files {
            let url = root.appendingPathComponent(relative)
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(!source.isEmpty, "\(relative) is empty or moved; this guard is not running")

            for literal in Self.stringLiterals(in: source) {
                for unit in units {
                    #expect(
                        !literal.contains(unit),
                        """
                        \(relative) renders "\(literal)", which carries \(unit). \
                        `residentMb()` has no callers and never reaches the wire, so there is no \
                        memory figure the router observes (DESIGN.md §6).
                        """
                    )
                }
                for word in words {
                    #expect(
                        !literal.localizedCaseInsensitiveContains(word),
                        "\(relative) renders \"\(literal)\", which names \(word)s (DESIGN.md §6)."
                    )
                }
            }
        }
    }

    /// Every double-quoted literal in a Swift source, with comment lines dropped first.
    ///
    /// Deliberately simple: it is a guard over this repo's own copy, not a Swift parser. Dropping
    /// `//` lines is what keeps the doc comments — which argue *for* this rule using the very words
    /// it forbids — from failing it.
    static func stringLiterals(in source: String) -> [String] {
        var literals: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
            var inLiteral = false
            var current = ""
            var previous: Character?
            for character in line {
                if character == "\"", previous != "\\" {
                    if inLiteral { literals.append(current); current = "" }
                    inLiteral.toggle()
                } else if inLiteral {
                    current.append(character)
                }
                previous = character
            }
        }
        return literals
    }

    /// The guard above is only worth having if it can fail. Proving that here rather than only in a
    /// commit message: a literal carrying a unit is rejected, and the prose around it is not.
    @Test("the memory-unit guard rejects a literal and ignores a comment")
    func memoryGuardCanFail() {
        let offending = """
        let label = "Warm set uses 240MB"
        """
        #expect(Self.stringLiterals(in: offending).contains { $0.contains("MB") })

        let commentary = "/// residentMb() reports megabytes and has no callers."
        #expect(Self.stringLiterals(in: commentary).isEmpty)
    }
}
