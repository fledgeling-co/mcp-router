import Foundation
import Testing
@testable import MCPRouterKit

/// The two checks that keep the register from becoming decorative: every citation resolves to a
/// pre-existing file that really carries the quoted line, and no colour is written outside a token
/// block on either side.
///
/// A suite of its own because `MockTokenParityTests.swift` had grown past the 400 lines SwiftLint
/// allows, and because these four ask a different question from the rest — not "do the two token
/// sets agree" but "is the apparatus that answers that still connected to anything".
@Suite("Mock token literals and citations")
struct MockTokenLiteralTests {
    @Test("every citation resolves to a pre-existing file that really contains the quoted line")
    func citationsResolve() throws {
        let root = try MockTokenParityTests.repoRoot()
        for citation in MockTokenRegister.citations {
            let url = root.appendingPathComponent(citation.file)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                Issue.record("citation '\(citation.key)' points at \(citation.file), which does not exist")
                continue
            }
            #expect(
                text.contains(citation.quote),
                """
                citation '\(citation.key)' quotes a line \(citation.file) does not contain: \
                "\(citation.quote)". A citation that does not resolve is a justification \
                composed during the audit.
                """
            )
        }
    }

    @Test("every citation key a row uses is one of the declared citations")
    func everyUsedCitationIsDeclared() {
        let declared = Set(MockTokenRegister.citations.map(\.key))
        for (name, key) in MockTokenRegister.pendingCitations {
            #expect(declared.contains(key), "'\(name)' cites '\(key)', which is not a declared citation")
        }
    }

    @Test("the mock writes no colour outside its token blocks")
    func theMockHasNoStrayColourLiterals() throws {
        let stray = try MockTokenParser.strayColorLiterals(in: MockTokenParityTests.mockText())
        print("MOCK-FIDELITY-MOCK-LITERALS: stray=\(stray.count)")
        #expect(
            stray.isEmpty,
            """
            the mock writes \(stray.count) colour(s) outside its token blocks, so the :root family \
            is not the whole palette and comparing against it compares a subset while reporting a \
            whole: \(stray.prefix(5).map { "line \($0.line): \($0.text)" })
            """
        )
    }

    /// Assertion 3 is **executed** by `scripts/lint/no-raw-design-values.sh`, in two places: every
    /// `make lint`, and the `literals` layer of `scripts/acceptance/mock-fidelity-gate.sh`.
    ///
    /// It is not re-executed here, and that is a measured decision rather than a shortcut. The
    /// script takes 75 seconds of wall clock — 1.1s of CPU across roughly a thousand `grep`
    /// invocations — so running it inside the unit suite would add that to every `make all` for a
    /// second reading of a check the same run already performed. What this suite owns instead is
    /// the failure mode a duplicate run would not catch anyway: the script being present and
    /// **uninvoked**, which passes for exactly the same reason the script being absent does.
    ///
    /// Rewriting the rule in Swift was the other option and is worse: the script also catches a
    /// component-built colour, a named SwiftUI colour, a shorthand system colour, a numeric font
    /// size, a system text style and a geometry literal, and it carries the two binding files'
    /// exemption by explicit path. Two spellings of one rule drift, and the weaker one is the one
    /// people read.
    @Test("the colour-literal check exists, is executable, and both of its callers still call it")
    func theColourLiteralCheckIsWiredIn() throws {
        let root = try MockTokenParityTests.repoRoot()
        let script = root.appendingPathComponent("scripts/lint/no-raw-design-values.sh")
        #expect(
            FileManager.default.isExecutableFile(atPath: script.path),
            "scripts/lint/no-raw-design-values.sh is missing or not executable"
        )

        let makefile = try String(
            contentsOf: root.appendingPathComponent("Makefile"), encoding: .utf8
        )
        #expect(
            makefile.contains("scripts/lint/no-raw-design-values.sh"),
            """
            the lint script exists but `make lint` no longer runs it. A gate that is present and \
            uninvoked passes for the same reason a gate that is absent does.
            """
        )

        let gate = try String(
            contentsOf: root.appendingPathComponent("scripts/acceptance/mock-fidelity-gate.sh"),
            encoding: .utf8
        )
        #expect(
            gate.contains("no-raw-design-values.sh"),
            """
            the conversion gate no longer runs the colour-literal check, so its `literals` layer \
            reports on nothing.
            """
        )
    }
}
