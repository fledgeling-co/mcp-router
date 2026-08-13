import Foundation

/// The filesystem, behind a protocol.
///
/// Not for mocking's sake: several of this item's requirements are about what happens when a write
/// *fails* — an unwritable directory, a failing backup, a process killed between the temp write and
/// the rename, a log file that cannot be appended to. Those are states the real filesystem will not
/// enter on request, and a test that cannot enter them is a test that only ever proves the happy
/// path.
///
/// It is also what makes the manifest store's four paths testable as *sequences* rather than as
/// four independent cases: a file that is malformed at construction and then corrected, or deleted
/// and recreated with an identical stamp, is a trace the real filesystem cannot be asked to perform
/// on cue.
public protocol FileSystem: Sendable {
    func fileExists(atPath path: String) -> Bool
    func readFile(atPath path: String) throws -> Data
    func writeFile(_ data: Data, atPath path: String) throws
    /// Appends, creating the file when it is absent. Separate from ``writeFile(_:atPath:)`` because
    /// the log opens and closes per line rather than holding a handle.
    func appendFile(_ data: Data, atPath path: String) throws
    func createDirectory(atPath path: String) throws
    func moveItem(atPath source: String, toPath destination: String) throws
    func copyItem(atPath source: String, toPath destination: String) throws
    func removeItem(atPath path: String) throws
    func contentsOfDirectory(atPath path: String) throws -> [String]
    func attributes(atPath path: String) throws -> FileStamp
}

/// The two attributes the manifest store watches. Nothing else is read, because reading more would
/// mean re-reading the file to notice a change that mtime and size already imply.
public struct FileStamp: Sendable, Hashable {
    public let modified: Date
    public let size: Int

    public init(modified: Date, size: Int) {
        self.modified = modified
        self.size = size
    }
}

public struct RealFileSystem: FileSystem {
    public init() {}

    private var manager: FileManager { FileManager.default }

    public func fileExists(atPath path: String) -> Bool {
        manager.fileExists(atPath: path)
    }

    public func readFile(atPath path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    public func writeFile(_ data: Data, atPath path: String) throws {
        try data.write(to: URL(fileURLWithPath: path))
    }

    public func appendFile(_ data: Data, atPath path: String) throws {
        guard manager.fileExists(atPath: path) else {
            try data.write(to: URL(fileURLWithPath: path))
            return
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public func createDirectory(atPath path: String) throws {
        try manager.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public func moveItem(atPath source: String, toPath destination: String) throws {
        // rename(2) replaces the destination atomically; FileManager.moveItem refuses to.
        if rename(source, destination) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    public func copyItem(atPath source: String, toPath destination: String) throws {
        if manager.fileExists(atPath: destination) {
            try manager.removeItem(atPath: destination)
        }
        try manager.copyItem(atPath: source, toPath: destination)
    }

    public func removeItem(atPath path: String) throws {
        try manager.removeItem(atPath: path)
    }

    public func contentsOfDirectory(atPath path: String) throws -> [String] {
        try manager.contentsOfDirectory(atPath: path)
    }

    public func attributes(atPath path: String) throws -> FileStamp {
        let values = try manager.attributesOfItem(atPath: path)
        let modified = values[.modificationDate] as? Date ?? .distantPast
        let size = (values[.size] as? NSNumber)?.intValue ?? 0
        return FileStamp(modified: modified, size: size)
    }
}
