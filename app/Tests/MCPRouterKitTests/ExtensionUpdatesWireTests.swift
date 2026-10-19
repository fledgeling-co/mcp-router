import Foundation
import Testing
@testable import MCPRouterKit

/// The wire the update check and the cache promotion speak, decoded from the same JSON the router's route
/// answers
/// (test/plugin-cache.test.ts and test/skills-route.test.ts assert that JSON on the router side).
@Suite("The update check and cache promotion wire")
struct ExtensionUpdatesWireTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("an offer carries its changelog, a current entry carries none, and an unreadable kind is named")
    func updatesDecode() throws {
        let response = try decode(ExtensionUpdatesResponse.self, #"""
        {
          "checkedAtMs": 1, "staleAfterMs": 86400000, "summary": {"total": 2},
          "catalogues": [],
          "entries": [
            {"kind": "plugins", "name": "demo@market", "catalogue": "market", "state": "update-available",
             "installed": "1.0.0", "available": "2.0.0", "hasUpdate": true, "compared": true,
             "reason": "2.0.0 is offered and 1.0.0 is installed",
             "changelog": {"text": "## 2.0.0\n", "note": "CHANGELOG.md from the cached 2.0.0 copy"}},
            {"kind": "plugins", "name": "other@market", "catalogue": "market", "state": "current",
             "installed": "1.0.0", "available": "1.0.0", "hasUpdate": false, "compared": true,
             "reason": "1.0.0 is installed", "changelog": null}
          ],
          "unreadable": ["/Users/you/.claude/mcp-router/extensions/skills could not be read"]
        }
        """#)

        #expect(response.offered.map(\.name) == ["demo@market"])
        #expect(response.offered.first?.changelog?.text == "## 2.0.0\n")
        #expect(response.entries.last?.changelog == nil)
        #expect(response.unreadable.count == 1)
    }

    @Test("an older router's update check, with no changelog member at all, still decodes with none")
    func updatesWithoutChangelogMember() throws {
        let response = try decode(ExtensionUpdatesResponse.self, #"""
        {"entries": [{"kind": "plugins", "name": "demo@market", "state": "update-available",
          "installed": "1.0.0", "available": "2.0.0", "hasUpdate": true, "reason": "r"}],
         "unreadable": []}
        """#)

        #expect(response.offered.first?.changelog == nil)
    }

    @Test("an unknown kind in the update check is refused by the closed set, not guessed at")
    func updatesRefuseUnknownKind() {
        #expect(throws: (any Error).self) {
            try decode(ExtensionUpdatesResponse.self, #"""
            {"entries": [{"kind": "widgets", "name": "x", "state": "current",
                          "hasUpdate": false, "reason": "r"}],
             "unreadable": []}
            """#)
        }
    }

    @Test("GET /skills says whether the router serves the cache route; an older router leaves it unknown")
    func skillsFlagDecodes() throws {
        let serving = try decode(
            SkillsResponse.self,
            #"{"skills": [], "clients": [], "promoteFromCache": true}"#
        )
        let predating = try decode(SkillsResponse.self, #"{"skills": [], "clients": []}"#)

        #expect(serving.promoteFromCache == true)
        #expect(predating.promoteFromCache == nil)
    }

    @Test(
        "a cache promotion sends the source and the version, and no files, since the router reads them itself"
    )
    func cachePromoteBodyCarriesNoFiles() throws {
        let body = try JSONEncoder().encode(CachePromoteBody(pluginVersion: "2.3.0"))
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])

        #expect(object == ["source": "cache", "pluginVersion": "2.3.0"])
    }
}
