import Foundation

/// Where the committed register lives, and how it is written.
///
/// Beside `MockTokenRegister.swift` for the type-length reason `MockTokenLiterals.swift` gives.
/// The seam is the boundary between deciding what a token is and putting that decision on disk:
/// nothing here classifies anything, and nothing there touches the filesystem.
extension MockTokenRegister {
    static func registerURL(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = dir.appendingPathComponent("planning/fidelity/token-register.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let fidelity = dir.appendingPathComponent("planning/fidelity")
            if FileManager.default.fileExists(atPath: fidelity.path) {
                return fidelity.appendingPathComponent("token-register.json")
            }
            dir = dir.deletingLastPathComponent()
        }
        throw MockTokenParser.ParseError.mockNotFound(startingFrom: filePath)
    }

    static func encode(_ register: Register) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(register)
    }
}
