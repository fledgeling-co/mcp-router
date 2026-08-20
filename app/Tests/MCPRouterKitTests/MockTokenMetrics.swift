import Foundation
@testable import MCPRouterKit

/// The mock's `<!-- mac-craft:metrics -->` block: the metric half of its token layer.
///
/// Beside `MockTokenParser.swift` rather than inside it, for the file-length reason
/// `MockTokenLiterals.swift` gives. The seam here is the source: everything below reads the metrics
/// comment, and nothing below touches the stylesheet the colour half is parsed out of.
extension MockTokenParser {
    /// A row of the `mac-craft:metrics` comment: `name value tier`.
    struct MetricRow: Equatable, Sendable {
        let name: String
        let rawValue: String
        let tier: String
        /// The value read as a length in points, when it is one.
        let points: Double?
        /// The value read as a colour, when it is one.
        let color: ColorValue?
    }

    /// A value that is entirely a length in `px`, as points. Nil for anything else.
    ///
    /// `px` in the mock and `pt` in SwiftUI are the same number here: the mock is authored at
    /// 1× against macOS point geometry, which is why `titlebar 33px` and `Titlebar | 33pt` are the
    /// same row. That equivalence is an assumption of the conversion, stated here rather than
    /// buried in a comparison.
    static func points(of raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
            .trimmingCharacters(in: .whitespaces)
        guard s.hasSuffix("px") else { return nil }
        return Double(s.dropLast(2))
    }

    /// The `name value tier` rows of the `mac-craft:metrics` comment, in document order.
    static func metricRows(in text: String) throws -> [MetricRow] {
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: {
            $0.contains("<!-- mac-craft:metrics")
        }) else { throw ParseError.metricsCommentMissing }

        var rows: [MetricRow] = []
        var closed = false
        for line in lines[(start + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("-->") { closed = true; break }
            if t.isEmpty { continue }
            let fields = t.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count == 3 else { throw ParseError.malformedMetricRow(t) }
            rows.append(MetricRow(
                name: fields[0],
                rawValue: fields[1],
                tier: fields[2],
                points: points(of: fields[1]),
                color: color(of: fields[1])
            ))
        }
        guard closed else { throw ParseError.metricsCommentUnterminated }
        return rows
    }
}
