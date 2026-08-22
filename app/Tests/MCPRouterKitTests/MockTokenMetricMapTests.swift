import Foundation
import Testing
@testable import MCPRouterKit

/// The metric ladder's own coverage guards.
///
/// A suite of its own for the file-length reason `MockTokenLiterals.swift` gives, and because these
/// two ask a different question from the rest of `MockTokenParityTests`: not "do the mock and Swift
/// agree about this value" but "is there anything on either side that nothing is looking at".
@Suite("Mock metric map coverage")
struct MockTokenMetricMapTests {
    /// The same guard on the metric ladder, which did not have one.
    ///
    /// `theNameMapCoversTheWholePalette` has watched `ColorToken` since M23; nothing watched
    /// `MetricToken`, so a new case could be added and compared against nothing. This is that
    /// mirror, and it is stricter than a subset check in the one direction that matters: a case is
    /// either mapped or **named** as one the mock does not declare, and the test below re-reads the
    /// mock to prove the second list is still true.
    @Test("every MetricToken case is either mapped to a mock row or named as one the mock omits")
    func theMetricNameMapCoversTheWholeLadder() {
        let mapped = MockTokenRegister.metricNameMap.values.compactMap { target -> MetricToken? in
            if case let .metric(m) = target { return m }
            return nil
        }
        let mappedSet = Set(mapped)
        let exempt = Set(MockTokenRegister.metricsTheMockDoesNotDeclare)
        for token in MetricToken.allCases {
            #expect(
                mappedSet.contains(token) || exempt.contains(token),
                """
                MetricToken.\(token.rawValue) is in no mock name map entry and is not named as a \
                row the mock omits, so nothing compares it against anything.
                """
            )
        }
        #expect(
            mappedSet.isDisjoint(with: exempt),
            "a metric is both mapped and exempt: \(mappedSet.intersection(exempt).map(\.rawValue))"
        )
    }

    /// The exemption list, held to its reason rather than to its existence.
    ///
    /// An exemption that outlives its cause is the quietest way a check stops checking: the mock
    /// could start publishing `focus-ring` tomorrow and this list would keep it unread. So the mock
    /// is re-parsed and each exempt name is required to be genuinely absent from it.
    @Test("the metrics the exemption list names really are absent from the mock")
    func theUndeclaredMetricsAreReallyUndeclared() throws {
        let text = try MockTokenParityTests.mockText()
        let declared = try Set(MockTokenParser.metricRows(in: text).map(\.name))
        let mapped = Set(MockTokenRegister.metricNameMap.keys)
        for token in MockTokenRegister.metricsTheMockDoesNotDeclare {
            let candidates = declared.subtracting(mapped)
            #expect(
                !candidates.contains(where: { Self.namesTheSameMetric($0, token) }),
                """
                MetricToken.\(token.rawValue) is on the "the mock does not declare it" list, but \
                the mock now declares an unmapped row that names it. Map it instead of exempting it.
                """
            )
        }
    }

    /// Whether an unmapped mock row name and a `MetricToken` are the same element under two
    /// spellings — `sidebar-row-large` against `Sidebar row large`.
    private static func namesTheSameMetric(_ mockName: String, _ token: MetricToken) -> Bool {
        let normalisedMock = mockName.replacingOccurrences(of: "-", with: " ").lowercased()
        let normalisedToken = token.rawValue.lowercased()
        return normalisedMock == normalisedToken
    }
}
