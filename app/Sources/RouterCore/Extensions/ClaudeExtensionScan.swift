import Foundation

/// Read Claude's directories and say what the router could take out of them. **It writes nothing.**
///
/// ## Why the plugin lane is a register read and the other two are directory walks
///
/// Measured on this machine on 2026-08-28, `~/.claude/plugins/cache` holds **335 directories shaped
/// like a version** and only **127 installed plugins**. Of those 335: 84 carry no `plugin.json`
/// anywhere in them, and five of the top-level entries are `temp_git_*` clones whose `.git/hooks`
/// walks to the same depth a real `<marketplace>/<plugin>/<version>` does. So a walk cannot tell an
/// installed plugin from an orphaned one, and the marker that looks as if it could does not:
/// `.in_use` is present on **241 of the 335**, and on **52 of the 65 plugins that have more than one
/// version it is present on more than one of them**. There is no property of a directory that names
/// the installed version.
///
/// `plugins/installed_plugins.json` names it exactly — one record per `<plugin>@<marketplace>`, each
/// carrying the `installPath` and the `version` — and on this machine every one of the 127 records
/// held exactly one element. So that file is the source, a cache directory no record names is
/// simply not a candidate, and the 84 descriptor-less directories are never considered rather than
/// being reported as 84 failures.
///
/// The two directory walks are safe because their layouts are flat and their descriptors are
/// required: a `skills/<name>` with no `SKILL.md` and a `marketplaces/<name>` with no
/// `.claude-plugin/marketplace.json` are reported and left alone, which is what the acceptance
/// clause about an unidentifiable extension asks for.
public enum ClaudeExtensionScan {
    /// Everything the router could take, everything it will not, and every register it could not
    /// read.
    public static func scan(
        tree: ClaudeTree,
        store: any ExtensionStoring,
        settleMilliseconds: Double,
        now: Double
    ) -> ClaudeScan {
        var candidates: [IngestCandidate] = []
        var blocked: [IngestBlocked] = []
        var unreadable: [String] = []
        let context = Context(tree: tree, store: store, settle: settleMilliseconds, now: now)

        for kind in [ExtensionKind.skills, .marketplaces] {
            let directory = kind == .skills ? tree.skillsDirectory : tree.marketplacesDirectory
            switch walk(directory) {
            case let .failure(message):
                unreadable.append(message)
            case let .success(names):
                for name in names {
                    context.consider(
                        Subject(
                            kind: kind,
                            name: name,
                            sourcePath: (directory as NSString).appendingPathComponent(name),
                            version: nil,
                            settingsKey: ClaudeTree.settingsContainer(for: kind) == nil ? nil : name
                        ),
                        into: &candidates, or: &blocked
                    )
                }
            }
        }

        switch installedPlugins(at: tree.installedPluginsPath) {
        case let .failure(message):
            unreadable.append(message)
        case let .success(records):
            for record in records {
                context.consider(
                    Subject(
                        kind: .plugins, name: record.identity, sourcePath: record.installPath,
                        version: record.version, settingsKey: record.identity
                    ),
                    into: &candidates, or: &blocked
                )
            }
        }
        return ClaudeScan(
            tree: tree, candidates: candidates, blocked: blocked, unreadableRegisters: unreadable
        )
    }

    // MARK: - The register

    /// One row of `installed_plugins.json`.
    struct InstalledPlugin: Sendable, Hashable {
        /// `<plugin>@<marketplace>` — the register's own key, used verbatim.
        let identity: String
        let installPath: String
        let version: String?
    }

    enum Reading<Value> {
        case success(Value)
        case failure(String)
    }

    /// `JSONParser`, never `JSONSerialization` — `scripts/lint/no-wire-codable.sh` covers this
    /// directory, and the reason it does applies here: a value lifted out of this file reaches
    /// `mcp-router ingest --json`, so a reordering decoder would decide bytes a caller compares.
    static func installedPlugins(at path: String) -> Reading<[InstalledPlugin]> {
        guard let data = FileManager.default.contents(atPath: path) else {
            // Absent is not a failure to report as unreadable — a Claude tree that never installed
            // a plugin has no register — but it IS the difference between zero and unknown, so the
            // caller is told which it was.
            return FileManager.default.fileExists(atPath: path)
                ? .failure("\(path) could not be opened")
                : .success([])
        }
        guard let text = String(data: data, encoding: .utf8),
              let parsed = try? JSONParser.parse(text)
        else { return .failure("\(path) is not valid UTF-8 JSON") }
        guard let members = parsed.member("plugins")?.asObjectMembers else {
            return .failure("\(path) carries no plugins object")
        }
        var rows: [InstalledPlugin] = []
        for member in members {
            let identity = member.key.string
            guard let first = member.value.asArray?.first else { continue }
            guard let installPath = first.member("installPath")?.asString?.string,
                  !installPath.isEmpty
            else { continue }
            rows.append(InstalledPlugin(
                identity: identity,
                installPath: installPath,
                version: first.member("version")?.asString?.string
            ))
        }
        return .success(rows.sorted { $0.identity < $1.identity })
    }

    static func walk(_ directory: String) -> Reading<[String]> {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) else {
            return .success([])
        }
        guard isDirectory.boolValue else { return .failure("\(directory) is not a directory") }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return .failure("\(directory) could not be read")
        }
        return .success(names.filter { !$0.hasPrefix(".") }.sorted())
    }
}
