import Foundation

/// The two filesystem questions PATH discovery asks.
///
/// Deliberately not ``FileSystem``: that protocol has seven implementations across the sources and
/// the test targets, and adding a method to it to answer one question here would edit six doubles
/// that have nothing to do with spawning.
public protocol DirectoryProbing: Sendable {
    /// What is directly inside a directory. Empty when it cannot be read — an unreadable `$HOME`
    /// must yield a PATH, not an error.
    func entries(ofDirectoryAt path: String) -> [String]
    func isDirectory(atPath path: String) -> Bool
}

public struct RealDirectoryProbe: DirectoryProbing {
    public init() {}

    public func entries(ofDirectoryAt path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }

    public func isDirectory(atPath path: String) -> Bool {
        var directory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
        return exists && directory.boolValue
    }
}

/// The PATH a stdio child inherits.
///
/// Launchd hands the router a fixed PATH — whatever `docs/install.sh` wrote into the plist — and
/// every child inherits it. That is the correct default for a daemon running only its own code and
/// the wrong one for a daemon whose whole job is executing other people's programs: a routed MCP
/// server that shells out to a CLI installed under the user's home cannot find it, reports the
/// capability *unavailable*, and the user pays for a paid API call in place of a free one.
///
/// The rule, recorded in `spec-R6.md` §2: add every `bin` directory that exists directly under
/// `$HOME` or under one of `$HOME`'s dot-directories. No shell is executed and no rc file is read.
/// `$SHELL -l -c 'echo $PATH'` was measured on the machine this was found on and rejected — zsh
/// reads `~/.zshrc` only when interactive, so a login shell returned `~/.local/bin` but not
/// `~/.grok/bin`, half-missing the defect at 1.69s, and the interactive variant that found both
/// cost 14.43s on a router the watcher restarts every time it adopts a server.
public enum ChildPath {
    /// The most directories that will be added. A home with thousands of dot-directories would
    /// otherwise build an environment long enough to matter to `execve`. Nine were found on the
    /// machine this was written on; the number bounds the loop rather than describing a measurement.
    public static let discoveryLimit = 64

    /// Every `bin` directory under `$HOME` or one of its dot-directories, sorted and deduplicated.
    ///
    /// Sorted so that two routers reading one home produce one string, and so the result does not
    /// depend on the order the filesystem happens to enumerate in.
    public static func userBinDirectories(
        home: String,
        probe: any DirectoryProbing = RealDirectoryProbe(),
        limit: Int = discoveryLimit
    ) -> [String] {
        guard !home.isEmpty, limit > 0 else { return [] }
        let root = home as NSString
        var candidates = [root.appendingPathComponent("bin")]
        for entry in probe.entries(ofDirectoryAt: home) where entry.hasPrefix(".") {
            // `.` and `..` are not returned by `contentsOfDirectory`, but a probe supplied by a
            // test may return them and a PATH entry of `$HOME/./bin` would be a duplicate wearing
            // a different spelling.
            guard entry != ".", entry != ".." else { continue }
            candidates.append(
                (root.appendingPathComponent(entry) as NSString).appendingPathComponent("bin")
            )
        }
        var found: Set<String> = []
        for candidate in candidates where probe.isDirectory(atPath: candidate) {
            found.insert(candidate)
        }
        // Sorted by UTF-8 bytes rather than by `String`'s own ordering. Swift compares Strings by
        // Unicode canonical equivalence and JavaScript's `Array.sort` compares UTF-16 code units,
        // and the two disagree above the BMP — a home holding `.\u{E000}` and an emoji-named
        // directory would order differently in the two routers, and at the cap boundary they would
        // select DIFFERENT directories. Byte order is the one comparison both can express.
        let ordered = found.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        return Array(ordered.prefix(limit))
    }

    /// The inherited PATH with the user's own tool directories appended.
    ///
    /// **Append, never prepend, and that is the load-bearing half.** The inherited entries keep
    /// their order and their position at the front, so no command that resolved before this change
    /// can resolve to a different binary after it — the change can only add capability. Prepending
    /// would let a version manager under `$HOME` capture `node` and `npx` for every child, and the
    /// measured defect is a missing binary rather than a wrong one.
    public static func augment(
        _ inherited: String,
        home: String,
        probe: any DirectoryProbing = RealDirectoryProbe(),
        limit: Int = discoveryLimit
    ) -> String {
        // Empty components are KEPT. `execvp` reads an empty entry as the current directory, so
        // dropping one from an inherited `:/usr/bin` would change where a child looks — and this
        // function's whole contract is that the inherited PATH survives unaltered.
        let existing = inherited.isEmpty
            ? []
            : inherited.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var seen = Set(existing)
        var merged = existing
        for directory in userBinDirectories(home: home, probe: probe, limit: limit)
            where seen.insert(directory).inserted
        {
            merged.append(directory)
        }
        return merged.joined(separator: ":")
    }

    /// The environment a child inherits: the router's own, with `PATH` augmented.
    ///
    /// A router started with no `PATH` at all still gets one, because the discovered directories
    /// are the whole of it rather than an addition to nothing.
    public static func augmentedEnvironment(
        _ environment: [String: String],
        probe: any DirectoryProbing = RealDirectoryProbe(),
        limit: Int = discoveryLimit
    ) -> [String: String] {
        guard let home = environment["HOME"], !home.isEmpty else { return environment }
        var augmented = environment
        augmented["PATH"] = augment(
            environment["PATH"] ?? "", home: home, probe: probe, limit: limit
        )
        return augmented
    }
}
