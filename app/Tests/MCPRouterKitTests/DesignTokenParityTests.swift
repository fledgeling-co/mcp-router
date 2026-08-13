import Foundation
import Testing
@testable import MCPRouterKit

/// Proves the code and `DESIGN.md` agree about every token, in both directions.
///
/// The two directions matter for different failures. Document → code catches a token that was
/// specified and never implemented. Code → document catches a constant someone added by hand that
/// no design decision backs — the drift that a one-directional test lets through silently.
@Suite("Design token parity with DESIGN.md")
struct DesignTokenParityTests {
    private static func documentText() throws -> String {
        let url = try DesignDocParser.designDocURL()
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Colour

    @Test("every colour token in DESIGN.md has a constant with the same value")
    func colorsDocumentToCode() throws {
        let rows = try DesignDocParser.colorRows(in: Self.documentText())
        #expect(!rows.isEmpty, "parsed no colour rows — the parser or the document changed shape")

        for row in rows {
            guard let token = ColorToken(rawValue: row.name) else {
                Issue.record("DESIGN.md documents \(row.name) but no ColorToken case defines it")
                continue
            }
            #expect(token.hex == row.hex, "\(row.name): code \(token.hex) vs document \(row.hex)")
            #expect(
                abs(token.opacity - row.opacity) < 0.0001,
                "\(row.name): code opacity \(token.opacity) vs document \(row.opacity)"
            )
        }
    }

    @Test("every ColorToken case traces back to a row in DESIGN.md")
    func colorsCodeToDocument() throws {
        let documented = try Set(DesignDocParser.colorRows(in: Self.documentText()).map(\.name))
        for token in ColorToken.allCases {
            #expect(
                documented.contains(token.rawValue),
                "ColorToken.\(token) (\(token.rawValue)) has no row in DESIGN.md §2"
            )
        }
    }

    // MARK: - Type

    @Test("the eight type roles match DESIGN.md exactly")
    func typeDocumentToCode() throws {
        let rows = try DesignDocParser.typeRows(in: Self.documentText())
        #expect(rows.count == 8, "expected 8 type roles in DESIGN.md, parsed \(rows.count)")

        for row in rows {
            guard let token = TypeToken(rawValue: row.role) else {
                Issue.record("DESIGN.md documents role \(row.role) but no TypeToken case defines it")
                continue
            }
            #expect(token.size == row.size, "\(row.role) size: code \(token.size) vs doc \(row.size)")
            #expect(
                token.lineHeight == row.lineHeight,
                "\(row.role) line height: code \(token.lineHeight) vs doc \(row.lineHeight)"
            )
            #expect(
                token.emphasis.rawValue == row.emphasis,
                "\(row.role) emphasis: code \(token.emphasis.rawValue) vs doc \(row.emphasis)"
            )
        }
    }

    @Test("every TypeToken case traces back to a row in DESIGN.md")
    func typeCodeToDocument() throws {
        let documented = try Set(DesignDocParser.typeRows(in: Self.documentText()).map(\.role))
        for token in TypeToken.allCases {
            #expect(documented.contains(token.rawValue), "TypeToken.\(token) has no row in DESIGN.md")
        }
    }

    @Test("body is 13pt — the loudest native-versus-web discriminator")
    func bodyIsThirteen() {
        #expect(TypeToken.body.size == 13)
    }

    // MARK: - Chrome geometry

    /// Rows whose documented value is prose rather than a leading number, listed by name so the
    /// gap is visible in the source instead of being implied by a parser that quietly skips them.
    static let metricRowsNotMachineChecked = ["Sidebar selection", "Control ladder"]

    @Test("chrome metrics match the leading scalar of their documented value")
    func metricsDocumentToCode() throws {
        let rows = try DesignDocParser.metricRows(in: Self.documentText())
        #expect(!rows.isEmpty, "parsed no chrome-geometry rows")

        for row in rows where !Self.metricRowsNotMachineChecked.contains(row.element) {
            guard let token = MetricToken(rawValue: row.element) else { continue }
            guard let scalar = row.leadingScalar else {
                Issue.record("\(row.element) has a MetricToken but its documented value is prose")
                continue
            }
            #expect(
                token.leadingScalar == scalar,
                "\(row.element): code \(token.leadingScalar) vs document \(scalar)"
            )
        }
    }

    @Test("every MetricToken case traces back to a row in DESIGN.md")
    func metricsCodeToDocument() throws {
        let documented = try Set(DesignDocParser.metricRows(in: Self.documentText()).map(\.element))
        for token in MetricToken.allCases {
            #expect(documented.contains(token.rawValue), "MetricToken.\(token) has no row in DESIGN.md")
        }
    }

    @Test("the rows excluded from the metric check really are prose, not values we skipped")
    func exclusionsAreJustified() throws {
        let rows = try DesignDocParser.metricRows(in: Self.documentText())
        for name in Self.metricRowsNotMachineChecked {
            guard let row = rows.first(where: { $0.element == name }) else { continue }
            #expect(
                row.leadingScalar == nil,
                """
                \(name) is on the exclusion list but its value now parses as \
                \(row.leadingScalar ?? -1) — check it instead of excluding it
                """
            )
        }
    }
}

/// The normalisations are load-bearing, so they are tested directly rather than only through the
/// parity checks — a broken normaliser would otherwise show up as a confusing token mismatch.
@Suite("DESIGN.md parsing normalisation")
struct DesignDocParserTests {
    @Test("markdown emphasis is stripped from every cell, values included")
    func stripsEmphasis() {
        // The real Body row bolds its numbers as well as its name.
        #expect(DesignDocParser.normalise("**Body**") == "Body")
        #expect(DesignDocParser.normalise("**13**") == "13")
        #expect(DesignDocParser.normalise("`--ground`") == "--ground")
    }

    @Test("shorthand and full hex are the same colour")
    func expandsShorthandHex() {
        #expect(DesignDocParser.canonicalHex("#FFF") == "#FFFFFF")
        #expect(DesignDocParser.canonicalHex("`#fff`") == "#FFFFFF")
        #expect(DesignDocParser.canonicalHex("#1E1E1E") == "#1E1E1E")
        #expect(DesignDocParser.canonicalHex("not a colour") == nil)
    }

    @Test("a leading scalar is read only when the cell begins with a number")
    func readsLeadingScalar() {
        #expect(DesignDocParser.leadingScalar("33pt") == 33)
        #expect(DesignDocParser.leadingScalar("52pt (8 + 36 XL controls + 8)") == 52)
        #expect(DesignDocParser.leadingScalar("24–28pt for dense lists") == 24)
        #expect(DesignDocParser.leadingScalar("inset rounded fill, radius 8") == nil)
        #expect(DesignDocParser.leadingScalar("Mini 16 · Small 20") == nil)
    }

    @Test("separator and header rows are not mistaken for data")
    func skipsNonDataRows() {
        #expect(DesignDocParser.cells(of: "|---|---|---|") == nil)
        #expect(DesignDocParser.cells(of: "| :--- | ---: |") == nil)
        #expect(DesignDocParser.cells(of: "not a row") == nil)
        #expect(DesignDocParser.cells(of: "| `--ground` | `#1E1E1E` | window |")
            == ["--ground", "#1E1E1E", "window"])
    }

    @Test("a missing DESIGN.md fails loudly rather than skipping the check")
    func missingDocumentThrows() {
        #expect(throws: DesignDocParser.ParseError.self) {
            try DesignDocParser.designDocURL(from: "/nonexistent/deep/path/file.swift")
        }
    }
}
