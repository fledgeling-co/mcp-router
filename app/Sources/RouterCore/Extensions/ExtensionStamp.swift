import CryptoKit
import Foundation

/// What a directory tree looked like at one moment: how much of it there was, when it last moved,
/// and a digest over its bytes.
///
/// Three figures rather than one, because they answer three different questions and only the third
/// is expensive. `files` and `bytes` are what a person reads in a plan; `newestModifiedMilliseconds`
/// is what decides whether anybody is editing the tree right now; `digest` is what makes "the copy
/// is complete" a comparison rather than an assurance.
public struct TreeStamp: Sendable, Hashable {
    public let files: Int
    public let bytes: Int
    public let newestModifiedMilliseconds: Double
    /// SHA-256 over every regular file's relative path, size and content hash, in sorted order.
    ///
    /// Path and size are in the material as well as the content, so a tree that moved a file
    /// without changing any byte of it does not hash the same as one that did not. Sorted, because
    /// `FileManager`'s enumerator promises no order and a digest that depended on it would differ
    /// between two readings of one unchanged directory.
    public let digest: String

    public init(files: Int, bytes: Int, newestModifiedMilliseconds: Double, digest: String) {
        self.files = files
        self.bytes = bytes
        self.newestModifiedMilliseconds = newestModifiedMilliseconds
        self.digest = digest
    }
}

/// Reading a tree's stamp, and nothing else. It opens files and writes none.
///
/// **Named `Stamp` rather than `Fingerprint` because of a gate, and the gate is right.**
/// `LogParityTests`' A31 rule refuses any line under `app/Sources/RouterCore` containing `print(`,
/// because a router speaking MCP over stdio must keep that stream clean and a scan for the
/// `FileHandle` names alone would miss the likeliest regression. `TreeFingerprint(` contains that
/// substring, so the constructor tripped it. Narrowing the rule to make this type's name fit would
/// have traded a gate for a noun; `FileStamp` was already the repository's word for the same idea.
public enum ExtensionStamp {
    /// `nil` when the directory could not be enumerated at all.
    ///
    /// A file inside it that cannot be read is **not** `nil`: it contributes its path and the
    /// marker `unreadable` to the digest instead of its content. That keeps a partially readable
    /// tree comparable with itself — a copy that reproduced the same unreadable file matches — while
    /// making it impossible for an unreadable file to be silently absent from the material.
    public static func measure(_ directory: String) -> TreeStamp? {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = manager.enumerator(atPath: directory)
        else { return nil }

        var lines: [String] = []
        var files = 0
        var bytes = 0
        var newest = modified(of: directory, manager: manager)
        for case let relative as String in enumerator {
            let path = (directory as NSString).appendingPathComponent(relative)
            newest = max(newest, modified(of: path, manager: manager))
            guard let attributes = try? manager.attributesOfItem(atPath: path) else {
                lines.append("\(relative)\t?\tunstattable")
                files += 1
                continue
            }
            let type = attributes[.type] as? FileAttributeType
            if type == .typeDirectory { continue }
            files += 1
            if type == .typeSymbolicLink {
                let target = (try? manager.destinationOfSymbolicLink(atPath: path)) ?? ""
                lines.append("\(relative)\tlink\t\(target)")
                continue
            }
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            bytes += size
            guard let data = manager.contents(atPath: path) else {
                lines.append("\(relative)\t\(size)\tunreadable")
                continue
            }
            lines.append("\(relative)\t\(size)\t\(hex(SHA256.hash(data: data)))")
        }
        lines.sort()
        return TreeStamp(
            files: files,
            bytes: bytes,
            newestModifiedMilliseconds: newest,
            digest: hex(SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)))
        )
    }

    /// A tree that has not been touched for `settleMilliseconds`.
    ///
    /// The guard behind "ingestion never runs against a directory a person is editing". It is a
    /// necessary condition and not a sufficient one — nothing on a POSIX filesystem can prove an
    /// editor does not have the file open — so the apply step re-measures after the copy and
    /// refuses on any change. The two together are what the promise rests on; this one alone would
    /// be a window, not a guarantee.
    public static func isSettled(
        _ stamp: TreeStamp, now: Double, settleMilliseconds: Double
    ) -> Bool {
        now - stamp.newestModifiedMilliseconds >= settleMilliseconds
    }

    private static func modified(of path: String, manager: FileManager) -> Double {
        guard let attributes = try? manager.attributesOfItem(atPath: path),
              let date = attributes[.modificationDate] as? Date
        else { return 0 }
        return date.timeIntervalSince1970 * 1000
    }

    private static func hex(_ digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
