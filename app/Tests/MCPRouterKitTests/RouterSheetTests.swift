import Foundation
import Testing
@testable import MCPRouterKit

/// The sheet inventory, checked against the drawing it was taken from.
///
/// The brief's clause is *"the twelve sheets are one enum, so the inventory is a compile-time
/// fact"*, and the fact is only worth having if something compares it to the mock. Triage already
/// found the drift this catches: the brief names twelve and `design/mcp-router-console.html` draws
/// thirteen, because M24 added `official` the same morning the brief was written. Counting by hand
/// is how that survived until triage; this counts on every run.
@Suite("The sheet inventory")
struct RouterSheetTests {
    /// The mock, found by walking up from this file — the same way `ControlCopyTests` finds its
    /// own, and deliberately a hard failure rather than a skip when it is missing. A skipped
    /// inventory check reports the same green as a passing one.
    static func mockText() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = dir.appendingPathComponent("design/mcp-router-console.html")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw InventoryError.mockNotFound
    }

    enum InventoryError: Error { case mockNotFound }

    /// Every `id="sh-…"` in the mock, which is what the mock's own `openSheet(id)` resolves.
    static func sheetIDsInMock() throws -> Set<String> {
        let text = try mockText()
        var found: Set<String> = []
        var search = text[...]
        while let range = search.range(of: "id=\"sh-") {
            let rest = search[range.upperBound...]
            if let close = rest.firstIndex(of: "\"") {
                found.insert(String(rest[rest.startIndex ..< close]))
            }
            search = rest
        }
        return found
    }

    // MARK: - The inventory against the mock

    @Test("the mock draws thirteen sheets, and the inventory names the same thirteen")
    func inventoryMatchesTheMock() throws {
        let drawn = try Self.sheetIDsInMock()
        let named = Set(RouterSheet.Kind.drawnInMock.map(\.rawValue))

        #expect(drawn.count == 13, "expected 13 sheets in the mock, parsed \(drawn.count): \(drawn.sorted())")
        #expect(
            named.subtracting(drawn).isEmpty,
            "RouterSheet.Kind names sheets the mock does not draw: \(named.subtracting(drawn).sorted())"
        )
        #expect(
            drawn.subtracting(named).isEmpty,
            "the mock draws sheets the inventory does not name: \(drawn.subtracting(named).sorted())"
        )
    }

    @Test("the three build-only kinds are marked so they cannot be mistaken for mock sheets")
    func buildOnlyKindsAreDistinguishable() throws {
        let drawn = try Self.sheetIDsInMock()
        let buildOnly = RouterSheet.Kind.allCases.filter { $0.rawValue.hasPrefix("-") }
        #expect(buildOnly.count == 3, "expected 3 build-only kinds, found \(buildOnly.count)")
        for kind in buildOnly {
            #expect(
                !drawn.contains(kind.rawValue),
                "\(kind) is marked build-only but the mock draws an id matching it"
            )
        }
        #expect(RouterSheet.Kind.allCases.count == 16)
    }

    // MARK: - Hosted, owned, or a hole

    @Test("every kind is either presentable or has an owner — never neither")
    func everyKindIsHostedOrOwned() {
        let presentable = Set(RouterSheet.allPresentable.map(\.kind))
        for kind in RouterSheet.Kind.allCases {
            if presentable.contains(kind) {
                #expect(kind.isHosted, "\(kind) is presentable but declares owner \(kind.owner ?? "nil")")
            } else {
                #expect(
                    kind.owner != nil,
                    "\(kind) has no RouterSheet case and no owner — a hole in the inventory"
                )
            }
        }
    }

    /// The census was four, and M30 hosting `readme` is what moved it to three.
    ///
    /// **This assertion changes with the feature rather than to accommodate it**, and it is
    /// deliberately stronger afterwards than before: it asserted that four kinds were unhosted and
    /// that `readme` was M19's, which was true only while nothing served a document. It now asserts
    /// that `readme` is hosted, carries no owner, and has a presentable case — three claims where
    /// there was one — so a later change that unhosted it again fails here rather than quietly
    /// leaving the panel unreachable, which is exactly the state M19 recorded and M30 closed.
    @Test("the three unhosted kinds are M22's, and readme is hosted since M30")
    func unhostedKindsAreTheOnesOnRecord() {
        let unhosted = RouterSheet.Kind.allCases.filter { !$0.isHosted }
        #expect(Set(unhosted) == [.reconcile, .recommendation, .analyzer])
        #expect(RouterSheet.Kind.readme.owner == nil)
        #expect(RouterSheet.Kind.readme.isHosted)
        #expect(RouterSheet.allPresentable.contains { $0.kind == .readme })
        #expect(RouterSheet.Kind.reconcile.owner == "M22")
        #expect(RouterSheet.Kind.recommendation.owner == "M22")
        #expect(RouterSheet.Kind.analyzer.owner == "M22")
    }

    @Test("allPresentable covers every hosted kind, so the hand-written list cannot drift")
    func presentableCoversEveryHostedKind() {
        let presentable = Set(RouterSheet.allPresentable.map(\.kind))
        let hosted = Set(RouterSheet.Kind.allCases.filter(\.isHosted))
        #expect(presentable == hosted, "missing: \(hosted.subtracting(presentable).sorted(by: byName))")
    }

    @Test("no two presentable sheets share an id, so one cannot replace another silently")
    func idsAreDistinct() {
        let ids = RouterSheet.allPresentable.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate sheet ids: \(ids.sorted())")
    }

    @Test("confirm-remove is one kind with two subjects, on two boards")
    func confirmRemoveHasTwoHosts() {
        let removals = RouterSheet.allPresentable.filter { $0.kind == .confirmRemove }
        #expect(removals.count == 2, "expected the Servers and Cleanup removals, found \(removals.count)")
        #expect(Set(removals.map(\.id)).count == 2)
    }

    private func byName(_ lhs: RouterSheet.Kind, _ rhs: RouterSheet.Kind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The gate table — that it is complete, and that nothing has been quietly downgraded.
///
/// That an action actually *opens* the sheet named here is asserted at the board-model seam in
/// `MCPRouterUITests`, not in this file. A gate table asserted only against itself proves the
/// table exists and nothing about whether anything routes through it.
@Suite("The gate table")
struct SheetGateTests {
    @Test("every action declares a blast radius and a gate")
    func everyActionIsDeclared() {
        #expect(SheetGate.Action.allCases.count == 8, "the brief's seven rows plus resetCallHistory")
        for action in SheetGate.Action.allCases {
            // Both are total switches, so this asserts the enum has not grown a case that some
            // future `default:` swallows.
            _ = SheetGate.radius(for: action)
            _ = SheetGate.gate(for: action)
            _ = SheetGate.availability(for: action)
        }
    }

    @Test("nothing above one child process is ungated")
    func frictionScalesWithBlastRadius() {
        for action in SheetGate.Action.allCases {
            guard case .ungated = SheetGate.gate(for: action) else { continue }
            #expect(
                SheetGate.radius(for: action) == .oneChildProcess,
                "\(action) is ungated at blast radius \(SheetGate.radius(for: action))"
            )
        }
    }

    @Test("the one reversible action is ungated, so friction has not been added either")
    func theReversibleActionStaysUngated() {
        guard case let .ungated(reason) = SheetGate.gate(for: .tripBreakerOrWake) else {
            Issue.record("tripBreakerOrWake gained a gate; DESIGN.md §9 is undo over confirm")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test("every built action whose gate is a sheet names a sheet this app can actually present")
    func builtGatesNameHostedSheets() {
        for action in SheetGate.Action.allCases {
            guard case .built = SheetGate.availability(for: action) else { continue }
            guard case let .sheet(kind) = SheetGate.gate(for: action) else { continue }
            #expect(kind.isHosted, "\(action) is built and gated by \(kind), which has no host")
        }
    }

    @Test("the three unbuilt rows are declared as such, and the unclaimed one says why")
    func unbuiltRowsAreVisible() {
        #expect(SheetGate.availability(for: .reconcileHarnessConfig) == .owned("M22"))
        #expect(SheetGate.availability(for: .stopRouter) == .owned("M20"))
        guard case let .unclaimed(reason) = SheetGate.availability(for: .disableServer) else {
            Issue.record("disableServer is recorded as unclaimed; if it was built, update the table")
            return
        }
        #expect(reason.contains("ServerPatch"))
    }

    @Test("Stop Router keeps its lack of an accelerator on purpose")
    func stopRouterHasNoAccelerator() {
        #expect(SheetGate.gate(for: .stopRouter) == .menuItem(accelerator: nil))
    }
}
