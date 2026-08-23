import Foundation
@testable import MCPRouterKit

/// The increased-contrast overlay, read out of its own table.
///
/// An extension rather than another member of `DesignDocParser`, because that type body is at
/// SwiftLint's 250-line ceiling and this is the seam that splits most naturally: everything in the
/// type reads a table that states values for the two base appearances, and everything here reads
/// the one table that states what a third and fourth context change.
///
/// **A file of its own since M16**, for the ceiling one level up: adding the Signal Path's table
/// reader took `DesignDocParser.swift` to 410 lines against a 400-line limit. The seam was already
/// declared here and already argued for, so moving the block that carries it is the split that
/// costs no reasoning — the alternative was fragmenting the geometry readers, which would have put
/// the chrome ladder's reader and the signature element's in different files for no reason anyone
/// could state.
extension DesignDocParser {
    /// The increased-contrast overlay: the tokens `prefers-contrast: more` re-solves, and only
    /// those.
    ///
    /// Returned as rows in their own right rather than merged into `colorRows`. Merging inside the
    /// parser would make a value's provenance unrecoverable — a base value and an override would
    /// arrive indistinguishable, and the whole point of the overlay is that *which* tokens
    /// override is the assertion. The parity test composes the two and can therefore say which
    /// table it disagreed with.
    static func contrastRows(in text: String) throws -> [ColorRow] {
        var rows: [ColorRow] = []
        var columns: [String: Int]?
        for line in try tableLines(in: text, under: "Increased contrast") {
            guard let c = cells(of: line) else { continue }
            guard c.first?.hasPrefix("--") == true else {
                columns = try headerIndices(c)
                continue
            }
            guard let columns else { throw ParseError.headerMissing("Increased contrast") }

            func cell(_ name: String) throws -> String {
                guard let i = columns[name] else {
                    throw ParseError.columnMissing(name, "Increased contrast")
                }
                guard i < c.count else { throw ParseError.rowTooShort(row: line, want: name) }
                return c[i]
            }

            let dark = try cell("dark")
            let light = try cell("light")
            guard let darkHex = canonicalHex(dark) else {
                throw ParseError.unparsableCell(row: line, cell: dark)
            }
            guard let lightHex = canonicalHex(light) else {
                throw ParseError.unparsableCell(row: line, cell: light)
            }
            rows.append(ColorRow(
                name: c[0],
                role: nil,
                hex: darkHex,
                opacity: opacity(in: dark) ?? 1.0,
                lightHex: lightHex,
                lightOpacity: opacity(in: light) ?? 1.0,
                documentedDarkContrast: nil,
                documentedLightContrast: nil
            ))
        }
        return rows
    }
}
