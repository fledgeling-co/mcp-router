import Foundation

/// A unified diff of two texts — what the dry run prints instead of writing.
///
/// It exists because "this command would change your config" is not something a person can check.
/// The file R32 was measured against is 1,441 bytes of the owner's window state, editor paths and
/// account preferences, and the command re-stringifies **the whole document** to add one entry. Most
/// of the time that is byte-identical outside the entry; when it is not — a file indented with four
/// spaces, a trailing newline that moves — the person running the command should see it before it
/// happens, not afterwards in a backup.
///
/// Whole-file rather than entry-scoped for exactly that reason: a diff of the part the writer
/// intends to change cannot show the parts it changes by accident.
public enum UnifiedDiff {
    /// Lines of context either side of a change, matching `diff -U3`.
    public static let context = 3

    /// The diff, or an empty string when the two texts are identical.
    ///
    /// Empty rather than "no changes" so a caller decides what to say: at the two call sites the
    /// right sentences are different, and a renderer that also writes the copy makes them the same.
    public static func between(
        _ before: String, _ after: String, fromLabel: String, toLabel: String
    ) -> String {
        let old = before.components(separatedBy: "\n")
        let new = after.components(separatedBy: "\n")
        let script = edits(from: old, to: new)
        guard script.contains(where: { $0.kind != .same }) else { return "" }

        var out = "--- \(fromLabel)\n+++ \(toLabel)\n"
        for hunk in hunks(of: script) {
            out += header(of: hunk, in: script) + "\n"
            for index in hunk {
                let edit = script[index]
                out += "\(edit.kind.marker)\(edit.text)\n"
            }
        }
        return out
    }

    enum Kind: Sendable, Equatable {
        case same, removed, added

        var marker: String {
            switch self {
            case .same: " "
            case .removed: "-"
            case .added: "+"
            }
        }
    }

    struct Edit: Sendable, Equatable {
        let kind: Kind
        let text: String
        /// 1-based line number in the source text this edit came from, so a hunk header can be
        /// built without re-walking the script. `nil` for a line the other side does not have.
        let oldLine: Int?
        let newLine: Int?
    }

    /// The edit script, from a longest-common-subsequence table.
    ///
    /// Quadratic in the two line counts, which is the right trade here: the documents are config
    /// files of a few dozen lines, and an O(ND) implementation would be more code to be wrong in
    /// than the thing it accelerates.
    static func edits(from old: [String], to new: [String]) -> [Edit] {
        var table = [[Int]](repeating: [Int](repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                table[i][j] = old[i] == new[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var script: [Edit] = []
        var i = 0
        var j = 0
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                script.append(Edit(kind: .same, text: old[i], oldLine: i + 1, newLine: j + 1))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                script.append(Edit(kind: .removed, text: old[i], oldLine: i + 1, newLine: nil))
                i += 1
            } else {
                script.append(Edit(kind: .added, text: new[j], oldLine: nil, newLine: j + 1))
                j += 1
            }
        }
        while i < old.count {
            script.append(Edit(kind: .removed, text: old[i], oldLine: i + 1, newLine: nil))
            i += 1
        }
        while j < new.count {
            script.append(Edit(kind: .added, text: new[j], oldLine: nil, newLine: j + 1))
            j += 1
        }
        return script
    }

    /// Index ranges of the script worth printing: every change, plus ``context`` lines around it,
    /// with overlapping neighbourhoods merged.
    static func hunks(of script: [Edit]) -> [[Int]] {
        let changed = script.indices.filter { script[$0].kind != .same }
        guard !changed.isEmpty else { return [] }

        var groups: [[Int]] = []
        var current: [Int] = []
        for index in changed {
            let low = max(0, index - context)
            let high = min(script.count - 1, index + context)
            let window = Array(low ... high)
            if let last = current.last, low > last + 1 {
                groups.append(current)
                current = window
            } else {
                current = Array(Set(current).union(window)).sorted()
            }
        }
        groups.append(current)
        return groups
    }

    /// `@@ -a,b +c,d @@`, with the counts taken from the hunk rather than assumed.
    ///
    /// A hunk that is pure insertion has no old lines at all, and the unified format says a
    /// zero-length range starts at the line *before* the insertion. Getting that wrong makes a diff
    /// that reads correctly and will not apply.
    static func header(of hunk: [Int], in script: [Edit]) -> String {
        let oldLines = hunk.compactMap { script[$0].oldLine }
        let newLines = hunk.compactMap { script[$0].newLine }
        let oldStart = oldLines.first ?? precedingOldLine(before: hunk[0], in: script)
        let newStart = newLines.first ?? precedingNewLine(before: hunk[0], in: script)
        return "@@ -\(oldStart),\(oldLines.count) +\(newStart),\(newLines.count) @@"
    }

    private static func precedingOldLine(before index: Int, in script: [Edit]) -> Int {
        script[..<index].reversed().compactMap(\.oldLine).first ?? 0
    }

    private static func precedingNewLine(before index: Int, in script: [Edit]) -> Int {
        script[..<index].reversed().compactMap(\.newLine).first ?? 0
    }
}
