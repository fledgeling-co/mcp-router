import Foundation
import Testing
@testable import MCPRouterKit

/// The half of the quarantine diff that was missing, and the four ways it can be got wrong.
///
/// The gap this closes: the router holds a change when the description **or** the input schema
/// differs (`src/manifest.ts:80-93`) and ships both, while `ToolChangeCard` rendered only the
/// description. A schema-only rewrite therefore drew two identical fields and no indication of
/// change — the user asked to accept a diff they could not see.
@Suite("Schema diff")
struct SchemaDiffTests {
    // MARK: - A27a · a schema-only change is a change

    @Test("a schema-only change is reported, and names the added parameter")
    func schemaOnlyChangeIsVisible() {
        let before = #"{"type":"object","properties":{"url":{"type":"string"}}}"#
        let after = #"""
        {"type":"object","properties":{"url":{"type":"string"},"context":{"type":"string"}}}
        """#

        guard case let .changed(parameters, _, _) = SchemaDiff.compare(before: before, after: after) else {
            Issue.record("a schema that gained a parameter was not reported as changed")
            return
        }
        #expect(parameters.map(\.name) == ["context"])
        #expect(parameters[0].kind == .added)
        #expect(parameters[0].sentence == "adds context")
    }

    // MARK: - A27b · an added parameter is the case that matters

    @Test("only an addition wants attention")
    func onlyAdditionsWantAttention() {
        #expect(SchemaDiff.ParameterChange(name: "context", kind: .added).wantsAttention)
        #expect(!SchemaDiff.ParameterChange(name: "context", kind: .removed).wantsAttention)
        #expect(!SchemaDiff.ParameterChange(name: "context", kind: .altered).wantsAttention)
    }

    @Test("removed and altered parameters are named without being marked")
    func removedAndAlteredAreNamed() {
        let before = #"{"properties":{"url":{"type":"string"},"depth":{"type":"number"}}}"#
        let after = #"{"properties":{"url":{"type":"integer"}}}"#

        guard case let .changed(parameters, _, _) = SchemaDiff.compare(before: before, after: after) else {
            Issue.record("expected a change")
            return
        }
        let byName = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.kind) })
        #expect(byName["url"] == .altered)
        #expect(byName["depth"] == .removed)
        #expect(parameters.allSatisfy { !$0.wantsAttention })
    }

    // MARK: - A27c · serialisation order is not a change

    /// The reason both sides are decoded rather than compared as strings. A router that
    /// re-serialises a schema in a different key order has not changed the tool, and reporting it
    /// as a change would train the user to click through the one surface that must not be
    /// clicked through.
    @Test("the same schema in a different key order is not a change")
    func keyOrderIsNotAChange() {
        let before = #"{"type":"object","properties":{"a":{"type":"string"},"b":{"type":"number"}}}"#
        let after = #"{"properties":{"b":{"type":"number"},"a":{"type":"string"}},"type":"object"}"#
        #expect(SchemaDiff.compare(before: before, after: after) == .identical)
    }

    @Test("whitespace alone is not a change")
    func whitespaceIsNotAChange() {
        let before = #"{"type":"object"}"#
        let after = "{\n  \"type\" : \"object\"\n}"
        #expect(SchemaDiff.compare(before: before, after: after) == .identical)
    }

    @Test("a tool that declared no schema and still declares none has not changed")
    func absentOnBothSidesIsIdentical() {
        #expect(SchemaDiff.compare(before: nil, after: nil) == .identical)
        #expect(SchemaDiff.compare(before: "", after: "") == .identical)
        // An empty declaration and an empty object are the same tool.
        #expect(SchemaDiff.compare(before: "", after: "{}") == .identical)
    }

    // MARK: - A27d · unreadable is never "no change"

    /// The failure `SWIFT_PRACTICES.md` §2 names as the worst available, in the place it would do
    /// the most damage: a schema this app cannot decode, reported as unchanged, silently passes an
    /// unreviewable input shape through the surface that exists to review it.
    @Test("an unparseable schema says so and never reports identical")
    func unparseableIsNeverIdentical() {
        let good = #"{"type":"object"}"#
        let broken = "{not json at all"

        guard case let .unreadable(_, _, reason) = SchemaDiff.compare(before: broken, after: good) else {
            Issue.record("an unparseable approved schema was not reported as unreadable")
            return
        }
        #expect(reason.contains("approved"))

        guard case let .unreadable(_, _, pendingReason) = SchemaDiff.compare(before: good, after: broken)
        else {
            Issue.record("an unparseable pending schema was not reported as unreadable")
            return
        }
        #expect(pendingReason.contains("pending"))

        #expect(SchemaDiff.compare(before: broken, after: broken) != .identical)
    }

    @Test("the unreadable case keeps the raw strings so they can still be read")
    func unreadableKeepsTheRawText() {
        let broken = "{not json at all"
        guard case let .unreadable(beforeRaw, afterRaw, _) = SchemaDiff.compare(
            before: broken, after: #"{"type":"object"}"#
        ) else {
            Issue.record("expected unreadable")
            return
        }
        #expect(beforeRaw == broken)
        #expect(afterRaw.contains("object"))
    }

    // MARK: - readability

    @Test("both sides are pretty-printed with sorted keys, so a change lands on its own line")
    func prettyPrintingIsSortedAndIndented() {
        let before = #"{"properties":{"url":{"type":"string"}}}"#
        let after = #"{"properties":{"url":{"type":"string"},"context":{"type":"string"}}}"#

        guard case let .changed(_, beforePretty, afterPretty) = SchemaDiff.compare(
            before: before, after: after
        ) else {
            Issue.record("expected a change")
            return
        }
        #expect(beforePretty.contains("\n"), "the approved schema was not pretty-printed")
        #expect(afterPretty.contains("\n"), "the pending schema was not pretty-printed")
        // Sorted keys: `context` precedes `url` in the output whatever order it arrived in.
        let contextIndex = afterPretty.range(of: "context")
        let urlIndex = afterPretty.range(of: "url")
        #expect(contextIndex != nil && urlIndex != nil)
        if let contextIndex, let urlIndex {
            #expect(contextIndex.lowerBound < urlIndex.lowerBound, "keys were not sorted")
        }
    }

    @Test("a schema with no properties reports no parameters rather than every keyword")
    func schemaKeywordsAreNotParameters() {
        let before = #"{"type":"object"}"#
        let after = #"{"type":"array"}"#
        guard case let .changed(parameters, _, _) = SchemaDiff.compare(before: before, after: after) else {
            Issue.record("expected a change")
            return
        }
        #expect(parameters.isEmpty, "`type` was reported as a parameter")
    }
}
