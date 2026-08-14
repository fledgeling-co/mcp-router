import Foundation
import Testing
@testable import RouterCore

/// A probe that can enter the states the real machine will not enter on request.
///
/// This is the whole reason ``ProcessProbe`` exists. Every clause below describes a *failure* to
/// look — a pid that exits mid-scan, descriptors that cannot be listed, a socket that is not TCP —
/// and against `libproc` none of them is reachable from a test. Against this they all are, and the
/// call counters make "the cache skipped the second lookup" an assertion rather than a belief.
final class FakeProcessProbe: ProcessProbe, @unchecked Sendable {
    var pids: [Int32] = []
    /// Pids whose descriptors cannot be listed at all — the `nil` return, distinct from `[]`.
    var unlistable: Set<Int32> = []
    var ports: [Int32: [UInt16]] = [:]
    var names: [Int32: String] = [:]
    var cwds: [Int32: String] = [:]

    private(set) var nameCalls = 0
    private(set) var cwdCalls = 0

    func allPids() -> [Int32] {
        pids
    }

    func tcpLocalPorts(of pid: Int32) -> [UInt16]? {
        if unlistable.contains(pid) { return nil }
        return ports[pid] ?? []
    }

    func workingDirectory(of pid: Int32) -> String? {
        cwdCalls += 1
        return cwds[pid]
    }

    func processName(of pid: Int32) -> String? {
        nameCalls += 1
        return names[pid]
    }
}

/// B67, B69 and B70 — attribution, and specifically what it does when it cannot answer.
struct AttributionTests {
    private static func resolver(
        _ probe: FakeProcessProbe,
        selfPid: Int32 = 1,
        cache: AttributionCache = AttributionCache()
    ) -> LibProcPeerResolver {
        LibProcPeerResolver(selfPid: selfPid, probe: probe, cache: cache)
    }

    // MARK: - B67, the shape of a successful answer

    @Test("a named peer yields pid, name and cwd")
    func resolvesFullIdentity() {
        let probe = FakeProcessProbe()
        probe.pids = [1, 42]
        probe.ports = [42: [9000]]
        probe.names = [42: "claude"]
        probe.cwds = [42: "/Users/x/Dev/mcp-router"]

        let identity = Self.resolver(probe).identity(peerPort: 9000)
        #expect(identity.pid == 42)
        #expect(identity.client == "claude")
        #expect(identity.cwd == "/Users/x/Dev/mcp-router")
    }

    @Test("this process is never named as its own peer")
    func excludesSelf() {
        let probe = FakeProcessProbe()
        probe.pids = [7]
        probe.ports = [7: [9000]]
        probe.names = [7: "mcp-router"]

        #expect(Self.resolver(probe, selfPid: 7).identity(peerPort: 9000).isUnknown)
    }

    // MARK: - B69, one test per enumerated failure path

    @Test("no such pid yields an empty identity")
    func noSuchPid() {
        let probe = FakeProcessProbe()
        #expect(Self.resolver(probe).identity(peerPort: 9000).isUnknown)
    }

    @Test("a pid whose descriptors cannot be listed is skipped, not fatal")
    func unlistableDescriptors() {
        let probe = FakeProcessProbe()
        probe.pids = [10, 11]
        // 10's descriptors are unlistable — it exited between being listed and being inspected.
        probe.unlistable = [10]
        probe.ports = [11: [9000]]
        probe.names = [11: "node"]

        // The scan keeps going rather than failing at 10, and still finds 11.
        #expect(Self.resolver(probe).identity(peerPort: 9000).pid == 11)
    }

    @Test("an unlistable descriptor list on the only candidate yields an empty identity")
    func unlistableDescriptorsAlone() {
        let probe = FakeProcessProbe()
        probe.pids = [10]
        probe.unlistable = [10]
        #expect(Self.resolver(probe).identity(peerPort: 9000).isUnknown)
    }

    @Test("a process holding only non-TCP sockets yields an empty identity")
    func nonTCPSocket() {
        let probe = FakeProcessProbe()
        probe.pids = [12]
        // Listed successfully; nothing in it was an established TCP socket on this port.
        probe.ports = [12: []]
        probe.names = [12: "node"]
        #expect(Self.resolver(probe).identity(peerPort: 9000).isUnknown)
    }

    @Test("a pid exiting between the scan and the name read yields an empty identity, not a bare pid")
    func pidWithoutName() {
        let probe = FakeProcessProbe()
        probe.pids = [13]
        probe.ports = [13: [9000]]
        // No name: the process has gone. The reference reads pid and command from one lsof record,
        // so it cannot produce `{pid}` with no client — its scan would have found nothing at all.
        let identity = Self.resolver(probe).identity(peerPort: 9000)
        #expect(identity.isUnknown, "a named-less pid must not escape as a partial identity")
        #expect(identity.pid == nil)
    }

    /// B69's enumerated exception, and the reason it is an exception: B71 requires equality with
    /// the reference, and the reference emits `{ pid, client, cwd: cwd || undefined }`.
    @Test("a readable pid with an unreadable cwd keeps pid and name, matching the reference")
    func cwdFailureKeepsIdentity() {
        let probe = FakeProcessProbe()
        probe.pids = [14]
        probe.ports = [14: [9000]]
        probe.names = [14: "codex"]

        let identity = Self.resolver(probe).identity(peerPort: 9000)
        #expect(identity.pid == 14)
        #expect(identity.client == "codex")
        #expect(identity.cwd == nil)
        #expect(!identity.isUnknown)
    }

    @Test("the real probe answers nil for a pid that does not exist, rather than trapping")
    func realProbeHandlesDeadPid() {
        // The one path against `libproc` a test can enter deterministically: a pid far above
        // `kern.maxproc` cannot exist, which is the "process went away" case every guard above
        // stands in for. It must be nil, not a crash and not an empty string.
        let probe = LibProcProcessProbe()
        #expect(probe.processName(of: 999_999) == nil)
        #expect(probe.workingDirectory(of: 999_999) == nil)
        #expect(probe.tcpLocalPorts(of: 999_999) == nil)
    }

    @Test("the real probe can see this process's own listening socket")
    func realProbeSeesOwnSocket() throws {
        // Proves the libproc path is wired correctly — the fake above cannot show that, and a seam
        // whose real implementation is never exercised is a seam that can be quietly wrong.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        try #require(fd >= 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try #require(bound == 0)
        try #require(listen(fd, 1) == 0)
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        let port = UInt16(bigEndian: actual.sin_port)
        try #require(port != 0)

        let ports = LibProcProcessProbe().tcpLocalPorts(of: getpid())
        #expect(ports?.contains(port) == true, "libproc did not report a socket this process holds")
    }

    // MARK: - B70, the cache

    @Test("a second lookup for the same pid does not re-read the working directory")
    func cacheSkipsSecondLookup() {
        let probe = FakeProcessProbe()
        probe.pids = [20]
        probe.ports = [20: [9000]]
        probe.names = [20: "claude"]
        probe.cwds = [20: "/tmp/p"]
        let resolver = Self.resolver(probe)

        _ = resolver.identity(peerPort: 9000)
        _ = resolver.identity(peerPort: 9000)

        #expect(probe.cwdCalls == 1, "the cwd lookup ran twice — the pid cache is not consulted")
        #expect(probe.nameCalls == 1)
    }

    @Test("the cache holds 512 entries and the 513th clears it wholesale")
    func cacheBoundary() {
        let cache = AttributionCache()
        for pid in 1 ... 512 {
            cache.store(ClientIdentity(pid: Int32(pid), client: "c"), for: Int32(pid))
        }
        #expect(cache.count == 512, "the bound is checked after the insert, so 512 is retained")
        #expect(cache.identity(for: 1) != nil)

        cache.store(ClientIdentity(pid: 513, client: "c"), for: 513)
        // `if (size > 512) clear()` — wholesale, not an eviction. An LRU here would be a better
        // cache and a different one.
        #expect(cache.isEmpty, "the 513th entry must empty the cache, not evict one")
        #expect(cache.identity(for: 513) == nil)
    }

    @Test("re-storing a known pid does not grow the cache toward the bound")
    func cacheReplacesInPlace() {
        let cache = AttributionCache()
        for _ in 1 ... 600 {
            cache.store(ClientIdentity(pid: 5, client: "c"), for: 5)
        }
        #expect(cache.count == 1)
    }

    @Test("a failure to name is not cached, so a later successful lookup still answers")
    func failureIsNotCached() {
        let probe = FakeProcessProbe()
        probe.pids = [30]
        probe.ports = [30: [9000]]
        let resolver = Self.resolver(probe)

        #expect(resolver.identity(peerPort: 9000).isUnknown)
        probe.names = [30: "claude"]
        #expect(resolver.identity(peerPort: 9000).client == "claude")
    }
}
