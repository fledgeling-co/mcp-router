import Foundation
@testable import RouterCore

/// Records the order operations happened in, across whatever is sharing it.
///
/// Needed because one of the log's requirements is about **sequence**, not content: stderr is
/// written before the file, so that a process dying between the two still leaves the line on the
/// terminal. Two independent recorders could each be correct and prove nothing about their order.
final class OperationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    var operations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        entries = []
    }
}

/// A filesystem held in memory, with failures that can be switched on.
///
/// The point is the failures. Several clauses are about what happens when a write cannot complete —
/// an unwritable directory, a failing backup, a manifest that is malformed at construction and
/// corrected later, a file deleted and recreated with an identical stamp. The real filesystem will
/// not enter those states on request, and a test that cannot enter them proves only the happy path.
final class MemoryFileSystem: FileSystem, @unchecked Sendable {
    struct Entry {
        var data: Data
        var stamp: FileStamp
    }

    enum Failure: Error, Equatable {
        case injected(String)
    }

    private let lock = NSLock()
    private var files: [String: Entry] = [:]
    private var directories: Set<String> = []
    private let recorder: OperationRecorder?

    /// Paths whose operation should throw. Keyed by `"<operation>:<path>"`, or `"<operation>:*"` for
    /// every path.
    private var failures: Set<String> = []

    init(recorder: OperationRecorder? = nil) {
        self.recorder = recorder
    }

    // MARK: - Test control

    func fail(_ operation: String, at path: String = "*") {
        lock.lock()
        defer { lock.unlock() }
        failures.insert("\(operation):\(path)")
    }

    func stopFailing(_ operation: String, at path: String = "*") {
        lock.lock()
        defer { lock.unlock() }
        failures.remove("\(operation):\(path)")
    }

    /// Writes a file directly, bypassing the injected failures, and sets its stamp explicitly.
    func seed(
        _ text: String,
        atPath path: String,
        modified: Date = Date(timeIntervalSince1970: 1),
        size: Int? = nil
    ) {
        let data = Data(text.utf8)
        lock.lock()
        defer { lock.unlock() }
        files[path] = Entry(
            data: data,
            stamp: FileStamp(modified: modified, size: size ?? data.count)
        )
    }

    func delete(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        files.removeValue(forKey: path)
    }

    func contents(atPath path: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = files[path]?.data else { return nil }
        // Failable rather than replacement-character lossy: a file that is not valid UTF-8 reads as
        // unreadable, which is what the router's own reader does with one.
        return String(bytes: data, encoding: .utf8)
    }

    var createdDirectories: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return directories
    }

    var paths: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(files.keys)
    }

    private func check(_ operation: String, _ path: String) throws {
        lock.lock()
        let shouldFail = failures.contains("\(operation):*") || failures.contains("\(operation):\(path)")
        lock.unlock()
        if shouldFail { throw Failure.injected("\(operation) refused for \(path)") }
    }

    // MARK: - FileSystem

    func fileExists(atPath path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return files[path] != nil
    }

    func readFile(atPath path: String) throws -> Data {
        try check("readFile", path)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = files[path] else { throw Failure.injected("no such file \(path)") }
        return entry.data
    }

    func writeFile(_ data: Data, atPath path: String) throws {
        try check("writeFile", path)
        recorder?.record("writeFile:\(path)")
        lock.lock()
        defer { lock.unlock() }
        let previous = files[path]?.stamp.modified ?? Date(timeIntervalSince1970: 0)
        files[path] = Entry(
            data: data,
            stamp: FileStamp(modified: previous.addingTimeInterval(1), size: data.count)
        )
    }

    func appendFile(_ data: Data, atPath path: String) throws {
        try check("appendFile", path)
        recorder?.record("appendFile:\(path)")
        lock.lock()
        defer { lock.unlock() }
        var existing = files[path]?.data ?? Data()
        existing.append(data)
        let previous = files[path]?.stamp.modified ?? Date(timeIntervalSince1970: 0)
        files[path] = Entry(
            data: existing,
            stamp: FileStamp(modified: previous.addingTimeInterval(1), size: existing.count)
        )
    }

    func createDirectory(atPath path: String) throws {
        try check("createDirectory", path)
        recorder?.record("createDirectory:\(path)")
        lock.lock()
        defer { lock.unlock() }
        directories.insert(path)
    }

    func moveItem(atPath source: String, toPath destination: String) throws {
        try check("moveItem", source)
        recorder?.record("moveItem:\(source)->\(destination)")
        lock.lock()
        defer { lock.unlock() }
        guard let entry = files.removeValue(forKey: source) else {
            throw Failure.injected("no such file \(source)")
        }
        files[destination] = entry
    }

    func copyItem(atPath source: String, toPath destination: String) throws {
        try check("copyItem", source)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = files[source] else { throw Failure.injected("no such file \(source)") }
        files[destination] = entry
    }

    func removeItem(atPath path: String) throws {
        try check("removeItem", path)
        lock.lock()
        defer { lock.unlock() }
        files.removeValue(forKey: path)
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try check("contentsOfDirectory", path)
        lock.lock()
        defer { lock.unlock() }
        let prefix = path.hasSuffix("/") ? path : "\(path)/"
        return files.keys
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
            .filter { !$0.contains("/") }
    }

    func attributes(atPath path: String) throws -> FileStamp {
        try check("attributes", path)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = files[path] else { throw Failure.injected("no such file \(path)") }
        return entry.stamp
    }
}

/// A clock the test moves by hand, which also counts how often it was read.
///
/// The count is what makes "a debug line computes nothing when verbosity is off" checkable: the
/// claim is not that no bytes were written, it is that no timestamp was even taken.
final class ManualClock: RouterClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Double
    private var reads = 0

    init(milliseconds: Double = 0) {
        current = milliseconds
    }

    var nowMilliseconds: Double {
        lock.lock()
        defer { lock.unlock() }
        reads += 1
        return current
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    func advance(by milliseconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        current += milliseconds
    }

    func set(_ milliseconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        current = milliseconds
    }
}

/// Captures the bytes a log line was written with, and can be made to fail.
final class RecordingSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Data] = []
    private var shouldFail = false
    private let recorder: OperationRecorder?

    init(recorder: OperationRecorder? = nil) {
        self.recorder = recorder
    }

    func write(_ bytes: Data) throws {
        recorder?.record("sink")
        lock.lock()
        let failing = shouldFail
        if !failing { chunks.append(bytes) }
        lock.unlock()
        if failing { throw MemoryFileSystem.Failure.injected("sink refused") }
    }

    func fail(_ value: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        shouldFail = value
    }

    var written: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return chunks
    }

    var text: String {
        // A marker rather than "" on invalid UTF-8: an empty string would silently pass a
        // byte-equality assertion against an empty expectation.
        written.map { String(bytes: $0, encoding: .utf8) ?? "<invalid utf-8>" }.joined()
    }
}
