import Foundation
import Testing
@testable import RouterCore

/// R26 — the monitor: what it reads off disk, and what the throttle will and will not swallow.
@Suite("R26 auth expiry monitor")
struct AuthExpiryMonitorTests {
    private static let now: Double = 1_770_000_000_000
    private static let authDir = "/router/auth"

    private static func store(_ records: [String: String]) -> FileAuthStore {
        let fileSystem = AuthTestFileSystem()
        for (server, json) in records {
            fileSystem.memory.seed(
                json, atPath: AuthPaths.recordPath(authDir: authDir, server: JSString(server))
            )
        }
        return FileAuthStore(authDir: authDir, fileSystem: fileSystem)
    }

    private static func monitor(
        _ records: [String: String],
        upstreams: [UpstreamConfig] = [httpUpstream("remote"), stdioUpstream("local")],
        policy: AuthExpiryPolicy = .standard
    ) -> AuthExpiryMonitor {
        AuthExpiryMonitor(
            upstreams: upstreams, policy: policy, auth: store(records), verb: "mcp-router"
        )
    }

    private static func token(expiresIn seconds: Double?, authorizedAgoMs: Double) -> String {
        var members = "\"access_token\":\"a\""
        if let seconds { members += ",\"expires_in\":\(seconds)" }
        let stamp = JSDate.iso8601(milliseconds: now - authorizedAgoMs)
        return "{\"tokens\":{\(members)},\"authorizedAt\":\"\(stamp)\"}"
    }

    private static func expiringSoon() -> String {
        token(expiresIn: 3600, authorizedAgoMs: 1_800_000)
    }

    private static func alreadyExpired() -> String {
        token(expiresIn: 3600, authorizedAgoMs: 7_200_000)
    }

    // MARK: - Reading

    @Test("E10 — every declared upstream is present, in configuration order")
    func reportCoversEveryUpstream() async {
        let monitor = Self.monitor(["remote": Self.expiringSoon()])

        let report = await monitor.report(manifest: .empty, nowMilliseconds: Self.now)
        #expect(report.records.map(\.server) == ["remote", "local"])
        #expect(report.records[0].state == .expiring)
        // A server that cannot be authorised is present and says so, rather than being omitted:
        // an absent row and a server this router does not know about are different problems.
        #expect(report.records[1].state == .notApplicable)
    }

    @Test("E11 — the expiry is read off the record on disk, not remembered")
    func theReportFollowsTheFile() async {
        let fileSystem = AuthTestFileSystem()
        let path = AuthPaths.recordPath(authDir: Self.authDir, server: JSString("remote"))
        fileSystem.memory.seed(Self.expiringSoon(), atPath: path)
        let monitor = AuthExpiryMonitor(
            upstreams: [httpUpstream("remote")], policy: .standard,
            auth: FileAuthStore(authDir: Self.authDir, fileSystem: fileSystem)
        )

        let before = await monitor.report(manifest: .empty, nowMilliseconds: Self.now)
        #expect(before.records[0].state == .expiring)

        // Re-authorised, from outside: the store is stateless by design and re-reads every call.
        fileSystem.memory.seed(
            Self.token(expiresIn: 604_800, authorizedAgoMs: 0), atPath: path
        )
        let after = await monitor.report(manifest: .empty, nowMilliseconds: Self.now)
        #expect(after.records[0].state == .valid)
        #expect(after.records[0].expiresAtMs != before.records[0].expiresAtMs)
    }

    // MARK: - The throttle

    @Test("E12 — the same fact is said once, then withheld until the window has passed")
    func repetitionIsThrottled() async {
        let monitor = Self.monitor(["remote": Self.expiringSoon()])

        let first = await monitor.claim(manifest: .empty, nowMilliseconds: Self.now)
        #expect(first.count == 1)
        #expect(first[0].kind == .expiring)

        let immediately = await monitor.claim(manifest: .empty, nowMilliseconds: Self.now + 1000)
        #expect(immediately.isEmpty)

        let later = await monitor.claim(
            manifest: .empty,
            nowMilliseconds: Self.now + Double(AuthExpiryPolicy.standard.renotifyAfterMs)
        )
        #expect(later.count == 1)
    }

    @Test("E13 — an escalation is never withheld, however recently the warning went out")
    func expiringBecomingExpiredAlwaysGoesOut() async {
        // A renotify window of a year, so nothing can go out on elapsed time alone. If the
        // escalation still arrives, it arrived because the KIND changed and for no other reason.
        let policy = AuthExpiryPolicy(warnWithinMs: 86_400_000, renotifyAfterMs: 31_536_000_000)
        let monitor = Self.monitor(["remote": Self.expiringSoon()], policy: policy)

        let warning = await monitor.claim(manifest: .empty, nowMilliseconds: Self.now)
        #expect(warning.count == 1)
        #expect(warning[0].kind == .expiring)

        // Half an hour on, the same token is past its expiry. Nothing on disk changed.
        let escalated = await monitor.claim(
            manifest: .empty, nowMilliseconds: Self.now + 1_800_001
        )
        #expect(escalated.count == 1)
        #expect(escalated[0].kind == .expired)

        // And the repeat after it is throttled again, so the arm above is the escalation rather
        // than the throttle simply not working.
        let repeated = await monitor.claim(
            manifest: .empty, nowMilliseconds: Self.now + 1_800_002
        )
        #expect(repeated.isEmpty)
    }

    @Test("E14 — a replaced credential is a new fact, not a repeat of the old one")
    func aMovedExpiryIsNotThrottled() async {
        let fileSystem = AuthTestFileSystem()
        let path = AuthPaths.recordPath(authDir: Self.authDir, server: JSString("remote"))
        fileSystem.memory.seed(Self.alreadyExpired(), atPath: path)
        let policy = AuthExpiryPolicy(warnWithinMs: 86_400_000, renotifyAfterMs: 31_536_000_000)
        let monitor = AuthExpiryMonitor(
            upstreams: [httpUpstream("remote")], policy: policy,
            auth: FileAuthStore(authDir: Self.authDir, fileSystem: fileSystem)
        )

        #expect(await monitor.claim(manifest: .empty, nowMilliseconds: Self.now).count == 1)
        // A second token, also already expired — the same KIND, a different expiry.
        fileSystem.memory.seed(
            Self.token(expiresIn: 60, authorizedAgoMs: 7_200_000), atPath: path
        )
        let second = await monitor.claim(manifest: .empty, nowMilliseconds: Self.now + 1)
        #expect(second.count == 1, "a different token's death is not the same notification")
    }

    @Test("E15 — resolving the authorisation clears the warning, and the next one is immediate")
    func recoveryDropsTheRecord() async {
        let fileSystem = AuthTestFileSystem()
        let path = AuthPaths.recordPath(authDir: Self.authDir, server: JSString("remote"))
        fileSystem.memory.seed(Self.expiringSoon(), atPath: path)
        let policy = AuthExpiryPolicy(warnWithinMs: 86_400_000, renotifyAfterMs: 31_536_000_000)
        let monitor = AuthExpiryMonitor(
            upstreams: [httpUpstream("remote")], policy: policy,
            auth: FileAuthStore(authDir: Self.authDir, fileSystem: fileSystem)
        )

        #expect(await monitor.claim(manifest: .empty, nowMilliseconds: Self.now).count == 1)
        #expect(await monitor.hasDelivered("remote"))

        fileSystem.memory.seed(Self.token(expiresIn: 604_800, authorizedAgoMs: 0), atPath: path)
        #expect(await monitor.claim(manifest: .empty, nowMilliseconds: Self.now + 1).isEmpty)
        #expect(await monitor.hasDelivered("remote") == false, "the warning is cleared, not aged out")
    }

    @Test("E16 — reading the report does not consume the notice")
    func reportingIsNotClaiming() async {
        let monitor = Self.monitor(["remote": Self.expiringSoon()])

        for _ in 0 ..< 3 {
            _ = await monitor.report(manifest: .empty, nowMilliseconds: Self.now)
        }
        #expect(await monitor.hasDelivered("remote") == false)
        #expect(await monitor.claim(manifest: .empty, nowMilliseconds: Self.now).count == 1)
    }

    // MARK: - What is and is not worth saying

    @Test("E17 — an unknown expiry is reported and is not notified about")
    func unknownIsInventoriedRatherThanAnnounced() async {
        let monitor = Self.monitor(["remote": Self.token(expiresIn: nil, authorizedAgoMs: 1000)])

        let report = await monitor.report(manifest: .empty, nowMilliseconds: Self.now)
        #expect(report.records[0].state == .unknown)
        #expect(report.records[0].unknownReason == .noLifetimeDeclared)
        // Not `valid`, and not a notification either: an alert for every date this router cannot
        // compute is one nobody can act on and one that never stops.
        #expect(await monitor.claim(manifest: .empty, nowMilliseconds: Self.now).isEmpty)
    }

    @Test("E18 — a refused credential is notified even while its clock says valid")
    func aRefusalIsItsOwnNotice() async throws {
        let monitor = Self.monitor(["remote": Self.token(expiresIn: 604_800, authorizedAgoMs: 0)])
        var manifest = Manifest.empty
        manifest.setEntry("remote", CachedServer(members: [
            JSONMember(
                key: JSString("error"),
                value: .string(JSString("[-32603] Internal error: Authentication required"))
            )
        ]))

        #expect(await monitor.claim(manifest: .empty, nowMilliseconds: Self.now).isEmpty)
        let notices = await monitor.claim(manifest: manifest, nowMilliseconds: Self.now)
        let notice = try #require(notices.first)
        #expect(notice.kind == .refused)
        #expect(notice.command == "mcp-router auth remote")
    }

    @Test("E19 — with a refresh token held, no command is offered")
    func theRefreshTokenChangesTheRemedy() async throws {
        let stored = """
        {"tokens":{"access_token":"a","refresh_token":"r","expires_in":3600},\
        "authorizedAt":"\(JSDate.iso8601(milliseconds: Self.now - 7_200_000))"}
        """
        let monitor = Self.monitor(["remote": stored])

        let notice = try #require(
            await monitor.claim(manifest: .empty, nowMilliseconds: Self.now).first
        )
        #expect(notice.kind == .expired)
        #expect(notice.hasRefreshToken)
        // The `mobbin` rule as a notification: there is something to refresh from, so a command
        // telling its owner to authorise again would send them round a loop that cannot succeed.
        #expect(notice.command == nil)
    }
}
