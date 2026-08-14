#if os(macOS)
    import Foundation
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The fixtures the Activity recovery suites build their scenarios from.
    ///
    /// Shared rather than duplicated because the two suites that use them — the one about the
    /// **record window** and the one about the **subscription** — are two halves of one subject, and
    /// a fixture that drifted between them would make their results incomparable. `window(newest:)`
    /// in particular encodes the router's ring semantics: a contiguous newest-first slice, which is
    /// the fact every merge test is written against.
    @MainActor
    enum ActivityFixture {
        /// A fixed instant. Every relative time on this surface is measured from *now*, so a test
        /// that read the wall clock would prove a different thing on every run.
        static let now = Date(timeIntervalSince1970: 1_755_166_918)

        static func model(
            _ scenario: FixtureControlAPIClient.Scenario = .populated,
            source: (any ActivityEventSource)? = nil
        ) -> ActivityModel {
            let model = ActivityModel(
                client: FixtureControlAPIClient(scenario), source: source, clock: { now }
            )
            // A board is on screen in every scenario below, which is what `beginSession` says. A
            // model nobody is looking at refuses to reconnect, and that is its own test.
            model.beginSession()
            return model
        }

        static func record(
            ts: String = "2026-08-14T09:41:58.412Z",
            tool: String = "browser_navigate",
            pid: Int? = 51310,
            client: String? = "claude"
        ) -> CallRecord {
            CallRecord(
                ts: ts, server: "obscura", tool: tool, ok: true, ms: 42, cold: false,
                pid: pid, cwd: "/Users/x/Dev/mcp-router", project: "mcp-router",
                client: client, err: nil
            )
        }

        /// A distinct, ordered timestamp per index, so 520 records have 520 ids.
        static func timestamp(_ index: Int) -> String {
            String(format: "2026-08-14T08:%02d:%02d.000Z", index / 60, index % 60)
        }

        /// `capacity` records, newest first, ending at `newest`.
        static func window(newest: Int) -> [CallRecord] {
            stride(from: newest, through: newest - ActivityRecords.capacity + 1, by: -1)
                .map { record(ts: timestamp($0), tool: "call\($0)") }
        }
    }
#endif
