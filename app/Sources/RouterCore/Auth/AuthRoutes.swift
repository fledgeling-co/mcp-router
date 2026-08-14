import Foundation

/// The control-API routes this item owns, as **value-layer functions**.
///
/// Each returns `(status, JSONValue)` over R1 types only. They deliberately do **not** use
/// `ControlResponse`, `ControlRequest` or the `AuthStore` protocol: those are R3's symbols, they are
/// not on this branch's base, and declaring them here would collide at merge. R3's dispatch wires
/// each of these in two lines.
///
/// **`DELETE /servers/:name/auth` is not here.** R3 already ships it; two implementations of one
/// route that can silently disagree is worse than a gap.
///
/// **B83 — the 404 that is not theirs.** Both routes sit behind
/// `/^\/servers\/([^/]+)(\/[a-z]+)?$/` and `upstreams.get(name)`, which answers 404
/// `no server named "<name>"` first. These functions therefore take an **already-resolved**
/// upstream: an unknown name cannot reach them, and that is enforced by the type rather than by a
/// check they could forget.
public enum AuthRoutes {
    /// Where the completion continuation goes.
    ///
    /// B95: `authStart` cannot express B79 through its return value, because the continuation
    /// outlives the response. It takes this instead, and registers on it **before** the 200 is
    /// built — matching `control.ts:399-405`, where the `.then` is attached before `json(res, 200)`.
    public protocol CompletionSink: Sendable {
        /// `clearPending(name)` then re-index, in that order, on success only.
        func onAuthorized(server: JSString) async
        /// Both the flow's rejection *and* the re-index's produce this one warn (B79).
        func onIncomplete(server: JSString, reason: String) async
    }

    /// `POST /servers/:name/auth`.
    public static func authStart(
        server: JSString,
        isStdio: Bool,
        sink: any CompletionSink,
        begin: @Sendable () async throws -> LiveFlow,
        awaitCompletion: @escaping @Sendable () async throws -> Void
    ) async -> (status: Int, body: JSONValue) {
        // The stdio refusal runs FIRST, before any flow is begun — so a stdio request binds no
        // port. The reason travels with the refusal; this is the Disabled state of the surface.
        if isStdio {
            return (400, .object([
                JSONMember(
                    key: "error",
                    value: .string("stdio servers do not authorize; their credentials are env vars")
                )
            ]))
        }
        do {
            let flow = try await begin()
            // Registered BEFORE the 200 is constructed. A port that assumes the response has
            // already been sent sequences this wrongly wherever the flow can complete first.
            Task {
                do {
                    try await awaitCompletion()
                    await sink.onAuthorized(server: server)
                } catch {
                    let reason = (error as? AuthFailure)?.message ?? error.localizedDescription
                    await sink.onIncomplete(server: server, reason: reason)
                }
            }
            return (200, .object([
                JSONMember(key: "server", value: .string(server)),
                JSONMember(key: "authorizationUrl", value: .string(JSString(flow.url)))
            ]))
        } catch {
            let reason = (error as? AuthFailure)?.message ?? error.localizedDescription
            return (502, .object([JSONMember(key: "error", value: .string(JSString(reason)))]))
        }
    }

    /// `POST /servers/:name/approve`.
    ///
    /// Reads the manifest **fresh from disk** — `/changes`, two blocks above it in the reference,
    /// uses the cached one, and a port that shares the cache here diverges whenever the cache is
    /// stale (B88). A corrupt manifest degrades to empty, so this answers 409 rather than throwing.
    public static func approve(
        server: JSString,
        manifestPath: String,
        fileSystem: any FileSystem = RealFileSystem(),
        nowMilliseconds: Double,
        log: RouterLog? = nil
    ) async -> (status: Int, body: JSONValue) {
        var manifest = ManifestIO.load(path: manifestPath, fileSystem: fileSystem).manifest

        guard
            let entry = manifest.serverEntries.first(where: { $0.name == server })?.entry,
            let pending = entry.pending,
            pending.isTruthy
        else {
            return (409, .object([
                JSONMember(
                    key: "error",
                    value: .string(JSString("no pending change for \"\(server.string)\""))
                )
            ]))
        }

        // `entry.pending.tools.length`, counted BEFORE the write.
        let approved = pending.member("tools")?.asArray?.count ?? 0

        // `{ ...entry, tools, digest, builtAt, pending: undefined }` — spread order, so a key the
        // entry already carries keeps its position and only genuinely new keys append. `pending`
        // is REMOVED, not emitted as null, because `JSON.stringify` drops an undefined member.
        // `CachedServer.set`/`.remove` are R1's and already carry exactly these semantics, so this
        // consumes them rather than restating the rule in a second place where it could drift.
        var updated = entry
        updated.set("tools", pending.member("tools") ?? .array([]))
        if let digest = pending.member("digest") { updated.set("digest", digest) }
        updated.set("builtAt", .string(JSString(JSDate.iso8601(milliseconds: nowMilliseconds))))
        updated.remove("pending")

        // R1's `setEntry` takes a Swift `String` but matches on `JSString` internally, so the
        // comparison stays code-unit based — B80's substance survives the boundary, and the name
        // gate keeps the round-trip lossless.
        manifest.setEntry(server.string, updated)
        try? ManifestIO.save(manifest, toPath: manifestPath, fileSystem: fileSystem)
        await log?.log(.toolSurfaceApproved(server: server.string, toolCount: approved))

        return (200, .object([
            JSONMember(key: "server", value: .string(server)),
            JSONMember(key: "approved", value: .number(Double(approved)))
        ]))
    }
}
