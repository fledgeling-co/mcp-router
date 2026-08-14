import Foundation

public extension JSONMember {
    /// ECMAScript `OrdinaryOwnPropertyKeys` order — **array-index keys first, ascending
    /// numerically, then every other key in insertion order** (spec S4).
    ///
    /// This is not a tidy-up. `JSON.stringify` walks an object in this order, so it is on the wire:
    /// a `projects` map that acquired the directories `"10"` and then `"2"` serialises `2` before
    /// `10`, and a Swift implementation that preserved plain insertion order would emit the two the
    /// other way round. R1 met the same rule for skipped-server ordering and built
    /// ``JSString/arrayIndex`` for it; this is that rule applied to object serialisation.
    ///
    /// The sort is **stable** over the non-index keys, which is what makes "then insertion order"
    /// true rather than approximately true.
    static func ecmaOrdered(_ members: [JSONMember]) -> [JSONMember] {
        var indexed: [(index: UInt32, member: JSONMember)] = []
        var rest: [JSONMember] = []
        for member in members {
            if let index = member.key.arrayIndex {
                indexed.append((index, member))
            } else {
                rest.append(member)
            }
        }
        guard !indexed.isEmpty else { return members }
        indexed.sort { $0.index < $1.index }
        return indexed.map(\.member) + rest
    }
}

public extension JSString {
    /// Splits on one UTF-16 code unit, keeping empty runs — `String.prototype.split` semantics.
    ///
    /// Operates on code units rather than `Character`s because a log line is cut at a byte offset
    /// (N5) and may therefore begin mid-grapheme; splitting such a buffer by `Character` would
    /// merge or drop units the reference keeps.
    func split(on unit: UInt16) -> [JSString] {
        var out: [JSString] = []
        var current: [UInt16] = []
        for value in units {
            if value == unit {
                out.append(JSString(units: current))
                current = []
            } else {
                current.append(value)
            }
        }
        out.append(JSString(units: current))
        return out
    }
}
