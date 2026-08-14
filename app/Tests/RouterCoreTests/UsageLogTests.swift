import Foundation
import Testing
@testable import RouterCore

/// `UsageStore`'s log: the ring, the rotation boundary, and N5's byte-offset cut.
///
/// These three were specified (B50, B51) and had **no test**. Nothing in the suite referenced
/// `ringSize`, `maxLogBytes` or `tailWindowBytes`, and the constant's own doc comment claimed it was
/// "tested at the boundary rather than near it" — a claim about evidence that did not exist. The
/// recorded fixtures cannot reach any of this: `usage.json` is a handful of records, so a store that
/// never rotated and read the whole log would reproduce it exactly.
@Suite("The usage log")
struct UsageLogTests {
    private static let statsPath = "/tmp/usage-log-tests/stats.json"
    private static let logPath = "/tmp/usage-log-tests/usage.jsonl"

    private static func line(_ index: Int, padding: String = "") -> String {
        #"{"ts":"2026-08-14T00:00:00.000Z","server":"s","tool":"t\#(index)","#
            + #""ok":true,"ms":1,"cold":false,"pad":"\#(padding)"}"#
    }

    private static func store(log: Data) -> (UsageStore, MemoryFileSystem) {
        let fileSystem = MemoryFileSystem()
        try? fileSystem.createDirectory(atPath: "/tmp/usage-log-tests")
        try? fileSystem.writeFile(log, atPath: logPath)
        let store = UsageStore(
            logPath: logPath,
            statsPath: statsPath,
            fileSystem: fileSystem,
            clock: ManualClock(milliseconds: 1_770_000_000_000)
        )
        return (store, fileSystem)
    }

    // MARK: - B50, the ring

    /// `readTail` ends `out.slice(-500)`. A log holding more than the ring is cut to the **last**
    /// 500, in order — not the first 500, and not all of them.
    @Test("the ring keeps the last 500 records of a longer log")
    func ringKeepsTheLastFiveHundred() {
        let log = (0 ..< 640).map { Self.line($0) }.joined(separator: "\n") + "\n"
        let (store, _) = Self.store(log: Data(log.utf8))
        // `recent` reverses, so the newest is first. `limit: nil` is the reference's 200 default,
        // which would hide the boundary; ask for more than the ring can hold.
        let all = store.recent(limit: 10000, server: nil, cwd: nil)
        #expect(all.count == UsageStore.ringSize, "the ring held \(all.count), not 500")
        #expect(all.first?.tool == "t639", "the newest record is not the last line of the log")
        #expect(all.last?.tool == "t140", "the ring kept the wrong 500 — it cut from the wrong end")
    }

    /// A torn final line is normal after a hard kill (B52) and is skipped rather than failing the
    /// whole read. Stated here because the ring test above would pass over a truncated log by
    /// accident.
    @Test("a torn final line is skipped and the rest survives")
    func tornFinalLineIsSkipped() {
        let log = Self.line(0) + "\n" + Self.line(1) + "\n" + #"{"ts":"2026-08-14T00:00"#
        let (store, _) = Self.store(log: Data(log.utf8))
        let all = store.recent(limit: 10000, server: nil, cwd: nil)
        #expect(all.count == 2, "a torn tail took \(all.count) records with it")
    }

    // MARK: - B50, the rotation boundary

    /// The reference is `if (statSync(path).size < MAX_LOG_BYTES) return`, so it rotates at
    /// `>=`, and 8 MiB **exactly** rotates. Asserted at the boundary and one byte below it, which is
    /// the only pair that distinguishes `>=` from `>`.
    @Test(
        "rotation happens at exactly 8 MiB, not one byte later",
        arguments: [
            (UsageStore.maxLogBytes - 1, false),
            (UsageStore.maxLogBytes, true),
            (UsageStore.maxLogBytes + 1, true)
        ]
    )
    func rotatesAtTheBoundary(_ size: Int, _ expectRotation: Bool) {
        // A short log so the ring warm-up is cheap; the size the guard reads comes from the stamp,
        // which the double reports from the bytes actually stored.
        let padding = String(repeating: "x", count: max(0, size - Data(Self.line(0).utf8).count - 1))
        let log = Self.line(0, padding: padding) + "\n"
        let (store, fileSystem) = Self.store(log: Data(log.utf8))
        let stamped = (try? fileSystem.attributes(atPath: Self.logPath).size) ?? 0

        store.record(UsageRecord(
            ts: "2026-08-14T00:00:01.000Z",
            server: "s",
            tool: "t",
            ok: true,
            ms: 1,
            cold: false
        ))
        store.flush()

        let rotated = fileSystem.fileExists(atPath: "\(Self.logPath).1")
        #expect(
            rotated == expectRotation,
            """
            a log stamped \(stamped) bytes \(rotated ? "rotated" : "did not rotate"), \
            against a threshold of \(UsageStore.maxLogBytes)
            """
        )
    }

    // MARK: - B51 / N5, the byte offset applied to a UTF-16 string

    /// **The ported defect.** The reference computes its cut point from `statSync().size` — a
    /// **byte** count — and applies it to `raw.indexOf('\n', offset)`, where `raw` is a UTF-16
    /// string. For an all-ASCII log the two coincide and nothing shows. For a log carrying
    /// multi-byte text they do not, and the reference cuts at a different character than a
    /// byte-correct implementation would.
    ///
    /// This is the input that makes the difference **maximal**, and it is chosen deliberately.
    /// Every padding character is `é`: two bytes in UTF-8, one unit in UTF-16. So a log of just over
    /// 1 MiB is just over 512 Ki UTF-16 units, and `size - 512 KiB` therefore lands **past the end**
    /// of the string. The reference keeps nothing. A byte-correct implementation would keep the last
    /// 512 KiB of bytes — roughly half the records — so the two answers are not close: they are
    /// "everything recent" against "nothing at all".
    ///
    /// Parity is what R4 measures, so nothing here is a bug to fix. It is a defect to *reproduce*,
    /// and this test is what stops a later reader tidying it into a divergence.
    @Test("a non-ASCII log is cut where the reference cuts it, not where the bytes say")
    func byteOffsetIsAppliedToUTF16() {
        // 800 `é` against ~80 bytes of ASCII JSON per line puts the byte:unit ratio near 1.9, and
        // the log is grown to three windows so that `size - 512 KiB` clears the whole UTF-16 length
        // with margin. Both facts are asserted below rather than trusted.
        let padding = String(repeating: "é", count: 800)
        var lines: [String] = []
        var bytes = 0
        var index = 0
        while bytes <= UsageStore.tailWindowBytes * 3 {
            let line = Self.line(index, padding: padding)
            lines.append(line)
            bytes += Data(line.utf8).count + 1
            index += 1
        }
        let log = lines.joined(separator: "\n") + "\n"
        let data = Data(log.utf8)
        let units = Array(log.utf16).count

        // The premise of the test, asserted rather than assumed: the byte count must exceed the
        // UTF-16 length by enough that the offset overshoots the string entirely.
        #expect(data.count > UsageStore.tailWindowBytes, "the log is too small to trigger the cut")
        #expect(
            data.count - UsageStore.tailWindowBytes >= units,
            "this log does not overshoot (\(data.count) bytes, \(units) units) — the test proves nothing"
        )

        let (store, _) = Self.store(log: data)
        let kept = store.recent(limit: 10000, server: nil, cwd: nil).count
        #expect(
            kept == 0,
            """
            the tail kept \(kept) records. The reference keeps none here, because its byte-derived \
            offset lands past the end of the UTF-16 string. Keeping records means the offset was \
            corrected to a byte-accurate one — which is a divergence R4 will report.
            """
        )
    }

    /// The other side of the same clause, so the test above cannot be satisfied by a `readTail` that
    /// simply returns nothing whenever the log is large. Here the padding is ASCII, bytes and UTF-16
    /// units coincide, the offset lands inside the string, and records survive.
    @Test("an ASCII log over the window keeps its tail, cut at a line boundary")
    func asciiLogKeepsItsTail() {
        let padding = String(repeating: "x", count: 400)
        var lines: [String] = []
        var bytes = 0
        var index = 0
        while bytes <= UsageStore.tailWindowBytes + 50000 {
            let line = Self.line(index, padding: padding)
            lines.append(line)
            bytes += Data(line.utf8).count + 1
            index += 1
        }
        let log = lines.joined(separator: "\n") + "\n"
        let (store, _) = Self.store(log: Data(log.utf8))
        let all = store.recent(limit: 10000, server: nil, cwd: nil)

        #expect(!all.isEmpty, "an ASCII log over the window lost its whole tail")
        #expect(all.count <= UsageStore.ringSize, "the ring bound was not applied")
        #expect(all.first?.tool == "t\(index - 1)", "the newest record is not the last line")
        // Cut at a line boundary: every surviving record parsed, so no partial line was fed in.
        #expect(all.allSatisfy { $0.server == "s" }, "a partial line was parsed as a record")
    }
}
