import Foundation
import Testing
@testable import RouterCore

@Suite("R18 — Manifest digest retention across failed index")
struct ManifestDigestHoldTests {
    @Test("a failed index preserves the previous digest so subsequent change is held")
    func failedIndexPreservesDigestForHold() {
        let toolA = CachedTool(members: [
            JSONMember(key: "name", value: .string("toolA")),
            JSONMember(key: "description", value: .string("original tool A"))
        ])
        let toolB = CachedTool(members: [
            JSONMember(key: "name", value: .string("toolB")),
            JSONMember(key: "description", value: .string("new tool B"))
        ])

        // Step 1: Initial successful index -> approved
        let step1 = ManifestBookkeeping.apply(
            previous: nil,
            observation: .tools([toolA]),
            configHash: "hash1",
            nowMilliseconds: 1000
        )
        guard case let .approved(count) = step1.outcome else {
            #expect(Bool(false), "Step 1 should be approved")
            return
        }
        #expect(count == 1)
        #expect(step1.entry.hasDigest)
        let initialDigest = step1.entry.digest

        // Step 2: Failed re-index -> marked failed, but previous digest is preserved (R18)
        let step2 = ManifestBookkeeping.apply(
            previous: step1.entry,
            observation: .failure(message: "Connection closed"),
            configHash: "hash1",
            nowMilliseconds: 2000
        )
        guard case let .failed(reason) = step2.outcome else {
            #expect(Bool(false), "Step 2 should be failed")
            return
        }
        #expect(reason == "Connection closed")
        #expect(step2.entry.hasError)
        #expect(step2.entry.digest == initialDigest, "R18: previous digest must be preserved across failure")

        // Step 3: Subsequent successful re-index with TAMPERED / CHANGED tools
        // Because the digest was preserved, this is held for approval, NOT auto-approved!
        let step3 = ManifestBookkeeping.apply(
            previous: step2.entry,
            observation: .tools([toolB]),
            configHash: "hash1",
            nowMilliseconds: 3000
        )
        guard case let .heldForApproval(changeCount) = step3.outcome else {
            #expect(Bool(false), "Step 3 must be held for approval, not auto-approved")
            return
        }
        #expect(changeCount > 0)
        #expect(step3.entry.pending != nil, "Changed surface must be held in pending")
    }
}
