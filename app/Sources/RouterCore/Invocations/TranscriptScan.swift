import Foundation

/// A harness's transcript corpus: what it is called, and where its session files are.
///
/// **The root is supplied, never guessed.** Nothing here defaults to `~/.claude`. A router that
/// discovered a corpus and started reading it would be reading somebody's sessions because it could,
/// and the difference between that and this is one line of configuration that a person typed.
public struct TranscriptSource: Sendable, Hashable {
    public let harness: String
    public let root: String

    public init(harness: String, root: String) {
        self.harness = harness
        self.root = root
    }
}

/// Everything one scan produced.
public struct TranscriptScanResult: Sendable {
    public let events: [InvocationEvent]
    public let accounting: TranscriptAccounting
    public let watermarks: TranscriptWatermarks

    public init(
        events: [InvocationEvent],
        accounting: TranscriptAccounting,
        watermarks: TranscriptWatermarks
    ) {
        self.events = events
        self.accounting = accounting
        self.watermarks = watermarks
    }
}

/// Reading invocations out of a harness's own session transcripts. **It writes nothing and it sends
/// nothing.**
///
/// ## What it takes off each line, and what it leaves
///
/// Four things: the line's `timestamp`, and — only inside an assistant `tool_use` block — the tool's
/// `name` and, for a `Skill` call, its `skill` input. That is the whole list.
///
/// A line is parsed in full, because a JSONL line has to be parsed to be read at all. What the
/// parse produces is a local that goes out of scope at the end of the loop; the only thing that
/// survives this function is an ``InvocationEvent``, and that type has **no member** for a prompt,
/// an argument, a tool result, a working directory, a git branch or a session id. The privacy claim
/// in `spec-F5.md` §3 rests on that absence rather than on this reader being careful, and
/// `InvocationEvent.wireKeys` is what makes it fail if it stops being true.
///
/// ## Why it is incremental
///
/// Measured 2026-08-29: 59,476 files, 19.5 GB. See ``TranscriptWatermark`` for the arithmetic. A
/// file whose size and mtime both match its watermark is not opened.
///
/// **A known cost, stated: a file that grew is read whole and then sliced at the offset.** The
/// `FileSystem` seam has no partial read, and adding one is a change to a port six other types
/// depend on. So the saving here is over files that did not change — which is nearly all of them,
/// nearly all the time — and not over the tail of one that did.
public enum TranscriptScan {
    /// The member holding a line's instant.
    static let timestampKey = "timestamp"
    /// Where a `tool_use` block lives on an assistant line.
    static let messageKey = "message"
    static let contentKey = "content"
    static let typeKey = "type"
    static let toolUseType = "tool_use"
    static let nameKey = "name"
    static let inputKey = "input"
    static let skillKey = "skill"

    /// Scan a named set of files, resuming from `watermarks`.
    ///
    /// `files` is passed in rather than walked here, and the split is `DiskExtensionStore`'s: a
    /// directory walk is a filesystem property that the in-memory double does not reproduce, so the
    /// walk is driven against real temporary directories and this — where every rule lives — is
    /// driven against the double.
    public static func scan(
        files: [String],
        harness: String,
        fileSystem: any FileSystem,
        watermarks: TranscriptWatermarks
    ) -> TranscriptScanResult {
        var events: [InvocationEvent] = []
        var accounting = TranscriptAccounting()
        var updated = watermarks

        for path in files {
            guard let stamp = try? fileSystem.attributes(atPath: path) else {
                accounting.filesUnreadable += 1
                continue
            }
            let disposition = TranscriptWatermark.disposition(
                for: stamp, against: watermarks.watermark(for: path)
            )
            if case .unchanged = disposition {
                accounting.filesSkipped += 1
                continue
            }
            guard let data = try? fileSystem.readFile(atPath: path) else {
                accounting.filesUnreadable += 1
                continue
            }
            var start = 0
            if case let .resume(offset) = disposition {
                start = min(offset, data.count)
            } else if watermarks.watermark(for: path) != nil {
                accounting.filesReread += 1
            }
            accounting.filesRead += 1
            let consumed = absorb(
                data: data, from: start, harness: harness,
                into: &events, accounting: &accounting
            )
            updated.set(TranscriptWatermark(
                path: path,
                size: stamp.size,
                modifiedMilliseconds: stamp.modified.timeIntervalSince1970 * 1000,
                offset: start + consumed
            ))
        }
        return TranscriptScanResult(events: events, accounting: accounting, watermarks: updated)
    }

    /// Consume whole lines from `start`, returning how many bytes were consumed.
    ///
    /// A trailing fragment with no newline after it is **not** consumed. A live session is being
    /// appended to as this runs, so the last line is routinely half-written; leaving it outside the
    /// offset is what lets the next scan read it whole rather than counting it as unparseable and
    /// never looking again.
    private static func absorb(
        data: Data,
        from start: Int,
        harness: String,
        into events: inout [InvocationEvent],
        accounting: inout TranscriptAccounting
    ) -> Int {
        let bytes = [UInt8](data)
        var cursor = start
        var consumed = 0
        while cursor < bytes.count {
            guard let newline = bytes[cursor...].firstIndex(of: 0x0A) else { break }
            let line = Array(bytes[cursor ..< newline])
            consumed += newline - cursor + 1
            cursor = newline + 1
            guard !line.isEmpty else { continue }
            accounting.linesRead += 1
            absorb(line: line, harness: harness, into: &events, accounting: &accounting)
        }
        return consumed
    }

    private static func absorb(
        line: [UInt8],
        harness: String,
        into events: inout [InvocationEvent],
        accounting: inout TranscriptAccounting
    ) {
        guard let parsed = try? JSONParser.parse(line) else {
            accounting.unparseable += 1
            return
        }
        guard let timestamp = parsed.member(timestampKey)?.asString?.string,
              VersionLedger.isOrderable(timestamp)
        else {
            accounting.withoutTimestamp += 1
            return
        }
        guard let blocks = parsed.member(messageKey)?.member(contentKey)?.asArray else {
            accounting.notAnInvocation += 1
            return
        }
        var found = false
        for block in blocks where block.member(typeKey)?.asString?.string == toolUseType {
            found = true
            record(block, at: timestamp, harness: harness, into: &events, accounting: &accounting)
        }
        if !found { accounting.notAnInvocation += 1 }
    }

    private static func record(
        _ block: JSONValue,
        at timestamp: String,
        harness: String,
        into events: inout [InvocationEvent],
        accounting: inout TranscriptAccounting
    ) {
        guard let name = block.member(nameKey)?.asString?.string,
              let reference = CapabilityReference.parse(
                  toolName: name,
                  skillInput: block.member(inputKey)?.member(skillKey)?.asString?.string
              )
        else {
            accounting.unnamedTool += 1
            return
        }
        guard let event = reference.event(at: timestamp, harness: harness) else {
            accounting.builtInTool += 1
            return
        }
        events.append(event)
    }
}
