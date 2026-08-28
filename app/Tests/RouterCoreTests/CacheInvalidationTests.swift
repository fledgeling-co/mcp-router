import Foundation
import Testing
@testable import RouterCore

/// R31 — the plan, its refusals, and the probe that reads a real tree.
///
/// The rule every case here circles is the brief's: **nothing is deleted that the router cannot
/// cause to be re-fetched.** It is held by a type rather than by care — a ``CacheRow`` carries an
/// optional `refetch` and a ``CacheStep`` carries a required one, so a row that names none cannot
/// become a step and the compiler is what says so.
@Suite("R31 — cache invalidation")
struct CacheInvalidationTests {
    private static func scratch() -> String {
        NSTemporaryDirectory() + "mcprouter-r31-" + UUID().uuidString
    }

    private static let entries: [NpxEntry] = [
        CacheFixture.entry("/npx/aaa", "ref-tools-mcp", spec: "^3.0.3", version: "3.0.3", bytes: 161_000_000),
        CacheFixture.entry("/npx/bbb", "ref-tools-mcp", spec: "^3.0.3", version: "3.0.3", bytes: 161_000_000),
        CacheFixture.entry("/npx/ccc", "vitest", spec: "^4.1.11", version: "4.1.11", bytes: 36_000_000),
        // The entry with no `package.json`. Two of the 48 on this machine are in this state.
        NpxEntry(directory: "/npx/ddd", requested: [], bytes: 1_000_000)
    ]

    private static let versions: [PluginVersion] = [
        PluginVersion(
            marketplace: "fledgeling-plugins", plugin: "agent-voice", version: "0.1.1",
            directory: "/plugins/fledgeling-plugins/agent-voice/0.1.1", bytes: 5_000_000
        ),
        PluginVersion(
            marketplace: "fledgeling-plugins", plugin: "agent-voice", version: "0.2.0",
            directory: "/plugins/fledgeling-plugins/agent-voice/0.2.0", bytes: 6_000_000
        ),
        // A `temp_git_<millis>_<suffix>` clone leftover. Five of the twelve directories under this
        // cache on 2026-08-28 are these, and no marketplace restores one.
        PluginVersion(
            marketplace: "temp_git_1787297558771_evcrxb", plugin: "", version: "",
            directory: "/plugins/temp_git_1787297558771_evcrxb", bytes: 2_000_000
        )
    ]

    private static func inventory(
        upstreams: [UpstreamConfig], manifest: Manifest, probe: StubCacheProbe
    ) -> CacheInventory {
        CacheInventory.read(manifest: manifest, upstreams: upstreams, probe: probe)
    }

    // MARK: - Narrow, not wholesale

    @Test("R1 — a server target takes its own npx trees and nothing else, npx first")
    func serverTargetIsNarrowAndOrdered() throws {
        let ref = try CacheFixture.upstream(
            "ref-tools-mcp", command: "npx", args: ["-y", "ref-tools-mcp@3.0.3"]
        )
        let probe = StubCacheProbe(entries: Self.entries, versions: Self.versions)
        let plan = CacheInvalidation.plan(
            target: .server("ref-tools-mcp"),
            inventory: Self.inventory(upstreams: [ref], manifest: .empty, probe: probe),
            upstreams: [ref], probe: probe
        )
        #expect(plan.refusal == nil)
        // Two npx removals and one re-index. `vitest` is 36 MB of cache this plan does not touch,
        // which is the difference between invalidating a package and clearing a store.
        #expect(plan.steps.count == 3)
        #expect(plan.bytes == 322_000_000)
        guard let first = plan.steps.first, let last = plan.steps.last else {
            Issue.record("a server plan over a cached npx package cannot be empty")
            return
        }
        guard case .removeDirectory = first.effect else {
            Issue.record("the npx tree has to go before the re-index, or the re-index reads the old code")
            return
        }
        guard case .reindexServer = last.effect else {
            Issue.record("a server plan must end by re-deriving the manifest row")
            return
        }
        #expect(plan.steps.contains { $0.refetch == "npx -y ref-tools-mcp@^3.0.3" })
        #expect(plan.steps.allSatisfy { !$0.refetch.isEmpty })
    }

    @Test("R2 — a package target names both of its entries and holds the one that names no package")
    func packageTargetHoldsWhatItCannotRefetch() {
        let probe = StubCacheProbe(entries: Self.entries)
        let inventory = Self.inventory(upstreams: [], manifest: .empty, probe: probe)
        let plan = CacheInvalidation.plan(
            target: .npxPackage("ref-tools-mcp"), inventory: inventory, upstreams: [], probe: probe
        )
        #expect(plan.steps.count == 2)
        #expect(plan.held.isEmpty)

        // The unnameable entry is in the inventory, is reported as irreplaceable, and is in no plan.
        let orphan = inventory.npxRows.first { $0.path == "/npx/ddd" }
        #expect(orphan?.refetch == nil)
        #expect(orphan?.problem?.contains("names no package") == true)
        #expect(CacheInvalidation.apply(plan, probe: probe).removed.contains("/npx/ddd") == false)
    }

    @Test("R3 — a plugin target takes one version, or every version of one plugin")
    func pluginTargetScopesToAVersion() {
        let probe = StubCacheProbe(versions: Self.versions)
        let inventory = Self.inventory(upstreams: [], manifest: .empty, probe: probe)

        let one = CacheInvalidation.plan(
            target: .plugin("fledgeling-plugins/agent-voice/0.1.1"),
            inventory: inventory, upstreams: [], probe: probe
        )
        #expect(one.steps.count == 1)
        #expect(one.bytes == 5_000_000)

        let both = CacheInvalidation.plan(
            target: .plugin("fledgeling-plugins/agent-voice"),
            inventory: inventory, upstreams: [], probe: probe
        )
        #expect(both.steps.count == 2)
        #expect(both.steps.allSatisfy { $0.refetch.hasPrefix("claude plugin install agent-voice@") })

        // The clone leftover names no marketplace that restores it, so it is held rather than removed.
        let leftover = CacheInvalidation.plan(
            target: .plugin("temp_git_1787297558771_evcrxb"),
            inventory: inventory, upstreams: [], probe: probe
        )
        #expect(leftover.steps.isEmpty)
        #expect(leftover.held.count == 1)
    }

    // MARK: - Saying so, and asking

    @Test("R4 — clearing the whole npx cache is refused until its cost is named")
    func wholesaleAsksBeforeItSpends() {
        let probe = StubCacheProbe(entries: Self.entries)
        let inventory = Self.inventory(upstreams: [], manifest: .empty, probe: probe)

        let refused = CacheInvalidation.plan(
            target: .everyNpxEntry, inventory: inventory, upstreams: [], probe: probe
        )
        #expect(refused.refusal?.status == 409)
        #expect(refused.refusal?.reason == "cost-not-acknowledged")
        #expect(refused.refusal?.fallbackBytes == 358_000_000)
        #expect(refused.steps.isEmpty)

        // A stale acknowledgement is refused as firmly as an absent one, so the number a caller
        // agrees to is always the number the router just measured.
        let stale = CacheInvalidation.plan(
            target: .everyNpxEntry, inventory: inventory, upstreams: [], probe: probe,
            acknowledgedBytes: 1
        )
        #expect(stale.refusal?.reason == "cost-not-acknowledged")

        let asked = CacheInvalidation.plan(
            target: .everyNpxEntry, inventory: inventory, upstreams: [], probe: probe,
            acknowledgedBytes: 358_000_000
        )
        #expect(asked.refusal == nil)
        #expect(asked.steps.count == 3)
        // Even here the unnameable entry stays. "Clear everything" means everything the router can
        // put back, and that is a smaller set than everything on disk.
        #expect(asked.held.count == 1)
    }

    @Test("R5 — a target that matches nothing is a refusal, not an empty success")
    func nothingMatchedIsRefused() {
        let probe = StubCacheProbe(entries: Self.entries, versions: Self.versions)
        let inventory = Self.inventory(upstreams: [], manifest: .empty, probe: probe)
        for target in [
            CacheTarget.npxPackage("not-fetched"), .plugin("nowhere/none"), .server("ghost")
        ] {
            let plan = CacheInvalidation.plan(
                target: target, inventory: inventory, upstreams: [], probe: probe
            )
            #expect(plan.refusal?.status == 404)
            #expect(plan.isActionable == false)
        }
    }

    @Test("R6 — a manifest row for a server that is gone is reported and cannot be re-derived")
    func orphanedManifestRowIsIrreplaceable() throws {
        let kept = try CacheFixture.upstream("dossier", command: "node", args: ["/repo/dist/index.js"])
        var manifest = Manifest.empty
        var row = CachedServer(members: [])
        row.set("tools", .array([]))
        manifest.setEntry("dossier", row)
        manifest.setEntry("removed-last-month", row)

        let rows = CacheInventory.manifestRows(manifest: manifest, upstreams: [kept])
        #expect(rows.first { $0.subject == "dossier" }?.refetch == "mcp-router index")
        let orphan = rows.first { $0.subject == "removed-last-month" }
        #expect(orphan?.refetch == nil)
        #expect(orphan?.problem?.contains("no longer a configured server") == true)
    }

    // MARK: - The probe, against a real tree

    @Test("R7 — DiskCacheProbe reads npx and plugin layouts, and refuses a path outside its roots")
    func diskProbeReadsAndIsBounded() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        let npx = "\(root)/_npx"
        let plugins = "\(root)/plugins"
        try manager.createDirectory(
            atPath: "\(npx)/hash1/node_modules/vitest", withIntermediateDirectories: true
        )
        try #"{"dependencies":{"vitest":"^4.1.11"}}"#
            .write(toFile: "\(npx)/hash1/package.json", atomically: true, encoding: .utf8)
        try #"{"name":"vitest","version":"4.1.11"}"#
            .write(
                toFile: "\(npx)/hash1/node_modules/vitest/package.json", atomically: true, encoding: .utf8
            )
        try manager.createDirectory(atPath: "\(npx)/hash2", withIntermediateDirectories: true)
        try manager.createDirectory(
            atPath: "\(plugins)/market/plug/1.0.0", withIntermediateDirectories: true
        )
        try manager.createDirectory(atPath: "\(plugins)/temp_git_1", withIntermediateDirectories: true)

        let probe = DiskCacheProbe(roots: CacheRoots(npx: npx, pluginCache: plugins))
        let entries = probe.npxEntries()
        #expect(entries.count == 2)
        #expect(entries.first?.requested.first?.name == "vitest")
        // The version comes from the fetched tree, not from the spec — that is the half that moves.
        #expect(entries.first?.requested.first?.installedVersion == "4.1.11")
        #expect(entries.first?.requested.first?.spec == "^4.1.11")
        #expect(entries.last?.requested.isEmpty == true)

        let versions = probe.pluginVersions()
        #expect(versions.contains { $0.plugin == "plug" && $0.version == "1.0.0" })
        #expect(versions.contains { $0.marketplace == "temp_git_1" && $0.plugin.isEmpty })

        // A delete outside the roots is refused rather than attempted, because finding that out
        // afterwards is too late.
        let outside = "\(root)/elsewhere"
        try manager.createDirectory(atPath: outside, withIntermediateDirectories: true)
        #expect(probe.removeDirectory(outside)?.contains("is not inside") == true)
        #expect(manager.fileExists(atPath: outside))
        #expect(probe.removeDirectory(npx)?.contains("is not inside") == true)
        #expect(probe.removeDirectory("\(npx)/hash2") == nil)
        #expect(manager.fileExists(atPath: "\(npx)/hash2") == false)
    }
}
