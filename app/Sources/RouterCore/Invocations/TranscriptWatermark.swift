import Foundation

/// How far into one transcript file a previous scan reached.
///
/// **The corpus is why this exists rather than a nicety.** Measured 2026-08-29: this machine's
/// Claude Code transcripts are **59,476 files and 19.5 GB**, and a 200-file sample took 0.5 s — so a
/// full pass is roughly 150 seconds and 19.5 GB of reads. `GET /insights` answers inside a request.
/// A reader that walked the corpus per call would hang the control API and thrash the disk, and it
/// would do it while looking like a slow endpoint rather than a design error.
///
/// Session transcripts are append-only JSONL, which is what makes a byte offset valid across runs.
/// The two stamps are held **beside** the offset rather than instead of it: a file whose size and
/// mtime both match is not opened at all, and a file that **shrank** is not resumed from an offset
/// that now points into different bytes.
public struct TranscriptWatermark: Sendable, Hashable {
    public var path: String
    /// The file's size when the scan finished with it.
    public var size: Int
    /// Its modification time, in milliseconds, at the same moment.
    public var modifiedMilliseconds: Double
    /// Bytes consumed. Equal to `size` after a clean pass; smaller when the file ended on a torn
    /// line that a later append will complete.
    public var offset: Int

    public init(path: String, size: Int, modifiedMilliseconds: Double, offset: Int) {
        self.path = path
        self.size = size
        self.modifiedMilliseconds = modifiedMilliseconds
        self.offset = offset
    }

    public var value: JSONValue {
        .object([
            JSONMember(key: "path", value: .string(JSString(path))),
            JSONMember(key: "size", value: .number(Double(size))),
            JSONMember(key: "modifiedMs", value: .number(modifiedMilliseconds)),
            JSONMember(key: "offset", value: .number(Double(offset)))
        ])
    }

    public init?(_ value: JSONValue) {
        guard let path = value.member("path")?.asString?.string,
              let size = value.member("size")?.asNumber,
              let modified = value.member("modifiedMs")?.asNumber,
              let offset = value.member("offset")?.asNumber
        else { return nil }
        self.init(
            path: path, size: Int(size), modifiedMilliseconds: modified, offset: Int(offset)
        )
    }

    /// What to do with this file now, given what it looks like on disk.
    public enum Disposition: Sendable, Hashable {
        /// Size and mtime both unchanged. Not opened.
        case unchanged
        /// It grew. Resume from ``TranscriptWatermark/offset``.
        case resume(from: Int)
        /// It shrank, or its mtime moved backwards, or nothing is known about it. Read from zero.
        case fromStart
    }

    public static func disposition(
        for stamp: FileStamp, against watermark: TranscriptWatermark?
    ) -> Disposition {
        guard let watermark else { return .fromStart }
        let modified = stamp.modified.timeIntervalSince1970 * 1000
        if stamp.size == watermark.size, modified == watermark.modifiedMilliseconds {
            return .unchanged
        }
        // Smaller than what was already consumed means the bytes underneath moved. There is no
        // offset into the new file that corresponds to the old one, so nothing is resumed.
        guard stamp.size >= watermark.offset, modified >= watermark.modifiedMilliseconds else {
            return .fromStart
        }
        return .resume(from: watermark.offset)
    }
}

/// The watermark file, as a whole.
///
/// An array of records rather than a keyed map, for `ExtensionFile`'s reason and one of its own:
/// `scripts/lint/no-wire-codable.sh` refuses a stored dictionary on any path that reaches the wire,
/// and the order the records are written in is the order the corpus was walked in, which makes a
/// diff between two runs readable.
public struct TranscriptWatermarks: Sendable {
    public private(set) var records: [TranscriptWatermark]

    public init(records: [TranscriptWatermark] = []) {
        self.records = records
    }

    public func watermark(for path: String) -> TranscriptWatermark? {
        records.first { $0.path == path }
    }

    public mutating func set(_ watermark: TranscriptWatermark) {
        if let index = records.firstIndex(where: { $0.path == watermark.path }) {
            records[index] = watermark
        } else {
            records.append(watermark)
        }
    }

    public var value: JSONValue {
        .object([
            JSONMember(key: "version", value: .number(1)),
            JSONMember(key: "files", value: .array(records.map(\.value)))
        ])
    }

    /// An unreadable or wrong-version file starts empty, which costs a re-scan and never a wrong
    /// answer — `UsageStore.readStats`' judgement, for the same reason.
    public static func read(_ value: JSONValue) -> TranscriptWatermarks {
        guard value.member("version")?.asNumber == 1,
              let files = value.member("files")?.asArray
        else { return TranscriptWatermarks() }
        return TranscriptWatermarks(records: files.compactMap(TranscriptWatermark.init))
    }
}
