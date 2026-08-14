import Foundation

/// A pairing code: eight characters the Mac issues and the phone consumes.
///
/// **Crockford Base32**, and the alphabet is the whole point rather than a detail. This code's one
/// job is to be *typed by a human reading it off another screen*, so the two characters that break
/// that job are the ones a naive alphabet keeps: `O` against `0`, and `I`/`l` against `1`. Crockford
/// excludes `I`, `L`, `O` and `U` from the encoding set and decodes `I`/`L` as `1` and `O` as `0`,
/// which means a user who types what they think they see is right anyway. `U` is excluded outright
/// and is not aliased to anything — it is a rejection, not a normalisation.
///
/// The Mac issues; the phone consumes. There is no generator here, and its absence is deliberate:
/// a phone that can mint a code is a phone that can pair itself, which inverts the direction the
/// whole design depends on.
public struct PairingCode: Sendable, Hashable, CustomStringConvertible {
    /// The eight canonical characters, upper-case, no separator.
    public let canonical: String

    /// Crockford's encoding alphabet: the digits and the letters, minus `I`, `L`, `O` and `U`.
    public static let alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    /// How many characters a complete code has.
    public static let length = 8

    /// Parse a code a human typed or a Mac encoded.
    ///
    /// Accepts any case, an optional single `-` between the two groups, and surrounding whitespace.
    /// Returns nil for anything else — including a code of the wrong length, which is the boundary
    /// that actually gets hit, since a partially typed code is the normal state of the field.
    public init?(_ text: String) {
        var out = ""
        out.reserveCapacity(Self.length)

        for character in text {
            if character.isWhitespace || character == "-" { continue }

            guard let scalar = character.uppercased().first else { return nil }
            let normalised: Character = switch scalar {
            // Crockford's decode aliases. A user reading a screen cannot be defeated by a font.
            case "I", "L": "1"
            case "O": "0"
            default: scalar
            }

            // `U` is excluded from the alphabet and is not an alias, so it lands here and fails.
            guard Self.alphabet.contains(normalised) else { return nil }
            out.append(normalised)

            // Fail fast rather than accumulating an arbitrarily long string from a hostile input.
            if out.count > Self.length { return nil }
        }

        guard out.count == Self.length else { return nil }
        canonical = out
    }

    /// Build from characters already known to be canonical. Fails on anything that is not.
    public init?(canonical text: String) {
        guard text.count == Self.length, text.allSatisfy({ Self.alphabet.contains($0) }) else {
            return nil
        }
        canonical = text
    }

    /// `XXXX-XXXX` — how the Mac shows it and how the field renders it back.
    public var formatted: String {
        let middle = canonical.index(canonical.startIndex, offsetBy: 4)
        return "\(canonical[canonical.startIndex ..< middle])-\(canonical[middle...])"
    }

    /// Never the code itself. A code is a credential for the window it is alive, and a description
    /// that printed it would put it in every log line that interpolated the value.
    public var description: String { "PairingCode(<redacted>)" }
}

/// How far through the code the user has typed, for the field that renders it.
///
/// A separate type from `PairingCode` because a partially typed code **is not a code** — modelling
/// it as an optional code plus a string would give two sources of truth for the same characters,
/// and the commit button would then be free to disagree with the field about whether it is complete.
public struct PairingCodeEntry: Sendable, Equatable {
    public private(set) var characters: String

    public init(_ text: String = "") {
        characters = ""
        append(contentsOf: text)
    }

    /// Accept keystrokes, normalising and discarding anything the alphabet does not carry.
    ///
    /// Rejecting silently is right here and nowhere else: the user is typing into a field whose
    /// boxes show exactly what was accepted, so a discarded character is visible immediately. An
    /// error message per keystroke would be noise for a condition the field already reports.
    public mutating func append(contentsOf text: String) {
        for character in text {
            guard characters.count < PairingCode.length else { return }
            if character.isWhitespace || character == "-" { continue }
            guard let upper = character.uppercased().first else { continue }
            let normalised: Character = switch upper {
            case "I", "L": "1"
            case "O": "0"
            default: upper
            }
            guard PairingCode.alphabet.contains(normalised) else { continue }
            characters.append(normalised)
        }
    }

    public mutating func deleteBackward() {
        guard !characters.isEmpty else { return }
        characters.removeLast()
    }

    /// The index the caret sits at, which is also the first empty box.
    public var caret: Int { characters.count }

    /// The complete code, or nil while it is still being typed. **This is what the commit control
    /// reads** — so "enabled" and "there is a code to submit" cannot drift apart.
    public var code: PairingCode? {
        guard characters.count == PairingCode.length else { return nil }
        return PairingCode(canonical: characters)
    }

    public var isComplete: Bool { code != nil }

    /// The character in a box, or nil when that box is still empty.
    public func character(at index: Int) -> Character? {
        guard index >= 0, index < characters.count else { return nil }
        return characters[characters.index(characters.startIndex, offsetBy: index)]
    }
}
