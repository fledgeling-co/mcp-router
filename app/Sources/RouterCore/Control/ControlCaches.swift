import Foundation

/// `GET /caches` and `POST /caches/invalidate` — R31.
///
/// Three caches sit between a change and a call: the router's own `tools/list` manifest, npm's
/// `~/.npm/_npx` package trees, and Claude's plugin cache. Each can serve the old thing after
/// everything upstream has been told, and the manifest is the one that can do it while looking
/// current — its key is the server's command/args/env identity, so a change that leaves those
/// alone leaves the key alone (see ``ContentIdentity``).
///
/// The route answers what would happen before it happens. `POST /caches/invalidate` **plans by
/// default**: a body with no `apply: true` returns the steps, their bytes and the command that
/// re-fetches each one, and changes nothing. That is what *an invalidation that cannot be scoped
/// says so and asks* looks like on a wire — the asking is a reply a caller reads, not a prompt.
///
/// It **diverges from `src/control.ts`**, which answers both paths 404, and is declared in
/// `planning/parity/surface.tsv` as the `div-r31-*` rows the way the `div-r28-*` and
/// `div-m22-*` families are.
extension ControlHandler {
    func routeCaches(
        _ path: String, _ request: ControlAPIRequest, _ deps: ControlDeps
    ) -> ControlAPIResponse? {
        guard path == "/caches" || path == "/caches/invalidate" else { return nil }
        guard let caches = deps.caches else {
            // The shape `/harnesses` and `/extensions` use when the one dependency is absent: name
            // the missing capability rather than answer an empty inventory, which a machine with
            // nothing cached would be indistinguishable from.
            return .error(503, "cache inspection is unavailable: this router has no cache probe")
        }
        let inventory = CacheInventory.read(
            manifest: deps.manifest, upstreams: deps.config.upstreams, probe: caches
        )
        switch (path, request.method) {
        case ("/caches", "GET"):
            return .json(200, Self.inventoryValue(inventory))
        case ("/caches/invalidate", "POST"):
            return invalidate(request, inventory: inventory, probe: caches, deps: deps)
        default:
            return nil
        }
    }

    private func invalidate(
        _ request: ControlAPIRequest,
        inventory: CacheInventory,
        probe: any CacheProbing,
        deps: ControlDeps
    ) -> ControlAPIResponse {
        let body = request.bodyObject
        guard let target = Self.target(body) else {
            return .json(400, .object([
                JSONMember(key: JSString("error"), value: .string(JSString(
                    "name one of server, npxPackage, plugin, or everyNpxEntry: true"
                ))),
                JSONMember(key: JSString("reason"), value: .string(JSString("no-target")))
            ]))
        }
        let acknowledged = body.first { $0.key == JSString("acknowledgeBytes") }?
            .value.asNumber.map { Int($0) }
        let plan = CacheInvalidation.plan(
            target: target, inventory: inventory, upstreams: deps.config.upstreams,
            probe: probe, acknowledgedBytes: acknowledged
        )
        if let refusal = plan.refusal {
            return .json(refusal.status, Self.planValue(plan, applied: nil))
        }
        // Planning is the default and applying is the exception, which is the way round that makes
        // a mistyped body harmless. `apply` is read for truthiness, matching `POST /servers`'s
        // reading of `name`, so `"apply": ""` is not an apply.
        let wantsApply = body.first { $0.key == JSString("apply") }?.value.isTruthy ?? false
        guard wantsApply else { return .json(200, Self.planValue(plan, applied: nil)) }
        let applied = CacheInvalidation.apply(plan, probe: probe)
        // A step that failed is a 207-shaped answer in spirit and a 200 on the wire, with the
        // failures listed: the removals that did land are real and reporting the whole call as an
        // error would invite a caller to repeat work that is already done.
        return .json(200, Self.planValue(plan, applied: applied))
    }

    /// Exactly one target per request. Two named at once is a 400 rather than a guess about which
    /// the caller meant.
    static func target(_ body: [JSONMember]) -> CacheTarget? {
        func text(_ key: String) -> String? {
            guard let value = body.first(where: { $0.key == JSString(key) })?.value,
                  value.isTruthy, let string = value.asString
            else { return nil }
            return string.string
        }
        var found: [CacheTarget] = []
        if let name = text("server") { found.append(.server(name)) }
        if let name = text("npxPackage") { found.append(.npxPackage(name)) }
        if let name = text("plugin") { found.append(.plugin(name)) }
        if body.first(where: { $0.key == JSString("everyNpxEntry") })?.value.isTruthy ?? false {
            found.append(.everyNpxEntry)
        }
        return found.count == 1 ? found[0] : nil
    }
}
