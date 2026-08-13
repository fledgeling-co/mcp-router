import Foundation

/// A JavaScript string: a sequence of UTF-16 code units, compared by those code units.
///
/// Swift's `String` cannot back a JSON value that has to round-trip through JavaScript, for two
/// reasons that are both invisible until they are not:
///
/// 1. **It cannot hold a lone surrogate.** `JSON.parse("\"\\ud800\"")` is a perfectly ordinary
///    JavaScript string, and `JSON.stringify` writes it back as `"\ud800"`. Decoding that into a
///    Swift `String` substitutes `U+FFFD`, so the bytes change.
/// 2. **It compares by canonical equivalence.** `"\u{00E9}"` and `"e\u{0301}"` are *equal* Swift
///    strings and *distinct* JavaScript object keys. Storing keys as `String` silently merges two
///    members the reference keeps apart — which changes the digest those members are hashed into,
///    on an input no ASCII fixture would ever produce.
///
/// So the storage is the code units themselves. Conversion to `String` exists only for handing a
/// value to a caller at the API edge; it is never on the path that produces bytes for a digest.
public struct JSString: Sendable, Hashable {
    public let units: [UInt16]

    public init(units: [UInt16]) {
        self.units = units
    }

    /// Every Swift `String` has a well-formed UTF-16 view, so this direction is lossless.
    public init(_ string: String) {
        units = Array(string.utf16)
    }

    public var isEmpty: Bool { units.isEmpty }
    public var count: Int { units.count }

    /// Lossy exactly where JavaScript holds an unpaired surrogate, which Swift cannot represent.
    /// Never call this on a value that is about to be serialised.
    public var string: String {
        String(decoding: units, as: UTF16.self)
    }
}

extension JSString: Comparable {
    /// JavaScript's `<` on strings compares UTF-16 code units, not Unicode scalars. The two orders
    /// disagree wherever a supplementary character meets a private-use one: `U+1F600` leads with
    /// code unit `0xD83D`, which is *below* `0xE000`, so the emoji sorts first — whereas by scalar
    /// value `0x1F600` is above `0xE000` and it sorts last.
    ///
    /// This is the comparator the reference's `(a < b ? -1 : a > b ? 1 : 0)` sorts with, so it is
    /// the one the config hash depends on.
    public static func < (lhs: JSString, rhs: JSString) -> Bool {
        let shared = min(lhs.units.count, rhs.units.count)
        var i = 0
        while i < shared {
            if lhs.units[i] != rhs.units[i] { return lhs.units[i] < rhs.units[i] }
            i += 1
        }
        return lhs.units.count < rhs.units.count
    }
}

extension JSString: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension JSString: CustomStringConvertible {
    public var description: String { string }
}

public extension JSString {
    /// Concatenation over code units.
    ///
    /// Not the same as joining the `String` forms and converting back: a lone surrogate cannot
    /// survive `String`, so building a namespaced tool name that way would replace it with U+FFFD
    /// and change the bytes served to a client. JavaScript's `+` on strings is code-unit
    /// concatenation, and so is this.
    static func + (lhs: JSString, rhs: JSString) -> JSString {
        JSString(units: lhs.units + rhs.units)
    }

    /// Whether this key is an *array index* in the sense that decides JavaScript's property
    /// enumeration order: `String(UInt32(key)) == key`, excluding `"4294967295"`.
    ///
    /// The round-trip requirement is what rejects the near-misses — `"01"` maps to `1` and back to
    /// `"1"`, `"-0"` maps to `0` and back to `"0"`, and `"4294967296"` wraps to `0`. Only
    /// `"4294967295"` needs stating separately: it survives the round trip and is still not an
    /// index, because it is reserved as the maximum array length.
    var arrayIndex: UInt32? {
        guard !units.isEmpty, units.count <= 10 else { return nil }
        // Leading zeros never round-trip, and "0" is the only key that may start with one.
        if units[0] == 0x30, units.count > 1 { return nil }
        var value: UInt64 = 0
        for unit in units {
            guard unit >= 0x30, unit <= 0x39 else { return nil }
            value = value * 10 + UInt64(unit - 0x30)
            if value > UInt64(UInt32.max) { return nil }
        }
        guard value < UInt64(UInt32.max) else { return nil }
        return UInt32(value)
    }
}
