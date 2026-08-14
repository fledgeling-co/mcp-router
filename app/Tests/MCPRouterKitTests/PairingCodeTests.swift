import Foundation
import Testing
@testable import MCPRouterKit

/// The code a human has to read off one screen and type into another.
///
/// Boundary values throughout rather than middle ones: the bugs that ship here are one character
/// short, one character long, and the glyph pairs a font makes ambiguous.
@Suite("Pairing code")
struct PairingCodeTests {
    @Test("eight canonical characters parse")
    func canonicalParses() {
        #expect(PairingCode("K7QN4FMB")?.canonical == "K7QN4FMB")
    }

    @Test("the dash the Mac shows is accepted, and so is whitespace around it")
    func separatorsTolerated() {
        #expect(PairingCode("K7QN-4FMB")?.canonical == "K7QN4FMB")
        #expect(PairingCode("  K7QN-4FMB  ")?.canonical == "K7QN4FMB")
        // A dash in the wrong place is still just a separator — the characters are what matter.
        #expect(PairingCode("K7Q-N4FMB")?.canonical == "K7QN4FMB")
    }

    @Test("case does not matter, because the user is copying what they see")
    func caseInsensitive() {
        #expect(PairingCode("k7qn4fmb")?.canonical == "K7QN4FMB")
    }

    /// The whole reason for choosing this alphabet.
    @Test("Crockford aliases: I and L read as 1, O reads as 0")
    func crockfordAliases() {
        #expect(PairingCode("I7QN4FMB")?.canonical == "17QN4FMB")
        #expect(PairingCode("L7QN4FMB")?.canonical == "17QN4FMB")
        #expect(PairingCode("O7QN4FMB")?.canonical == "07QN4FMB")
        #expect(PairingCode("i7qn4fmb")?.canonical == "17QN4FMB")
    }

    /// `U` is excluded from the encoding set and is deliberately **not** aliased to anything.
    @Test("U is rejected rather than normalised")
    func rejectsU() {
        #expect(PairingCode("U7QN4FMB") == nil)
    }

    @Test("length is exact — seven and nine both fail")
    func lengthIsExact() {
        #expect(PairingCode("K7QN4FM") == nil)
        #expect(PairingCode("K7QN4FMBX") == nil)
        #expect(PairingCode("") == nil)
    }

    @Test("anything outside the alphabet fails")
    func rejectsForeignCharacters() {
        #expect(PairingCode("K7QN4FM!") == nil)
        #expect(PairingCode("K7QN 4FM£") == nil)
    }

    @Test("the formatted form is what the Mac shows")
    func formatting() {
        #expect(PairingCode("K7QN4FMB")?.formatted == "K7QN-4FMB")
    }

    /// A code is a credential for as long as it lives, so its description must not carry it.
    @Test("the description never contains the code")
    func descriptionIsRedacted() {
        let code = PairingCode("K7QN4FMB")
        #expect(code?.description.contains("K7QN") == false)
        #expect(code?.description == "PairingCode(<redacted>)")
    }
}

/// The field's own model — partially typed is not a code, and the commit reads the same value the
/// boxes render.
@Suite("Code entry")
struct PairingCodeEntryTests {
    @Test("a partially typed code is not complete and yields no code")
    func partialIsNotComplete() {
        var entry = PairingCodeEntry("K7QN4")
        #expect(entry.caret == 5)
        #expect(entry.isComplete == false)
        #expect(entry.code == nil)

        entry.append(contentsOf: "FMB")
        #expect(entry.isComplete)
        #expect(entry.code?.canonical == "K7QN4FMB")
    }

    /// The boundary the commit button lives on.
    @Test("completeness flips only on the eighth character")
    func completesOnTheEighth() {
        var entry = PairingCodeEntry()
        for (index, character) in "K7QN4FMB".enumerated() {
            entry.append(contentsOf: String(character))
            #expect(entry.isComplete == (index == 7), "flipped at \(index + 1) characters")
        }
    }

    @Test("a ninth character is refused rather than overflowing the field")
    func doesNotOverflow() {
        var entry = PairingCodeEntry("K7QN4FMB")
        entry.append(contentsOf: "X")
        #expect(entry.characters == "K7QN4FMB")
    }

    @Test("keystrokes are normalised as they arrive")
    func normalisesKeystrokes() {
        var entry = PairingCodeEntry()
        entry.append(contentsOf: "io")
        #expect(entry.characters == "10")
    }

    @Test("characters outside the alphabet never reach the boxes")
    func discardsForeign() {
        var entry = PairingCodeEntry()
        entry.append(contentsOf: "K!7@Q")
        #expect(entry.characters == "K7Q")
    }

    @Test("backspace walks the caret back")
    func deletion() {
        var entry = PairingCodeEntry("K7Q")
        entry.deleteBackward()
        #expect(entry.characters == "K7")
        entry.deleteBackward()
        entry.deleteBackward()
        entry.deleteBackward()
        #expect(entry.characters.isEmpty)
    }

    @Test("a box reports its character, or nothing when it is still empty")
    func boxes() {
        let entry = PairingCodeEntry("K7")
        #expect(entry.character(at: 0) == "K")
        #expect(entry.character(at: 2) == nil)
        #expect(entry.character(at: -1) == nil)
    }
}
