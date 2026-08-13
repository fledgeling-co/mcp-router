import Foundation
import Observation
import AppKit

/// The app's single source of truth. One store, shared by the menu bar and the window,
/// because they are two views of one instrument — a second store would let them
/// disagree about whether a server is running, which is the exact fact both exist to show.
@Observable
@MainActor
final class RouterStore {
    enum Connection: Equatable {
        case connecting
        case up(port: Int)
        case down(String)

        var isUp: Bool { if case .up = self { return true }; return false }
    }

    private(set) var connection: Connection = .connecting
    private(set) var servers: [MCPServer] = []
    private(set) var calls: [CallRecord] = []
    private(set) var summaries: [String: ServerSummary] = [:]
    private(set) var since: String?
    private(set) var lastRefreshed: Date?

    /// Set by a view when an action fails, cleared when it's shown. Errors surface where
    /// the action was taken rather than in a global banner; a failed install is about the
    /// install button, not about the app.
    var actionError: String?

    /// Servers whose tool descriptions changed and are being held. This is what the menu
    /// bar icon is allowed to change for.
    var needingAttention: [MCPServer] { servers.filter(\.needsAttention) }

    var runningCount: Int { servers.filter(\.isRunning).count }
    var idleCount: Int { servers.count - runningCount }
    var neverUsed: [MCPServer] { servers.filter(\.neverUsed).sorted { $0.name < $1.name } }
    var totalTools: Int { servers.reduce(0) { $0 + $1.tools } }

    private let client: RouterClient
    private var streamTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    init(client: RouterClient = RouterClient()) {
        self.client = client
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // The server list changes on install, removal, spawn and reap. The stream
                // covers calls; this covers everything else, and 4s is short enough that a
                // spawn shows up while you're still looking at the row that caused it.
                try? await Task.sleep(for: .seconds(4))
            }
        }
        startStream()
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil
        streamTask?.cancel(); streamTask = nil
    }

    /// Point at a different router. The stream has to be torn down and rebuilt, not just
    /// reconfigured: it is an open connection to the old port.
    func repoint(port: Int) async {
        await client.setPort(port)
        connection = .connecting
        calls = []
        startStream()
        await refresh()
    }

    private func startStream() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    for try await rec in await client.stream() {
                        if Task.isCancelled { return }
                        self.ingest(rec)
                    }
                } catch {
                    // A dropped stream is the normal shape of "the router restarted", not
                    // an error worth telling anyone about. Reconnect quietly.
                }
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func ingest(_ rec: CallRecord) {
        calls.insert(rec, at: 0)
        if calls.count > 500 { calls.removeLast(calls.count - 500) }
        // A call means that server is now running and has one more call against it. Showing
        // that immediately rather than at the next poll is what makes the log feel live.
        if let i = servers.firstIndex(where: { $0.name == rec.server }) {
            servers[i].usage.calls += 1
            if !rec.ok { servers[i].usage.errors += 1 }
            servers[i].usage.lastUsed = rec.ts
            servers[i].state = "running"
        }
    }

    func refresh() async {
        do {
            async let s = client.servers()
            async let sum = client.summary()
            let (list, summary) = try await (s, sum)

            connection = .up(port: list.port)
            servers = list.servers.sorted { $0.name < $1.name }
            since = list.since
            summaries = Dictionary(uniqueKeysWithValues: summary.servers.map { ($0.name, $0) })
            lastRefreshed = Date()

            // The call log is only fetched once; after that the stream carries it. Refetching
            // 200 records every 4 seconds would scroll the list under the reader's cursor.
            if calls.isEmpty {
                calls = try await client.usage(limit: 300).records.sorted { $0.date > $1.date }
            }
        } catch {
            connection = .down(error.localizedDescription)
        }
    }

    /// A full reload including the log — used after a reset, where the log genuinely changed.
    func hardRefresh() async {
        calls = []
        await refresh()
    }

    // MARK: - Actions
    //
    // Each returns Bool rather than throwing, and records the message in `actionError`.
    // A view calling one of these is a button, and a button wants to know whether to show
    // a spinner or a message, not to handle an error type.

    private func perform(_ work: () async throws -> Void) async -> Bool {
        do { try await work(); await refresh(); return true }
        catch { actionError = error.localizedDescription; return false }
    }

    func install(name: String, spec: InstallSpec, force: Bool = false) async -> Bool {
        await perform { try await client.install(name: name, spec: spec, force: force) }
    }

    func remove(_ name: String) async -> Bool {
        await perform { try await client.remove(name) }
    }

    func reindex(_ name: String) async -> Bool {
        await perform { try await client.reindex(name) }
    }

    func approve(_ name: String) async -> Bool {
        await perform { try await client.approveChanges(name) }
    }

    func clearAuth(_ name: String) async -> Bool {
        await perform { try await client.clearAuth(name) }
    }

    func setWarm(_ name: String, _ warm: Bool) async -> Bool {
        await perform { try await client.patch(name, warm: warm) }
    }

    func setProjects(_ name: String, _ projects: [String]) async -> Bool {
        await perform { try await client.patch(name, projects: projects) }
    }

    func setPlacard(_ name: String, _ placard: Placard?) async -> Bool {
        await perform { try await client.patch(name, placard: .some(placard)) }
    }

    func resetUsage(server: String? = nil) async -> Bool {
        let ok = await perform { try await client.resetUsage(server: server) }
        if ok { await hardRefresh() }
        return ok
    }

    func changes(_ name: String) async -> ChangesResponse? {
        do { return try await client.changes(name) }
        catch { actionError = error.localizedDescription; return nil }
    }

    func search(_ query: String) async -> RegistryResponse? {
        do { return try await client.search(query) }
        catch { actionError = error.localizedDescription; return nil }
    }

    /// Starts an OAuth flow and hands the URL to the browser.
    ///
    /// The router owns the loopback callback and the token file; the app's whole part is
    /// to ask for the URL and open it. Doing the flow in-app would mean holding the user's
    /// credentials in a process that has no need to see them.
    func authorize(_ name: String) async -> Bool {
        do {
            let start = try await client.beginAuth(name)
            if let url = URL(string: start.authorizationUrl) { NSWorkspace.shared.open(url) }
            // The router polls its own callback; the app just watches for the flag to flip.
            Task { [weak self] in
                for _ in 0..<150 {
                    try? await Task.sleep(for: .seconds(2))
                    await self?.refresh()
                    if await self?.servers.first(where: { $0.name == name })?.auth.authorized == true { return }
                }
            }
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    // MARK: - Derived views of the log

    func calls(forServer server: String?) -> [CallRecord] {
        guard let server else { return calls }
        return calls.filter { $0.server == server }
    }

    /// Every project the log has seen, most recently active first. Built from the log
    /// rather than from a list of directories, because the answer to "who is using this"
    /// is only ever the sessions that actually called something.
    var projects: [(key: String, label: String, calls: Int, last: Date)] {
        var seen: [String: (String, Int, Date)] = [:]
        for c in calls {
            let key = c.cwd ?? "—"
            let label = projectLabel(cwd: c.cwd, project: c.project)
            let prev = seen[key]
            seen[key] = (label, (prev?.1 ?? 0) + 1, max(prev?.2 ?? .distantPast, c.date))
        }
        return seen.map { (key: $0.key, label: $0.value.0, calls: $0.value.1, last: $0.value.2) }
            .sorted { $0.last > $1.last }
    }
}
