import Foundation
import Testing
@testable import RouterCore

/// `describe()` serialises the **raw parsed config**, not the typed fields — the family of
/// divergences the completeness critic found.
///
/// `config.ts` keeps `command: s.command`, `args: s.args ?? []` and `projects: s.projects`
/// verbatim, whatever their type, and `describe` emits them unchanged. `ServerParser` necessarily
/// coerces — `command` to a `String`, `args` to `[String]`, `projects` to `[String]` — so reading
/// the typed field reports a value the reference never sends. `cwd` and `warm` were already read
/// from `raw` for exactly this reason; these are the same rule applied to the rest.
///
/// The `projects` case is the sharpest, because the port contradicted itself: PATCH stores a
/// non-array `projects` on disk (`b.projects?.length` is a property read, so `"x"` has length 1),
/// and `describe` then reported `[]` for the value it had just written.
struct RawFieldParityTests {
    static func row(_ body: String) throws -> String {
        let parsed = try JSONParser.parse("{\"mcpServers\":{\"s\":\(body)}}")
        let entries = parsed.member("mcpServers")?.asObjectMembers ?? []
        var upstreams: [(name: JSString, upstream: UpstreamConfig)] = []
        for entry in entries {
            guard case let .upstream(upstream) = ServerParser.parse(
                name: entry.key.string, raw: entry.value
            ) else { continue }
            upstreams.append((entry.key, upstream))
        }
        let deps = try PortIdentityTests.deps(upstreams: upstreams)
        return JSStringify.compact(Describe.row(deps.upstreams[0].upstream, deps))
    }

    @Test("a non-array projects survives to the wire, as `?? []` being nullish requires")
    func projectsNonArray() throws {
        let produced = try Self.row("{\"command\":\"/bin/echo\",\"projects\":\"x\"}")
        #expect(produced.contains("\"projects\":\"x\""))
        #expect(!produced.contains("\"projects\":[]"), "a stored value was denied on the wire")
    }

    @Test("an absent or null projects becomes an empty array")
    func projectsNullish() throws {
        #expect(try Self.row("{\"command\":\"/bin/echo\"}").contains("\"projects\":[]"))
        #expect(try Self.row("{\"command\":\"/bin/echo\",\"projects\":null}").contains("\"projects\":[]"))
    }

    @Test("args keeps its element types rather than being stringified")
    func argsElementTypes() throws {
        let produced = try Self.row("{\"command\":\"/bin/echo\",\"args\":[1,2]}")
        #expect(produced.contains("\"args\":[1,2]"))
        #expect(!produced.contains("\"args\":[\"1\",\"2\"]"))
    }

    @Test("a non-array args survives, since `s.args ?? []` is nullish")
    func argsNonArray() throws {
        #expect(try Self.row("{\"command\":\"/bin/echo\",\"args\":\"abc\"}").contains("\"args\":\"abc\""))
    }

    @Test("a truthy non-string command is reported as given")
    func commandNonString() throws {
        // `if (!s.command)` is a truthiness test, so `true` is accepted and stored as `true`.
        let produced = try Self.row("{\"command\":true}")
        #expect(produced.contains("\"command\":true"))
        #expect(!produced.contains("\"command\":\"true\""))
    }

    @Test("a normal stdio row is unchanged by all of this")
    func ordinaryRowUnchanged() throws {
        let produced = try Self.row("{\"command\":\"/bin/echo\",\"args\":[\"hello\"]}")
        #expect(produced.contains("\"command\":\"/bin/echo\""))
        #expect(produced.contains("\"args\":[\"hello\"]"))
        #expect(produced.contains("\"projects\":[]"))
    }
}
