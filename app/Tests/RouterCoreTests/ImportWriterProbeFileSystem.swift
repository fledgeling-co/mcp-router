import Foundation
import Testing
@testable import RouterCore

/// A real filesystem that reports what it was asked to do, and can be told to fail one call.
///
/// `RealFileSystem` rather than a memory double throughout this suite, because three of the
/// properties under test — the file mode, `flock`, and a rename replacing an inode — are OS
/// behaviours that a memory double would simulate rather than exhibit.
final class ImportWriterProbeFileSystem: FileSystem, FileModeWriting, @unchecked Sendable {
    private let inner = RealFileSystem()
    private let lock = NSLock()
    private var _reads: [String] = []
    private var _moveAttempts: [String] = []
    let failMoveItem: Bool
    /// Signalled the first time the config path is read, so a test can tell "the writer read"
    /// from "the writer is still blocked on the lock".
    let readSignal = DispatchSemaphore(value: 0)
    private let signalOn: String?

    init(failMoveItem: Bool = false, signalOnReadOf path: String? = nil) {
        self.failMoveItem = failMoveItem
        signalOn = path
    }

    var reads: [String] { lock.withLock { _reads } }
    var moveAttempts: [String] { lock.withLock { _moveAttempts } }

    func fileExists(atPath path: String) -> Bool {
        inner.fileExists(atPath: path)
    }

    func readFile(atPath path: String) throws -> Data {
        lock.withLock { _reads.append(path) }
        defer { if path == signalOn { readSignal.signal() } }
        return try inner.readFile(atPath: path)
    }

    func writeFile(_ data: Data, atPath path: String) throws {
        try inner.writeFile(data, atPath: path)
    }

    func writeFile(_ data: Data, atPath path: String, mode: UInt16) throws {
        try inner.writeFile(data, atPath: path, mode: mode)
    }

    func fileMode(atPath path: String) throws -> UInt16 {
        try inner.fileMode(atPath: path)
    }

    func appendFile(_ data: Data, atPath path: String) throws {
        try inner.appendFile(data, atPath: path)
    }

    func createDirectory(atPath path: String) throws {
        try inner.createDirectory(atPath: path)
    }

    func createDirectory(atPath path: String, mode: UInt16) throws {
        try inner.createDirectory(atPath: path, mode: mode)
    }

    func moveItem(atPath source: String, toPath destination: String) throws {
        lock.withLock { _moveAttempts.append(destination) }
        if failMoveItem {
            throw NSError(domain: "ImportWriterProbe", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "rename refused by the probe"
            ])
        }
        try inner.moveItem(atPath: source, toPath: destination)
    }

    func copyItem(atPath source: String, toPath destination: String) throws {
        try inner.copyItem(atPath: source, toPath: destination)
    }

    func removeItem(atPath path: String) throws {
        try inner.removeItem(atPath: path)
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try inner.contentsOfDirectory(atPath: path)
    }

    func attributes(atPath path: String) throws -> FileStamp {
        try inner.attributes(atPath: path)
    }
}

/// Fixtures shared by the two writer suites.
///
/// They are split — `ImportConfigWriterTests` for the file's content, mode and bytes;
/// `ImportConfigWriterLockTests` for the cross-process lock — because those are different kinds of
/// test: one needs a scratch file, the other needs a second PROCESS holding a real `flock`. Sharing
/// the fixtures is what keeps the two from drifting apart on what "the adopted set" means.
enum ImportWriterFixtures {
    static func scratch() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcp-router-importwriter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var alpha: [JSONMember] {
        [JSONMember(key: JSString("alpha"), value: .object([
            JSONMember(key: JSString("command"), value: .string(JSString("node"))),
            JSONMember(key: JSString("args"), value: .array([.string(JSString("x.js"))]))
        ]))]
    }

    static func write(
        to path: String,
        adopted: [JSONMember]? = nil,
        fileSystem: any FileSystem & FileModeWriting = ImportWriterProbeFileSystem(),
        processIdentifier: Int32 = 4242,
        lockTimeoutMs: Int = 5000
    ) throws {
        try ImportConfigWriter.write(
            adopted: adopted ?? alpha,
            port: RouterHome.defaultPort,
            to: .init(
                path: path, processIdentifier: processIdentifier, lockTimeoutMs: lockTimeoutMs
            ),
            fileSystem: fileSystem
        )
    }
}
