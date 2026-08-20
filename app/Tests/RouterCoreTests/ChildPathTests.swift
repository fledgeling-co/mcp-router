import Foundation
import Testing
@testable import RouterCore

/// A probe over a dictionary, so discovery is exercised without a filesystem.
///
/// `directories` is the set of paths that answer yes to `isDirectory`; `listing` is what each one
/// contains. A path present in `listing` but absent from `directories` is the file-named-`bin`
/// case, which the discovery has to skip.
private struct FakeProbe: DirectoryProbing {
    var listing: [String: [String]] = [:]
    var directories: Set<String> = []

    func entries(ofDirectoryAt path: String) -> [String] {
        listing[path] ?? []
    }

    func isDirectory(atPath path: String) -> Bool {
        directories.contains(path)
    }
}

@Suite("R6 — the PATH a child inherits")
struct ChildPathTests {
    private static let home = "/Users/tester"

    /// A home with `bin`, three dot-directories that carry a `bin`, one that does not, one whose
    /// `bin` is a file, and one non-dot directory that carries a `bin` and must be ignored.
    private static func probe() -> FakeProbe {
        FakeProbe(
            listing: [home: [".local", ".grok", ".cargo", ".config", ".broken", "Projects"]],
            directories: [
                "\(home)/bin",
                "\(home)/.local/bin",
                "\(home)/.grok/bin",
                "\(home)/.cargo/bin"
            ]
        )
    }

    @Test("A2 — discovery finds bin under the home and under its dot-directories")
    func discoversUserBinDirectories() {
        let found = ChildPath.userBinDirectories(home: Self.home, probe: Self.probe())
        #expect(found == [
            "\(Self.home)/.cargo/bin",
            "\(Self.home)/.grok/bin",
            "\(Self.home)/.local/bin",
            "\(Self.home)/bin"
        ])
    }

    @Test("A2 — a dot-directory with no bin, and a bin that is a file, are both skipped")
    func skipsWhatIsNotADirectory() {
        let found = ChildPath.userBinDirectories(home: Self.home, probe: Self.probe())
        #expect(!found.contains("\(Self.home)/.config/bin"))
        #expect(!found.contains("\(Self.home)/.broken/bin"))
    }

    @Test("A2 — a non-dot sibling directory is not searched")
    func ignoresNonDotDirectories() {
        var probe = Self.probe()
        probe.directories.insert("\(Self.home)/Projects/bin")
        let found = ChildPath.userBinDirectories(home: Self.home, probe: probe)
        #expect(!found.contains("\(Self.home)/Projects/bin"))
    }

    @Test("A2 — `.` and `..` cannot become PATH entries")
    func ignoresDotAndDotDot() {
        var probe = FakeProbe(listing: [Self.home: [".", ".."]], directories: [])
        probe.directories.insert("\(Self.home)/./bin")
        probe.directories.insert("\(Self.home)/../bin")
        #expect(ChildPath.userBinDirectories(home: Self.home, probe: probe).isEmpty)
    }

    @Test("A2 — discovery stops at the limit")
    func honoursTheLimit() {
        let names = (0 ..< 200).map { ".tool\($0)" }
        let probe = FakeProbe(
            listing: [Self.home: names],
            directories: Set(names.map { "\(Self.home)/\($0)/bin" })
        )
        #expect(ChildPath.userBinDirectories(home: Self.home, probe: probe).count == 64)
        #expect(ChildPath.userBinDirectories(home: Self.home, probe: probe, limit: 3).count == 3)
    }

    @Test("A1 — the inherited PATH keeps its order and stays at the front")
    func appendsRatherThanPrepends() {
        let inherited = "/opt/homebrew/bin:/usr/bin:/bin"
        let merged = ChildPath.augment(inherited, home: Self.home, probe: Self.probe())
        #expect(merged == inherited
            + ":\(Self.home)/.cargo/bin"
            + ":\(Self.home)/.grok/bin"
            + ":\(Self.home)/.local/bin"
            + ":\(Self.home)/bin")
        #expect(merged.hasPrefix(inherited), "a prepend would change which node a child resolves")
    }

    @Test("A1 — a directory already on the PATH is not added twice")
    func deduplicatesAgainstTheInheritedPath() {
        let inherited = "\(Self.home)/.local/bin:/usr/bin"
        let merged = ChildPath.augment(inherited, home: Self.home, probe: Self.probe())
        let occurrences = merged.split(separator: ":").filter { $0 == "\(Self.home)/.local/bin" }
        #expect(occurrences.count == 1)
        #expect(merged.hasPrefix(inherited))
    }

    /// `execvp` reads an empty PATH component as the current directory, so dropping one changes
    /// where a child looks. The contract is that the inherited PATH survives byte for byte.
    @Test("A1 — an empty component in the inherited PATH survives")
    func keepsEmptyPathComponents() {
        let merged = ChildPath.augment(":/usr/bin::", home: Self.home, probe: Self.probe())
        #expect(merged.hasPrefix(":/usr/bin::"))
        #expect(merged == ":/usr/bin::"
            + ":\(Self.home)/.cargo/bin"
            + ":\(Self.home)/.grok/bin"
            + ":\(Self.home)/.local/bin"
            + ":\(Self.home)/bin")
    }

    /// Swift orders Strings by Unicode canonical equivalence and JavaScript's `Array.sort` orders
    /// by UTF-16 code units. The two disagree above the BMP, and at the cap boundary a disagreement
    /// would make the two routers select different directories. Both sort by UTF-8 bytes.
    @Test("A7 — discovery orders by UTF-8 bytes, where the two routers can agree")
    func ordersByUTF8Bytes() {
        let names = [".\u{E000}", ".\u{1F600}"]
        let probe = FakeProbe(
            listing: [Self.home: names],
            directories: Set(names.map { "\(Self.home)/\($0)/bin" })
        )
        // U+E000 encodes as EE 80 80 and U+1F600 as F0 9F 98 80, so the private-use name sorts
        // first by bytes. Sorting by UTF-16 code units puts the surrogate pair first instead.
        #expect(ChildPath.userBinDirectories(home: Self.home, probe: probe) == [
            "\(Self.home)/.\u{E000}/bin",
            "\(Self.home)/.\u{1F600}/bin"
        ])
    }

    @Test("A6 — an empty inherited PATH, an empty home and an unreadable home each yield a PATH")
    func degradesRatherThanFailing() {
        #expect(ChildPath.augment("", home: Self.home, probe: Self.probe()) == [
            "\(Self.home)/.cargo/bin",
            "\(Self.home)/.grok/bin",
            "\(Self.home)/.local/bin",
            "\(Self.home)/bin"
        ].joined(separator: ":"))
        #expect(ChildPath.augment("/usr/bin", home: "", probe: Self.probe()) == "/usr/bin")
        let unreadable = FakeProbe(listing: [:], directories: [])
        #expect(ChildPath.augment("/usr/bin", home: Self.home, probe: unreadable) == "/usr/bin")
    }

    @Test("A1 — the environment keeps every other variable, and a home-less one is untouched")
    func augmentsOnlyThePathVariable() {
        let base = ["HOME": Self.home, "PATH": "/usr/bin", "TOKEN": "keep-me"]
        let augmented = ChildPath.augmentedEnvironment(base, probe: Self.probe())
        #expect(augmented["TOKEN"] == "keep-me")
        #expect(augmented["PATH"]?.hasPrefix("/usr/bin:") == true)
        #expect(ChildPath.augmentedEnvironment(["PATH": "/usr/bin"], probe: Self.probe())
            == ["PATH": "/usr/bin"])
    }

    /// The parity guard. `mcp-router import` reports `PoolError.message`, and the `cli-import`
    /// lane diffs it against Node's own text for a missing command. Rewording it would redden a
    /// parity row over a rewording, so the exact bytes are asserted here rather than described.
    @Test("A5 — commandNotFound carries the reference's wire text and a richer description")
    func commandNotFoundText() {
        let error = PoolError.commandNotFound(
            name: "aseprite",
            command: "aseprite",
            searchedPath: "/usr/bin:/bin:/opt/homebrew/bin"
        )
        #expect(error.message == "spawn aseprite ENOENT")
        #expect(error.description == """
        upstream "aseprite" could not be started: spawn aseprite ENOENT — "aseprite" is not \
        in any of the 3 directories on the router's PATH. Install it, or give this server an \
        absolute command.
        """)
        #expect(
            error != PoolError.spawnFailed(name: "aseprite", reason: "spawn aseprite ENOENT"),
            "the point of the case is that a caller can tell the two apart"
        )
    }
}
