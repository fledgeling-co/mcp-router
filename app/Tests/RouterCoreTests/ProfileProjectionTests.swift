import Foundation
import Testing
@testable import RouterCore

/// A skill-root reader built from values, so every state in `spec-F8.md` §1.1 is reachable.
struct FixtureSkillRoots: SkillRootReading {
    let roots: [SkillRootInventory]
    let absent: [MCPClient]

    func inventories() -> [SkillRootInventory] {
        roots
    }

    func clientsWithoutRoot() -> [MCPClient] {
        absent
    }
}

/// F8 — what a profile would require, harness by harness.
@Suite("F8 — the profile projection")
struct ProfileProjectionTests {
    private static func scratch() -> String {
        NSTemporaryDirectory() + "mcprouter-f8-proj-" + UUID().uuidString
    }

    /// A store holding exactly the skills named, so the projection's denominator is chosen here
    /// rather than being whatever the developer's own store happens to hold.
    private static func store(_ root: String, skills: [String]) -> DiskExtensionStore {
        let store = DiskExtensionStore(root: root)
        for name in skills {
            _ = store.add(.skills, name: name, files: [ExtensionFile(
                path: "SKILL.md",
                text: "---\nname: \(name)\ndescription: a skill\n---\n"
            )])
        }
        return store
    }

    private static func root(
        _ client: MCPClient, _ path: String, _ entries: [SkillEntry]
    ) -> SkillRootInventory {
        SkillRootInventory(client: client, path: path, exists: true, entries: entries)
    }

    /// A5 — every step carries its reach, and the three reaches are produced by three real inputs.
    ///
    /// The control is inside the same assertion: a skill step must be `durable` **and** a server
    /// step must be `tell-elsewhere` in one projection, so a `reach` that answered one constant
    /// would fail one of the two.
    @Test("J1 a skill step is durable and a server step is tell-elsewhere, in one projection")
    func reachIsPerStepNotPerProjection() throws {
        let scratch = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let projection = ProfileProjector.project(
            profile: ProfileRecord(name: "p", servers: ["github"], skills: ["design-craft"]),
            store: Self.store(scratch, skills: ["design-craft"]),
            roots: [Self.root(.cursor, "/scratch/.cursor/skills", [])],
            upstreamNames: ["github"],
            clientsWithoutRoot: []
        )
        #expect(projection.steps(reaching: "durable").count == 1)
        #expect(projection.steps(reaching: "tell-elsewhere").count == 1)
        let server = try #require(projection.steps(reaching: "tell-elsewhere").first)
        // The mechanism is named and the binary it lives in is named with it, so the body cannot
        // read as a claim that this router can announce the change.
        #expect(server.reach.detail.contains("src/livereload.ts"))
        #expect(server.action == .satisfied)
    }

    /// A5's third reach. `refused` is the router's answer for a harness MCP configuration write,
    /// and it names R7's gate rather than a sentence a reader has to take on trust.
    @Test("J2 the refused reach names the boundary and the gate that holds it")
    func refusedNamesItsGate() {
        guard case let .refused(reason) = ProfileProjector.harnessConfigReach else {
            Issue.record("the harness-config reach is not a refusal"); return
        }
        #expect(reason.contains("spec-R7"))
        #expect(reason.contains("no-harness-config-writes.sh"))
    }

    /// A dangling link is **repaired**, not added — it occupies its name.
    ///
    /// The control is the second root in the same projection, where the name is absent and the
    /// action is `add`. One reader, two answers.
    @Test("J3 a dangling entry produces repair and an absent one produces add")
    func repairBeatsAdd() {
        let scratch = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let projection = ProfileProjector.project(
            profile: ProfileRecord(name: "p", skills: ["design-craft"]),
            store: Self.store(scratch, skills: ["design-craft"]),
            roots: [
                Self.root(.cursor, "/a", [SkillEntry(
                    name: "design-craft", kind: .dangling(target: "/gone/design-craft")
                )]),
                Self.root(.geminiCLI, "/b", []),
                Self.root(.claudeCode, "/c", [SkillEntry(name: "design-craft", kind: .directory)])
            ],
            upstreamNames: [],
            clientsWithoutRoot: []
        )
        #expect(projection.steps.count == 3)
        let byClient = Dictionary(
            uniqueKeysWithValues: projection.steps.compactMap { step in
                step.client.map { ($0, step.action) }
            }
        )
        #expect(byClient[.cursor] == .repair(target: "/gone/design-craft"))
        #expect(byClient[.geminiCLI] == .add)
        #expect(byClient[.claudeCode] == .satisfied)
    }

    /// A skill the router does not hold is reported once, against the store, rather than once per
    /// harness — there is nothing to project onto and repeating it would inflate the step count.
    @Test("J4 a skill the store does not hold is one step, not one per harness")
    func missingFromStoreIsReportedOnce() {
        let scratch = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let projection = ProfileProjector.project(
            profile: ProfileRecord(name: "p", skills: ["never-installed"]),
            store: Self.store(scratch, skills: []),
            roots: [Self.root(.cursor, "/a", []), Self.root(.geminiCLI, "/b", [])],
            upstreamNames: [],
            clientsWithoutRoot: []
        )
        #expect(projection.steps.count == 1)
        #expect(projection.steps.first?.action == .missingFromStore)
        #expect(projection.steps.first?.client == nil)
    }

    /// A root that could not be opened is carried apart from an empty one, and it produces **no**
    /// steps — a projection that guessed `add` for an unreadable root would propose an install
    /// over something that might already be there.
    @Test("J5 an unreadable root produces no step and is named separately")
    func unreadableRootProposesNothing() {
        let scratch = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let projection = ProfileProjector.project(
            profile: ProfileRecord(name: "p", skills: ["design-craft"]),
            store: Self.store(scratch, skills: ["design-craft"]),
            roots: [SkillRootInventory(
                client: .cursor, path: "/a", exists: true, entries: [],
                unreadable: "/a could not be read"
            )],
            upstreamNames: [],
            clientsWithoutRoot: [.grokCLI]
        )
        #expect(projection.steps.isEmpty)
        #expect(projection.unreadableRoots == ["/a"])
        #expect(projection.withoutSkillRoot == [.grokCLI])
        // Both appear in what a person reads, so neither absence is invisible on the surface.
        #expect(projection.render().contains("unreadable"))
        #expect(projection.render().contains("no-skill-root"))
        #expect(projection.render().contains("nothing applies this projection"))
    }
}
