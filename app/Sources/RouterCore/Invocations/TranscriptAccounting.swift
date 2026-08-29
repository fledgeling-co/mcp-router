import Foundation

/// What a scan was given, against what it kept.
///
/// Every field here is a class of thing the reader **discarded**, counted rather than dropped. The
/// rule is `UsageInsights.unreadableLines`' one directory over and `planning/reader-accounting.py`'s
/// across the whole repository: a count of what parsed is not a count of what was there, and a
/// reader whose pass and whose could-not-read look identical from the outside has measured nothing.
///
/// Two of these are not theoretical. Measured over a 400-file random sample of this machine's
/// Claude Code corpus on 2026-08-29: **0 of 20,268 lines failed to parse**, and **936 of them
/// carried no `timestamp`**. So `unparseable` is the rare class and `withoutTimestamp` is a real
/// and sizeable one — the opposite of what a reader would guard for by instinct.
public struct TranscriptAccounting: Sendable, Hashable {
    /// Files the watermark said were unchanged, so they were never opened.
    public var filesSkipped = 0
    /// Files opened and read.
    public var filesRead = 0
    /// Files that **shrank** since the watermark. An offset into a file that got smaller points at
    /// different bytes, so these are re-read from zero rather than resumed, and saying so is the
    /// difference between a resumed read and a silently corrupted one.
    public var filesReread = 0
    /// Files whose bytes could not be read at all.
    public var filesUnreadable = 0
    public var linesRead = 0
    /// Not JSON. A torn last line is ordinary after a hard kill and costs the line, never the file.
    public var unparseable = 0
    /// Parsed, and carries no orderable timestamp. Produces no event, because an invocation with no
    /// moment cannot be placed against a version boundary — which is the whole subject here.
    public var withoutTimestamp = 0
    /// Parsed and timestamped and holds no tool call. The bulk of every transcript.
    public var notAnInvocation = 0
    /// A tool call whose name is missing or is not a shape this reader can attribute.
    public var unnamedTool = 0
    /// A tool call that is one of the harness's own built-ins — `Bash`, `Read`, `Edit` and the
    /// rest. Real calls, and not invocations of a skill, a plugin or a server, so they belong to no
    /// capability and are counted separately from a line that held no call at all.
    ///
    /// **This is the largest class by far.** Measured over a 200-file sample on 2026-08-29: of
    /// 3,320 `tool_use` blocks, 2,429 were `Bash`, 15 were `Skill` and 64 were `mcp__…`. Folding
    /// these into `notAnInvocation` would hide the ratio the reader's own yield depends on.
    public var builtInTool = 0

    public init() {}

    /// The keys a wire member carries, in order. Named so a route cannot report a subset of the
    /// accounting while looking complete.
    public static let wireKeys = [
        "filesSkipped", "filesRead", "filesReread", "filesUnreadable",
        "linesRead", "unparseable", "withoutTimestamp", "notAnInvocation", "unnamedTool",
        "builtInTool"
    ]

    public var value: JSONValue {
        .object([
            JSONMember(key: "filesSkipped", value: .number(Double(filesSkipped))),
            JSONMember(key: "filesRead", value: .number(Double(filesRead))),
            JSONMember(key: "filesReread", value: .number(Double(filesReread))),
            JSONMember(key: "filesUnreadable", value: .number(Double(filesUnreadable))),
            JSONMember(key: "linesRead", value: .number(Double(linesRead))),
            JSONMember(key: "unparseable", value: .number(Double(unparseable))),
            JSONMember(key: "withoutTimestamp", value: .number(Double(withoutTimestamp))),
            JSONMember(key: "notAnInvocation", value: .number(Double(notAnInvocation))),
            JSONMember(key: "unnamedTool", value: .number(Double(unnamedTool))),
            JSONMember(key: "builtInTool", value: .number(Double(builtInTool)))
        ])
    }

    /// Everything the reader was handed and did not turn into an event.
    ///
    /// A single figure a surface can put beside a count of events, so the two reconcile. Without it
    /// "1,204 invocations" is a number with no denominator, which is the shape this repository's
    /// gate family exists to refuse.
    public var discarded: Int {
        unparseable + withoutTimestamp + notAnInvocation + unnamedTool + builtInTool
    }
}
