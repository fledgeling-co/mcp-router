import Foundation

/// A capability's own documentation, read out of the package the router starts it from.
///
/// The Swift half of `src/document.ts`, and diffed against it by the `document-image-refs`,
/// `document-resolve` and `document-caps` vectors. Two implementations of one route diverge
/// silently unless something forces them to agree, and the halves worth forcing are the pure ones:
/// which references a document names, whether a reference may be read, and which cap a size hits.
///
/// The router is the only process that may read a package. `scripts/lint/no-raw-design-values.sh`
/// forbids the presentation layer reaching past the control API, which is what lets the router be
/// replaced underneath the app — so the files, the bytes and every refusal are decided here, and
/// what crosses the wire is bytes the app cannot mistake for a path.
///
/// `planning/specs/spec-M30.md` owns the reasoning.
public enum DocumentPackage {
    /// The three documents a package may publish, in the panel's tab order.
    public static let files: [(tab: String, file: String)] = [
        (tab: "readMe", file: "README.md"),
        (tab: "changelog", file: "CHANGELOG.md"),
        (tab: "capabilities", file: "CAPABILITIES.md")
    ]

    /// The transport's own caps, which are not `MarkdownLimits`.
    ///
    /// `MarkdownLimits` caps the parse, in the app, after the bytes have already crossed. A read me
    /// is unbounded on disk, so the wire needs a bound of its own — and a refusal that names which
    /// of the three it hit, because "too large" without a cap name tells a reader nothing they can
    /// act on.
    public enum Caps {
        /// One markdown file. Over this the whole request refuses rather than truncating.
        public static let documentBytes = 524_288
        /// One image. Over this that image travels as a refusal and the document still travels.
        public static let imageBytes = 2_097_152
        /// Every image in one response together. Once spent, the rest are refused in order.
        public static let imageBudgetBytes = 8_388_608
    }

    /// What the app will render as an image, by extension.
    ///
    /// A boundary rather than a convenience: an image reference is a request to read a file, and
    /// the document making it is untrusted. `svg` is deliberately outside the set — it is a
    /// document format that can carry script, and nothing in this panel needs one.
    public static func mediaType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case ".png": "image/png"
        case ".jpg", ".jpeg": "image/jpeg"
        case ".gif": "image/gif"
        case ".webp": "image/webp"
        default: nil
        }
    }

    /// Why a reference was not read. Each case is user-facing copy's input in the app, so each one
    /// is a distinct thing that happened rather than a shared "invalid".
    public enum Refusal: Equatable, Sendable {
        case remote(scheme: String)
        case absolutePath
        case escapesPackage
        case notInPackage
        case unsupportedType(extension: String)
        case tooLarge(limit: Int)
        case budgetExhausted

        /// The wire's `reason`, which is the app's mapping key.
        public var reason: String {
            switch self {
            case .remote: "remote"
            case .absolutePath: "absolutePath"
            case .escapesPackage: "escapesPackage"
            case .notInPackage: "notInPackage"
            case .unsupportedType: "unsupportedType"
            case .tooLarge: "tooLarge"
            case .budgetExhausted: "budgetExhausted"
            }
        }
    }

    public enum Resolution: Equatable, Sendable {
        case readable(path: String)
        case refused(Refusal)
    }

    // MARK: - The reference scan

    /// Every `![alt](reference)` in one run of text, in order, as the document spelled it.
    ///
    /// Hand-scanned rather than regexed, and the reason is the app's: a reference may contain
    /// balanced parentheses — generated badge paths and Wikipedia URLs both do — and the obvious
    /// `\(([^)]*)\)` closes on the first one and yields a reference the document never wrote. A
    /// title after the reference is dropped at the first space, because carrying it would make the
    /// reference unresolvable.
    ///
    /// This is the scan `MarkdownParser.inlineImages` performs in the app. It has to be: the router
    /// decides which files to read, so a router that extracts a different set of references sends a
    /// different set of bytes and the app cannot see that it happened.
    public static func imageReferences(inRun text: String) -> [String] {
        let characters = Array(text)
        var references: [String] = []
        var index = 0
        while index < characters.count {
            guard let bang = characters[index...].firstIndex(of: "!") else { break }
            guard bang + 1 < characters.count, characters[bang + 1] == "[" else {
                index = bang + 1
                continue
            }
            guard let close = characters[(bang + 1)...].firstIndex(of: "]") else { break }
            guard close + 1 < characters.count, characters[close + 1] == "(" else {
                index = close + 1
                continue
            }
            guard let closeParen = balancedClose(characters, from: close + 1) else { break }
            let inside = String(characters[(close + 2) ..< closeParen])
            references.append(inside.split(separator: " ", maxSplits: 1).first.map(String.init) ?? inside)
            index = closeParen + 1
        }
        return references
    }

    /// The index of the `)` that closes the `(` at `open`, counting depth.
    private static func balancedClose(_ characters: [Character], from open: Int) -> Int? {
        var depth = 0
        var cursor = open
        while cursor < characters.count {
            if characters[cursor] == "(" { depth += 1 }
            if characters[cursor] == ")" {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor += 1
        }
        return nil
    }

    /// Every image reference a document names, in document order, with duplicates collapsed.
    ///
    /// A **run** is a maximal group of consecutive non-blank lines outside a fenced code block,
    /// trimmed and joined with one space — the same joining the app's parser performs before it
    /// scans, so a reference split across two lines resolves to the same spelling on both sides.
    ///
    /// It is deliberately a coarser split than the parser's: the parser also breaks a run at a
    /// heading, a list marker and a quote, and this does not. The consequence is stated rather than
    /// left to be discovered — the router may extract a reference the app will never ask for, which
    /// costs bytes and draws no wrong figure. It cannot go the other way, and a reference the app
    /// asks for and the router never read is the failure that would matter.
    public static func imageReferences(in source: String) -> [String] {
        var references: [String] = []
        var seen: Set<String> = []
        var run: [String] = []
        var fenced = false

        func flush() {
            guard !run.isEmpty else { return }
            for reference in imageReferences(inRun: run.joined(separator: " ")) where !seen.contains(reference) {
                seen.insert(reference)
                references.append(reference)
            }
            run = []
        }

        for raw in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flush()
                fenced.toggle()
                continue
            }
            if fenced { continue }
            if line.isEmpty {
                flush()
                continue
            }
            run.append(line)
        }
        flush()
        return references
    }

    // MARK: - Resolution

    /// Whether one reference may be read, and from where.
    ///
    /// Scheme first, because a path resolver will happily treat `https://example.com/a.png` as a
    /// relative path and land it inside the package — a remote reference laundered into a local
    /// one. Then absolute paths, which a document does not get to name whether or not they are
    /// inside the package. Then containment, compared on **path segments** after resolving
    /// symlinks, because `/pkg-evil/x.png` has `/pkg` as a string prefix and is not inside it, and
    /// because a downloaded archive is exactly where a symlink pointing out of itself comes from.
    public static func resolve(
        _ reference: String,
        inPackageAt root: String,
        fileSystem: any FileSystem
    ) -> Resolution {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = leadingScheme(of: trimmed) {
            return .refused(.remote(scheme: scheme))
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return .refused(.absolutePath)
        }

        let base = URL(fileURLWithPath: root, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let candidate = base.appendingPathComponent(trimmed)
            .standardizedFileURL.resolvingSymlinksInPath()
        let baseParts = base.pathComponents
        let candidateParts = candidate.pathComponents
        guard candidateParts.count > baseParts.count,
              Array(candidateParts.prefix(baseParts.count)) == baseParts
        else {
            return .refused(.escapesPackage)
        }

        let ext = "." + candidate.pathExtension
        guard mediaType(forExtension: ext) != nil else {
            return .refused(.unsupportedType(extension: candidate.pathExtension.isEmpty ? "" : ext))
        }
        // Present **and a file**. A directory carrying an image extension is refused rather than
        // read: the reference implementation asks `statSync(...).isFile()`, and a port that asked
        // only whether the path existed would go on to read a directory and turn a document's
        // reference into a 500 instead of a placeholder. `contentsOfDirectory` succeeding is what
        // says "directory" through the port this router already has.
        guard fileSystem.fileExists(atPath: candidate.path),
              (try? fileSystem.contentsOfDirectory(atPath: candidate.path)) == nil
        else {
            return .refused(.notInPackage)
        }
        return .readable(path: candidate.path)
    }

    /// The scheme a reference leads with, lowercased, or nil when it names none.
    ///
    /// Read by hand rather than through a URL parser, because the two disagree about a Windows-ish
    /// `c:` and about a reference whose first segment merely contains a colon, and the reference
    /// implementation's regex is the contract here.
    private static func leadingScheme(of reference: String) -> String? {
        guard let colon = reference.firstIndex(of: ":") else { return nil }
        let head = reference[reference.startIndex ..< colon]
        guard let first = head.first, first.isASCII, first.isLetter else { return nil }
        let rest = head.dropFirst()
        let legal = rest.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-") }
        return legal ? head.lowercased() : nil
    }

    // MARK: - The caps

    /// Whether one markdown file is over the transport's per-document cap.
    public static func documentOverCap(_ size: Int) -> Bool {
        size > Caps.documentBytes
    }

    public enum CapDecision: String, Equatable, Sendable {
        case send
        case tooLarge
        case budgetExhausted
    }

    /// What happens to each image, in document order, given only their sizes.
    ///
    /// Pure arithmetic, and separated from the reading for that reason: it is the half a parity
    /// vector can pin exactly, and the order matters — an oversized image is refused on its own
    /// terms and does **not** spend the shared budget, so one 9 MiB figure cannot silently refuse
    /// every figure after it for the wrong reason.
    public static func imageCapDecisions(sizes: [Int]) -> [CapDecision] {
        var spent = 0
        return sizes.map { size in
            if size > Caps.imageBytes { return .tooLarge }
            if spent + size > Caps.imageBudgetBytes { return .budgetExhausted }
            spent += size
            return .send
        }
    }
}
