#if os(macOS)
    import Foundation

    /// A line-oriented reader for `Button` declarations and the modifier chain each one carries.
    ///
    /// **Why source text rather than a rendered view.** A keyboard shortcut cannot be read back off
    /// a SwiftUI view: there is no accessor, and nothing on the macOS host can ask a `Button` which
    /// key activates it. That is why M18 could move `.keyboardShortcut(.cancelAction)` from Cancel
    /// onto a **destructive** Remove button — so Escape performed the removal — with 1757 tests
    /// green and not one of them naming either shortcut. The binding is a fact about the source, so
    /// the source is what gets read, in the shape `TriageSourceGuardTests` and `PhoneSourceGuardTests`
    /// already use for claims no runtime assertion can reach.
    ///
    /// The parser is armed by `SheetShortcutGuardTests.theScannerSeesTheDefectItWasBuiltFor`, which
    /// runs it over an inline fixture carrying the exact M18 shape and requires it to be found. A
    /// scanner that silently stopped matching would take every guard below with it, so it is not
    /// left to be trusted.
    enum SheetShortcutScan {
        enum ScanError: Error { case rootNotFound, nothingScanned }

        /// One `Button` and the modifiers written onto it.
        struct Control {
            let line: Int
            let declaration: String
            let modifiers: [String]

            var isDestructive: Bool { declaration.contains("role: .destructive") }

            /// The shortcuts this control carries, in written order — e.g. `["cancelAction"]`.
            ///
            /// The **first argument** of each `keyboardShortcut(`, with any leading dot dropped, so a
            /// chorded one reads as its key (`keyboardShortcut("r", modifiers: .command)` → `"r"`)
            /// rather than being skipped. Matching only `keyboardShortcut(.` would have made
            /// "no destructive control carries a key" true of a `⌘⌫` binding by not looking at it.
            var shortcuts: [String] {
                modifiers.compactMap { modifier in
                    guard let opening = modifier.range(of: "keyboardShortcut(") else { return nil }
                    let rest = modifier[opening.upperBound...]
                    var depth = 0
                    var argument = ""
                    for character in rest {
                        if character == "(" { depth += 1 }
                        if character == ")" {
                            if depth == 0 { break }
                            depth -= 1
                        }
                        if character == ",", depth == 0 { break }
                        argument.append(character)
                    }
                    let trimmed = argument.trimmingCharacters(in: .whitespaces)
                    return trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
                }
            }
        }

        /// A `struct <Name>: View` block and the controls in it.
        struct SheetView {
            let name: String
            let file: String
            let line: Int
            let controls: [Control]

            var shortcuts: [String] { controls.flatMap(\.shortcuts) }

            /// Sheets are named for what they are, and hosts and frames are not among them.
            ///
            /// Suffix rather than a named list, so a fifteenth sheet is in the population the day it
            /// is written. This is how `MissingSubjectSheet` turned up: M18's verdict enumerated
            /// fourteen sheet views and it is the fifteenth, so the no-Escape-path figure that
            /// verdict reports as 8 of 14 is 9 of 15.
            var isSheet: Bool { name.hasSuffix("Sheet") || name.hasSuffix("Dialog") }
        }

        // MARK: - Reading the tree

        static func repoRoot(from filePath: String = #filePath) throws -> URL {
            var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            for _ in 0 ..< 8 {
                if FileManager.default
                    .fileExists(atPath: directory.appendingPathComponent("DESIGN.md").path)
                {
                    return directory
                }
                directory = directory.deletingLastPathComponent()
            }
            throw ScanError.rootNotFound
        }

        /// Every sheet view under `app/Sources/MCPRouterUI`.
        static func allSheetViews() throws -> [SheetView] {
            try allViews().filter(\.isSheet)
        }

        /// **Every** view, sheet or not, from the whole subtree rather than a named list of files.
        ///
        /// The destructive-control and double-shortcut guards read this rather than the sheets alone:
        /// three destructive buttons in this tree live outside any sheet
        /// (`Boards/ServerInspectorSections.swift:154`, `Phone/PairedMacSettingsView.swift:374`,
        /// `Phone/PairingFlowView.swift:349`), and a guard that only ever looked at sheets would be
        /// silent the first time one of those gained a key.
        static func allViews() throws -> [SheetView] {
            let root = try repoRoot().appendingPathComponent("app/Sources/MCPRouterUI")
            guard let walker = FileManager.default.enumerator(atPath: root.path) else {
                throw ScanError.nothingScanned
            }
            var views: [SheetView] = []
            var filesRead = 0
            for case let path as String in walker where path.hasSuffix(".swift") {
                let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                filesRead += 1
                views += Self.views(in: source, file: path)
            }
            guard filesRead > 0 else { throw ScanError.nothingScanned }
            return views
        }

        // MARK: - The parse

        static func views(in source: String, file: String) -> [SheetView] {
            let lines = source.components(separatedBy: .newlines).map(stripped)
            var views: [SheetView] = []
            var index = 0
            while index < lines.count {
                guard let name = viewName(in: lines[index]) else {
                    index += 1
                    continue
                }
                let end = endOfBlock(lines, from: index)
                views.append(SheetView(
                    name: name,
                    file: file,
                    line: index + 1,
                    controls: controls(in: lines, from: index, to: end)
                ))
                index = max(end, index + 1)
            }
            return views
        }

        /// Comments and string literals out, one line in and one line out so line numbers survive.
        /// The naive version matches its own documentation, which is `PhoneSourceGuardTests`' stated
        /// reason for doing it this way: a guard that fires on a comment gets deleted for noise.
        static func stripped(_ line: String) -> String {
            let withoutComment = line.components(separatedBy: "//").first ?? ""
            var inString = false
            var kept = ""
            for character in withoutComment {
                if character == "\"" {
                    inString.toggle()
                    continue
                }
                if !inString { kept.append(character) }
            }
            return kept
        }

        /// `struct RemoveServerSheet: View {` → `RemoveServerSheet`.
        static func viewName(in line: String) -> String? {
            guard let match = line.range(
                of: #"struct ([A-Za-z0-9]+)(<[^>]*>)?: View \{"#,
                options: .regularExpression
            )
            else { return nil }
            let declaration = line[match]
            guard let nameStart = declaration.range(of: "struct ")?.upperBound,
                  let nameEnd = declaration[nameStart...].firstIndex(where: { $0 == ":" || $0 == "<" })
            else { return nil }
            return String(declaration[nameStart ..< nameEnd])
        }

        private static func delta(_ text: some StringProtocol, _ open: Character, _ close: Character) -> Int {
            text.reduce(0) { total, character in
                total + (character == open ? 1 : character == close ? -1 : 0)
            }
        }

        /// The index one past the line that closes the block opened on `from`.
        static func endOfBlock(_ lines: [String], from: Int) -> Int {
            var depth = 0
            for index in from ..< lines.count {
                depth += delta(lines[index], "{", "}")
                if depth <= 0, index > from { return index + 1 }
            }
            return lines.count
        }

        /// Every `Button(` between two line indices, with the modifier run that follows each.
        ///
        /// A control is consumed until its parentheses *and* its braces both balance, counted from
        /// the `Button(` itself — so a wrapped argument list or a trailing closure does not end the
        /// declaration early and hand its modifiers to nobody. Then the contiguous run of lines
        /// beginning `.` is the chain, and a modifier carrying its own multi-line closure is
        /// consumed whole rather than breaking the run: a `.keyboardShortcut` written after one
        /// would otherwise be invisible, which is a blind guard rather than a passing one.
        static func controls(in lines: [String], from: Int, to end: Int) -> [Control] {
            var found: [Control] = []
            var index = from
            while index < end {
                guard let start = lines[index].range(of: "Button(")?.lowerBound else {
                    index += 1
                    continue
                }
                let head = lines[index][start...]
                var declaration = String(head)
                var parens = delta(head, "(", ")")
                var braces = delta(head, "{", "}")
                var cursor = index + 1
                while parens > 0 || braces > 0, cursor < end {
                    declaration += " " + lines[cursor]
                    parens += delta(lines[cursor], "(", ")")
                    braces += delta(lines[cursor], "{", "}")
                    cursor += 1
                }
                var modifiers: [String] = []
                while cursor < end {
                    let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix(".") else { break }
                    modifiers.append(trimmed)
                    var open = delta(lines[cursor], "{", "}")
                    cursor += 1
                    while open > 0, cursor < end {
                        open += delta(lines[cursor], "{", "}")
                        cursor += 1
                    }
                }
                found.append(Control(line: index + 1, declaration: declaration, modifiers: modifiers))
                index = max(cursor, index + 1)
            }
            return found
        }
    }
#endif
