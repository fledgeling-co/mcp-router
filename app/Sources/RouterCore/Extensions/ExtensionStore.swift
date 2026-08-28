import Foundation

/// The store, on the router's own disk.
///
/// **Nothing outside `root` is read or written.** The three kind directories, `.staging` and
/// `.removed` are all inside it, and `ExtensionNaming` refuses any name or relative path that
/// could reach past it. Claude's own `~/.claude/skills` and `~/.claude/plugins` are not touched by
/// this type at all — R28 makes the router able to *hold* these kinds, and R30 is the item that
/// moves anything out of Claude.
///
/// `FileManager` directly rather than the ``FileSystem`` seam, and the reason is the subject
/// rather than convenience: an entry is a directory tree, and the seam expresses single files. It
/// has no way to ask whether a path is a directory, its `copyItem` and `moveItem` are file
/// operations, and its in-memory double lists only the files immediately under a prefix, so a
/// store proven against it would be proven against something that is not a directory tree. The
/// suite drives this type against real temporary directories instead, which is also the only way
/// to observe the property this item is asked for — that a `GET` reports what is on disk.
public struct DiskExtensionStore: ExtensionStoring {
    /// `<router home>/extensions`.
    public let root: String
    /// Internal rather than private: the write half lives in `ExtensionStoreWrites.swift`, and a
    /// removal stamps its destination directory with the millisecond it happened at.
    let clock: any RouterClock

    public init(root: String, clock: any RouterClock = SystemClock()) {
        self.root = root
        self.clock = clock
    }

    private var manager: FileManager { FileManager.default }

    // MARK: - Paths

    public func directory(for kind: ExtensionKind) -> String {
        (root as NSString).appendingPathComponent(kind.rawValue)
    }

    var clockMilliseconds: Double { clock.nowMilliseconds }

    func entryPath(_ kind: ExtensionKind, _ name: String) -> String {
        (directory(for: kind) as NSString).appendingPathComponent(name)
    }

    private func isDirectory(_ path: String) -> Bool {
        var flag: ObjCBool = false
        return manager.fileExists(atPath: path, isDirectory: &flag) && flag.boolValue
    }

    // MARK: - Reading

    /// Enumerated from the directory on every call. There is no cached list and no index file, so
    /// an entry added or deleted by anything other than this router shows up on the next read.
    public func list(_ kind: ExtensionKind) -> ExtensionListing {
        let directory = directory(for: kind)
        // A store nobody has written to yet is empty, not unreadable. The router creates the kind
        // directory on the first add rather than at startup, so its absence is the ordinary state
        // of a fresh home and must not be reported as a failure.
        guard isDirectory(directory) else {
            return ExtensionListing(kind: kind, root: directory, records: [])
        }
        let names: [String]
        do {
            names = try manager.contentsOfDirectory(atPath: directory)
        } catch {
            return ExtensionListing(
                kind: kind, root: directory, records: [],
                unreadable: "\(directory) could not be read: \(error.localizedDescription)"
            )
        }
        // Sorted so two reads of an unchanged store agree; `contentsOfDirectory` does not promise
        // an order. Dotted names are skipped rather than listed: nothing this store writes can be
        // called one, so a `.DS_Store` is the operating system's litter and not an entry.
        let entries = names.filter { !$0.hasPrefix(".") }.sorted()
        return ExtensionListing(
            kind: kind, root: directory,
            records: entries.map { record(kind, name: $0) }
        )
    }

    public func read(_ kind: ExtensionKind, name: String) -> ExtensionRecord? {
        guard ExtensionNaming.isWellFormedName(name), isDirectory(entryPath(kind, name)) else {
            return nil
        }
        return record(kind, name: name)
    }

    private func record(_ kind: ExtensionKind, name: String) -> ExtensionRecord {
        let entry = entryPath(kind, name)
        guard isDirectory(entry) else {
            return ExtensionRecord(name: name, problem: "\(name) is not a directory")
        }
        let walk = walkFiles(entry)
        let descriptor = (entry as NSString).appendingPathComponent(kind.descriptorPath)
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: descriptor)),
              let text = String(bytes: bytes, encoding: .utf8)
        else {
            return ExtensionRecord(
                name: name, files: walk.files, bytes: walk.bytes,
                problem: "\(kind.descriptorPath) is missing or is not UTF-8"
            )
        }
        switch ExtensionDescriptor.read(kind, text: text) {
        case let .read(reading):
            return ExtensionRecord(
                name: name, title: reading.title, description: reading.description,
                files: walk.files, bytes: walk.bytes
            )
        case let .unreadable(problem):
            return ExtensionRecord(
                name: name, files: walk.files, bytes: walk.bytes, problem: problem
            )
        }
    }

    /// How many files the entry holds and how many bytes they come to.
    ///
    /// Both are counted rather than remembered from the add, so an entry a person edited in place
    /// reports its new size. A file the enumerator cannot stat contributes to `files` and not to
    /// `bytes`, which understates the size rather than inventing one.
    private func walkFiles(_ entry: String) -> (files: Int, bytes: Int) {
        guard let enumerator = manager.enumerator(atPath: entry) else { return (0, 0) }
        var files = 0
        var bytes = 0
        for case let relative as String in enumerator {
            let path = (entry as NSString).appendingPathComponent(relative)
            guard !isDirectory(path) else { continue }
            files += 1
            let size = (try? manager.attributesOfItem(atPath: path)[.size]) as? NSNumber
            bytes += size?.intValue ?? 0
        }
        return (files, bytes)
    }
}
