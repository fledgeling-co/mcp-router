import Foundation
import Testing
@testable import MCPRouterKit

/// The Activity board's data layer: the window, the de-duplication, the groupings and the filters.
///
/// Every one of these is a claim the board rests on and none of them needs a window to check, which
/// is the point of the split — the defects a log surface actually ships are in the algebra, not in
/// the layout.
@Suite("Activity — the loaded window")
struct ActivityRecordsTests {
    /// A record with everything the router sends, so a test can vary one field at a time.
    static func record(
        ts: String = "2026-08-14T09:41:58.412Z",
        server: String = "obscura",
        tool: String = "browser_navigate",
        ok: Bool = true,
        ms: Int = 42,
        cold: Bool = false,
        pid: Int? = 51310,
        cwd: String? = "/Users/x/Dev/mcp-router",
        project: String? = "mcp-router",
        client: String? = "claude",
        err: String? = nil
    ) -> CallRecord {
        CallRecord(
            ts: ts, server: server, tool: tool, ok: ok, ms: ms, cold: cold,
            pid: pid, cwd: cwd, project: project, client: client, err: err
        )
    }

    // MARK: - B19: the window is bounded, and bounded at the router's own number

    @Test("the window caps at the router's ring size rather than growing without limit")
    func windowIsBounded() {
        #expect(
            ActivityRecords.capacity == 500,
            "the cap is RING_SIZE in src/usage.ts; a different number means one of the two moved"
        )

        var records = ActivityRecords(records: [], since: "s")
        for index in 0 ..< (ActivityRecords.capacity + 50) {
            records.prepend(Self.record(ts: "2026-08-14T09:00:\(index).000Z", tool: "t\(index)"))
        }
        #expect(records.count == ActivityRecords.capacity)
        // Newest first, so the *oldest* is what falls off — a live feed must never push the newest
        // call out of a list whose whole promise is that new calls appear at the top.
        #expect(records.records.first?.tool == "t\(ActivityRecords.capacity + 49)")
    }

    @Test("a backfill longer than the cap is truncated on the way in, not after")
    func initialiserRespectsTheCap() {
        let many = (0 ..< 700).map { Self.record(ts: "2026-08-14T09:00:\($0).000Z", tool: "t\($0)") }
        #expect(ActivityRecords(records: many, since: "s").count == ActivityRecords.capacity)
    }

    // MARK: - B20: the two sources overlap by construction

    @Test("a record already in the window is not prepended a second time")
    func deduplicatesAgainstTheBackfill() {
        let one = Self.record()
        var records = ActivityRecords(records: [one], since: "s")
        #expect(records.prepend(one) == false, "the stream re-delivering a backfilled call")
        #expect(records.count == 1)
    }

    @Test("de-duplication is by the router's own identity, not by object equality")
    func deduplicatesByIdentity() {
        let one = Self.record()
        // Same ts, server, tool and pid — the four `CallRecord.id` is built from — but a different
        // duration. This is the same call reported twice, and a log that shows it twice is a log
        // nobody can count from.
        var second = one
        second.ms = 999
        var records = ActivityRecords(records: [one], since: "s")
        #expect(records.prepend(second) == false)
        #expect(records.count == 1)
    }

    @Test("a backfill carrying the same call twice keeps it once")
    func initialiserDeduplicates() {
        let one = Self.record()
        #expect(ActivityRecords(records: [one, one, one], since: "s").count == 1)
    }

    // MARK: - B13: an option exists if and only if a record supports it

    @Test("every filter option has at least one record behind it, and the count is that many")
    func optionsAreGroupings() {
        let records = ActivityRecords(
            records: [
                Self.record(ts: "…1", pid: 1, cwd: "/a", project: "a"),
                Self.record(ts: "…2", pid: 1, cwd: "/a", project: "a"),
                Self.record(ts: "…3", pid: 2, cwd: "/b", project: "b")
            ],
            since: "s"
        )

        let sessions = records.sessions()
        #expect(sessions.count == 2)
        #expect(sessions.first?.calls == 2, "ordered by count, most first")
        for option in sessions {
            let matching = records.records.filter { option.key.matches($0) }
            #expect(
                matching.count == option.calls,
                "\(option.label) offers \(option.calls) and \(matching.count) records match"
            )
            #expect(!matching.isEmpty, "an option no record supports would return nothing")
        }

        let directories = records.directories()
        #expect(directories.count == 2)
        for option in directories {
            #expect(records.records.contains { option.key.matches($0) })
        }
    }

    @Test("the menus offer nothing at all when nothing has loaded")
    func noRecordsMeansNoOptions() {
        let empty = ActivityRecords(records: [], since: "s")
        #expect(empty.sessions().isEmpty)
        #expect(empty.directories().isEmpty)
    }

    // MARK: - B15: the router's own failure to attribute is a group, not a gap

    @Test("a record the router could not attribute is grouped, never dropped")
    func unattributedIsItsOwnGroup() {
        let records = ActivityRecords(
            records: [
                Self.record(ts: "…1", pid: 51310, cwd: "/a", project: "a"),
                Self.record(ts: "…2", pid: nil, cwd: nil, project: nil, client: nil)
            ],
            since: "s"
        )
        #expect(records.count == 2, "an unattributed call is still a call")

        let sessions = records.sessions()
        #expect(sessions.contains { $0.key == .unattributed })
        #expect(sessions.first { $0.key == .unattributed }?.calls == 1)

        let directories = records.directories()
        #expect(directories.contains { $0.key == .unattributed })
    }

    /// The reason `SessionKey` is an enum rather than `Int?`: with an optional, "no pid" and "no
    /// filter" are the same value, and *show me the unattributed calls* silently becomes *show me
    /// everything*.
    @Test("the unattributed key matches only unattributed records")
    func unattributedDoesNotMatchEverything() {
        let attributed = Self.record(pid: 51310)
        let orphan = Self.record(pid: nil, cwd: nil)
        #expect(SessionKey.unattributed.matches(orphan))
        #expect(!SessionKey.unattributed.matches(attributed))
        #expect(DirectoryKey.unattributed.matches(orphan))
        #expect(!DirectoryKey.unattributed.matches(attributed))
    }

    @Test("an empty cwd is unattributed, not a directory named nothing")
    func emptyDirectoryIsUnattributed() {
        #expect(DirectoryKey(record: Self.record(cwd: "")) == .unattributed)
    }

    // MARK: - B14: the filters narrow, and compose

    @Test("each filter narrows on its own and the two compose")
    func filtersNarrowAndCompose() {
        let records = ActivityRecords(
            records: [
                Self.record(ts: "…1", pid: 1, cwd: "/a"),
                Self.record(ts: "…2", pid: 1, cwd: "/b"),
                Self.record(ts: "…3", pid: 2, cwd: "/a")
            ],
            since: "s"
        )

        let bySession = records.applying(ActivityFilter(session: .attributed(pid: 1)))
        #expect(bySession.visible.count == 2)
        #expect(bySession.total == 3, "the total is what it was drawn from, not what survived")

        let byDirectory = records.applying(ActivityFilter(directory: .path(cwd: "/a")))
        #expect(byDirectory.visible.count == 2)

        let both = records.applying(
            ActivityFilter(
                session: .attributed(pid: 1),
                directory: .path(cwd: "/a")
            )
        )
        #expect(both.visible.count == 1)
        #expect(both.total == 3)
    }

    /// A session filter is matched on `pid` alone. The client name travels with the key for display
    /// and must not narrow the match — the router reports it per connection and can legitimately
    /// send it for one call and not the next.
    @Test("the session match is on pid, and the client name does not narrow it")
    func sessionMatchesOnPid() {
        let key = SessionKey.attributed(pid: 1)
        #expect(key.matches(Self.record(pid: 1, client: nil)))
        #expect(key.matches(Self.record(pid: 1, client: "codex")))
        #expect(!key.matches(Self.record(pid: 2, client: "claude")))
    }

    @Test("a filter matching nothing is distinguishable from a window holding nothing")
    func filteredToNothingIsNotEmpty() {
        let records = ActivityRecords(records: [Self.record(pid: 1)], since: "s")
        let result = records.applying(ActivityFilter(session: .attributed(pid: 999)))
        #expect(result.visible.isEmpty)
        #expect(result.total == 1)
        #expect(result.isFilteredToNothing, "the state that says so rather than 'no calls yet'")

        let nothing = ActivityRecords(records: [], since: "s").applying(.none)
        #expect(!nothing.isFilteredToNothing, "an empty window is the empty state, not a filter miss")
    }

    @Test("an inactive filter admits everything without touching the array")
    func inactiveFilterIsIdentity() {
        let records = ActivityRecords(
            records: [Self.record(ts: "…1"), Self.record(ts: "…2")],
            since: "s"
        )
        let result = records.applying(.none)
        #expect(result.visible.count == records.count)
        #expect(result.hiddenCount == 0)
    }
}
