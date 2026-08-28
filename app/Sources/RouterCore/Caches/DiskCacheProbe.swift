import Foundation

/// The three caches as they are on a real machine.
///
/// `FileManager` directly rather than the ``FileSystem`` seam, for the reason ``DiskExtensionStore``
/// gives: the seam expresses single files and these are directory trees, so a probe proved against
/// its in-memory double would be proved against something that is not the subject.
///
/// **It reads and deletes under `~/.claude` and `~/.npm`, which R28 deliberately did not.** That is
/// this item's whole surface rather than a widening of R28's: the caches are not the router's to
/// hold, only to invalidate, and every path is reached through ``CacheRoots`` so a gate run points
/// somewhere else.
public struct DiskCacheProbe: CacheProbing {
    public let roots: CacheRoots

    public init(roots: CacheRoots) {
        self.roots = roots
    }

    private var manager: FileManager { FileManager.default }

    public func npxEntries() -> [NpxEntry] {
        directories(under: roots.npx).map { name in
            let directory = (roots.npx as NSString).appendingPathComponent(name)
            return NpxEntry(
                directory: directory,
                requested: requests(in: directory),
                bytes: treeBytes(directory)
            )
        }
    }

    public func pluginVersions() -> [PluginVersion] {
        var out: [PluginVersion] = []
        for marketplace in directories(under: roots.pluginCache) {
            let marketplacePath = (roots.pluginCache as NSString).appendingPathComponent(marketplace)
            let plugins = directories(under: marketplacePath)
            // A directory with no plugin directories under it is not a marketplace tree. It is
            // still reported — as itself, with empty plugin and version — because the refusal to
            // remove it is the interesting answer and dropping it here would hide the question.
            if plugins.isEmpty {
                out.append(PluginVersion(
                    marketplace: marketplace, plugin: "", version: "",
                    directory: marketplacePath, bytes: treeBytes(marketplacePath)
                ))
                continue
            }
            for plugin in plugins {
                let pluginPath = (marketplacePath as NSString).appendingPathComponent(plugin)
                let versions = directories(under: pluginPath)
                if versions.isEmpty {
                    out.append(PluginVersion(
                        marketplace: marketplace, plugin: "", version: "",
                        directory: pluginPath, bytes: treeBytes(pluginPath)
                    ))
                    continue
                }
                for version in versions {
                    let path = (pluginPath as NSString).appendingPathComponent(version)
                    out.append(PluginVersion(
                        marketplace: marketplace, plugin: plugin, version: version,
                        directory: path, bytes: treeBytes(path)
                    ))
                }
            }
        }
        return out
    }

    /// Size and modification time, which is what changes when a build output is rewritten.
    ///
    /// Not the file's bytes: `dossier`'s entry point is one file of a built tree and hashing it
    /// would be both slower and less true, since a rebuild that leaves the entry point identical
    /// still moves its mtime. A stamp that moves on every rebuild is the property wanted here.
    public func fileStamp(_ path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let attributes = try? manager.attributesOfItem(atPath: path)
        else { return nil }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        return "\(size):\(modified)"
    }

    public func removeDirectory(_ path: String) -> String? {
        // Refused rather than attempted when the path is not inside one of the two roots this type
        // was given. Every caller reaches here through a plan built from this probe's own readings,
        // so a path from anywhere else is a defect rather than a request — and a delete is the one
        // operation where finding that out afterwards is too late.
        guard isInsideARoot(path) else {
            return "\(path) is not inside \(roots.npx) or \(roots.pluginCache)"
        }
        do {
            try manager.removeItem(atPath: path)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func isInsideARoot(_ path: String) -> Bool {
        [roots.npx, roots.pluginCache].contains { root in
            path != root && path.hasPrefix(root.hasSuffix("/") ? root : "\(root)/")
        }
    }

    // MARK: - Reading

    /// Immediate subdirectories, dotted names skipped, sorted so two reads agree.
    private func directories(under path: String) -> [String] {
        guard let names = try? manager.contentsOfDirectory(atPath: path) else { return [] }
        return names.filter { name in
            guard !name.hasPrefix(".") else { return false }
            var isDirectory: ObjCBool = false
            let child = (path as NSString).appendingPathComponent(name)
            return manager.fileExists(atPath: child, isDirectory: &isDirectory) && isDirectory.boolValue
        }.sorted()
    }

    /// The direct dependencies one npx entry was created for, read from its own `package.json`,
    /// with the version that is actually installed read from the fetched tree.
    ///
    /// The spec and the installed version are both carried because they answer different questions:
    /// the spec is what does not change (`media-gen-pro-mcp@latest` forever) and the version is what
    /// does.
    private func requests(in directory: String) -> [NpxRequest] {
        let manifestPath = (directory as NSString).appendingPathComponent("package.json")
        guard let data = manager.contents(atPath: manifestPath),
              let text = String(data: data, encoding: .utf8),
              let parsed = try? JSONParser.parse(text),
              case let .object(members)? = parsed.member("dependencies")
        else { return [] }
        return members.map { member in
            let name = member.key.string
            return NpxRequest(
                name: name,
                spec: member.value.asString?.string ?? "",
                installedVersion: installedVersion(of: name, in: directory)
            )
        }.sorted { $0.name < $1.name }
    }

    private func installedVersion(of package: String, in directory: String) -> String? {
        let path = (directory as NSString)
            .appendingPathComponent("node_modules/\(package)/package.json")
        guard let data = manager.contents(atPath: path),
              let text = String(data: data, encoding: .utf8),
              let parsed = try? JSONParser.parse(text)
        else { return nil }
        return parsed.member("version")?.asString?.string
    }

    /// Bytes under a tree, or `nil` when the enumerator could not be made.
    ///
    /// A file that cannot be stat'd contributes nothing rather than a guess, which understates the
    /// size — the same direction ``DiskExtensionStore`` errs in, and the safe one for a figure a
    /// person is about to spend.
    private func treeBytes(_ path: String) -> Int? {
        guard let enumerator = manager.enumerator(atPath: path) else { return nil }
        var total = 0
        for case let relative as String in enumerator {
            let child = (path as NSString).appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: child, isDirectory: &isDirectory), !isDirectory.boolValue
            else { continue }
            let size = (try? manager.attributesOfItem(atPath: child)[.size]) as? NSNumber
            total += size?.intValue ?? 0
        }
        return total
    }
}
