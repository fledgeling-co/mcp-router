import Foundation
import Testing
@testable import RouterCore

@Suite("R16 — Project-scoped server adoption")
struct ProjectScopeAdoptionTests {
    @Test("stagedServers extracts both global and project-scoped servers")
    func stagedServersExtractsBothScopes() throws {
        let jsonText = """
        {
          "mcpServers": {
            "global-server": {
              "command": "node",
              "args": ["global.js"]
            }
          },
          "projects": {
            "/Users/user/Dev/proctor-mcp": {
              "mcpServers": {
                "proctor": {
                  "command": "proctor-shim",
                  "args": ["serve", "--profile", "core"]
                }
              }
            }
          }
        }
        """

        let parsed = try JSONParser.parse(jsonText)
        let staged = WatchStaging.stagedServers(of: parsed)
        let log = WatchLog(path: "/tmp/test.log", fileSystem: MemoryFileSystem())
        let candidates = WatchStaging.candidates(in: staged, log: log)

        #expect(candidates.count == 2)
        let global = try #require(candidates.first { $0.name == "global-server" })
        #expect(global.upstream.projects == nil)

        let proctor = try #require(candidates.first { $0.name == "proctor" })
        #expect(proctor.upstream.projects == ["/Users/user/Dev/proctor-mcp"])
    }

    @Test("ToolUnion filters project-scoped tools by caller working directory")
    func toolUnionFiltersByCWD() {
        let global = UpstreamConfig(
            name: "global",
            transport: .stdio,
            raw: .object([]),
            command: "echo",
            args: [],
            env: [],
            headers: []
        )
        let scoped = UpstreamConfig(
            name: "proctor",
            transport: .stdio,
            raw: .object([]),
            projects: ["/Users/user/Dev/proctor-mcp"],
            command: "proctor",
            args: [],
            env: [],
            headers: []
        )

        #expect(ToolUnion.visibleTo(global, cwd: "/Users/user/Dev/other"))
        #expect(ToolUnion.visibleTo(global, cwd: nil))

        #expect(ToolUnion.visibleTo(scoped, cwd: "/Users/user/Dev/proctor-mcp"))
        #expect(ToolUnion.visibleTo(scoped, cwd: "/Users/user/Dev/proctor-mcp/subfolder"))
        #expect(!ToolUnion.visibleTo(scoped, cwd: "/Users/user/Dev/other-project"))
        #expect(!ToolUnion.visibleTo(scoped, cwd: nil))
    }
}
