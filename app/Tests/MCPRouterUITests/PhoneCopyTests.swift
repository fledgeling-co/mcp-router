import Foundation
import MCPRouterKit
import Testing
@testable import MCPRouterUI

/// The copy manifest, checked in both directions against the design representation.
///
/// `ControlCopyTests` established the pattern for the control client's failure copy: pin the
/// literals, then find them in the mock. That catches a reword in code and a reword in the design
/// that never reached the code. This suite adds the third direction the flat version could not
/// express — **placement**. The manifest is keyed by surface and state, so "the narrowing appears
/// where it must" becomes an assertion rather than an intention.
@Suite("Phone copy manifest")
struct PhoneCopyTests {
    /// The mock, found by walking up from this file — the same way the token tests find `DESIGN.md`,
    /// and deliberately a hard failure rather than a skip when it is missing.
    static func mockText() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = dir.appendingPathComponent("design/mocks/i1-phone-pairing.html")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw CopyError.mockNotFound
    }

    enum CopyError: Error { case mockNotFound }

    /// HTML wraps and indents; the words are what is compared, not the line breaks. The mock also
    /// interpolates the Mac's name as `${MAC}`, which is the same hole the manifest spells `{mac}`.
    ///
    /// Space *before* a punctuation mark is also removed, and that is a consequence of `stripped`
    /// below rather than a cosmetic choice: a closing tag becomes a space, so
    /// `Pair iPhone</b>, then` normalises to `Pair iPhone , then` and stops matching the manifest's
    /// `Pair iPhone, then` — a failure about markup wearing the costume of a failure about copy.
    /// Applied to **both** sides, so it cannot make the mock match something the manifest does not
    /// say; the manifest's own strings have no space before punctuation to remove.
    static func normalised(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var out = ""
        out.reserveCapacity(collapsed.count)
        for character in collapsed {
            if ",.;:!?".contains(character), out.last == " " { out.removeLast() }
            out.append(character)
        }
        return out
    }

    /// Inline markup is presentational, and the comparison is about words.
    ///
    /// The scan instruction emphasises the menu path — `open <b>MCP Router → Settings → Pair
    /// iPhone</b>, then…` — which is a real typographic decision in the design and not something the
    /// manifest should carry. Comparing the raw source against a plain string fails on the `<b>`
    /// rather than on the copy, which is a failure about HTML dressed up as a failure about wording.
    ///
    /// A tag becomes a **space** rather than nothing, so `<p>one</p><p>two</p>` cannot fuse into
    /// `onetwo` and invent a word that is in neither element. It does let a sentence match across
    /// two elements, which is deliberate and already the position this suite takes: the per-sentence
    /// matching above exists precisely because the mock splits paragraphs across markup.
    static func stripped(_ html: String) -> String {
        var out = ""
        out.reserveCapacity(html.count)
        var insideTag = false
        for character in html {
            switch character {
            case "<": insideTag = true; out.append(" ")
            case ">": insideTag = false; out.append(" ")
            default: if !insideTag { out.append(character) }
            }
        }
        return out
    }

    static func mockForm(_ text: String) -> String {
        normalised(text.replacingOccurrences(of: "{mac}", with: "${MAC}"))
    }

    /// Sentences long enough to be worth matching. The mock splits some paragraphs across separate
    /// markup elements, so a whole-body substring match would fail for a reason that is about HTML
    /// rather than about the words.
    static func sentences(of text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 12 }
    }

    // MARK: Direction 1 — every manifest entry exists in the design

    @Test("every headline, body sentence and action label appears in the design representation")
    func manifestIsInTheMock() throws {
        let mock = try Self.normalised(Self.stripped(Self.mockText()))
        var checked = 0

        for (key, entry) in PairingCopy.all {
            if let headline = entry.headline {
                #expect(
                    mock.contains(Self.mockForm(headline)),
                    "\(key).headline is not in the mock: \(headline)"
                )
                checked += 1
            }
            for sentence in Self.sentences(of: entry.body) {
                #expect(
                    mock.contains(Self.mockForm(sentence)),
                    "\(key).body sentence is not in the mock: \(sentence)"
                )
                checked += 1
            }
            for label in [entry.actionLabel, entry.secondaryActionLabel].compactMap(\.self) {
                #expect(mock.contains(label), "\(key) action '\(label)' is not in the mock")
                checked += 1
            }
        }

        // A comparison that compared nothing would pass silently — the same failure the zero-test
        // guard in `make test` exists to stop.
        #expect(checked > 60, "only \(checked) strings were compared; the manifest looks empty")
    }

    @Test("the narrowing sentence is in the design representation")
    func narrowingIsInTheMock() throws {
        let mock = try Self.normalised(Self.stripped(Self.mockText()))
        for sentence in Self.sentences(of: PairingCopy.neverInstalls) {
            #expect(mock.contains(sentence), "the narrowing is not in the mock: \(sentence)")
        }
    }

    // MARK: Direction 2 — placement

    /// A26: the narrowing is rendered where permission is being decided, and on the surface most
    /// likely to be mistaken for an install surface.
    @Test("exactly the required surfaces carry the narrowing")
    func narrowingPlacement() {
        #expect(
            PairingCopy.narrowingKeys == [.settingsNeverPaired, .pairedSuccess, .libraryAwaiting],
            "the narrowing moved surfaces: \(PairingCopy.narrowingKeys)"
        )
    }

    @Test("every key has non-empty copy")
    func noBlankStates() {
        for key in PairingCopy.Key.allCases {
            let entry = PairingCopy.entry(key)
            #expect(!entry.body.isEmpty, "\(key) has an empty body")
            if let headline = entry.headline {
                #expect(!headline.isEmpty, "\(key) has an empty headline")
            }
        }
    }

    @Test("every surface has at least one state, so no surface is unrepresented")
    func everySurfaceIsCovered() {
        let covered = Set(PairingCopy.Key.allCases.map(\.surface))
        for surface in PairingCopy.Surface.allCases {
            #expect(covered.contains(surface), "\(surface) has no copy at all")
        }
    }

    // MARK: The exact wording, pinned

    @Test("the narrowing reads exactly as approved")
    func narrowingIsExact() {
        #expect(PairingCopy.neverInstalls == """
        This app queues items for review on your Mac. It cannot install, update or remove anything — \
        that happens only at your Mac.
        """)
    }

    /// The Error state's copy describes what was observed and names no cause. The earlier draft
    /// blamed a backup restore, which is wrong: a restore to a different device leaves the Keychain
    /// item **absent**, which is the never-paired state.
    @Test("the unreadable-pairing copy names no cause it has not observed")
    func unreadableCopyDoesNotGuess() {
        let entry = PairingCopy.entry(.settingsUnreadable)
        #expect(entry.headline == "Can't read this phone's pairing")
        #expect(!entry.body.lowercased().contains("backup"))
        #expect(!entry.body.lowercased().contains("restor"))
        #expect(entry.actionLabel == "Pair Mac")
    }

    @Test("the partial state says unknown rather than blank, and the row agrees with the banner")
    func partialSaysUnknown() {
        #expect(PairingCopy.entry(.settingsPartial).body.contains("unknown rather than guessed"))
        #expect(PairingSubtitle.lastSeenText(nil, now: Date()) == "unknown")
    }

    @Test("the mac placeholder is resolved, and falls back to a phrase rather than to nothing")
    func placeholderResolution() {
        let resolved = PairingCopy.entry(.outcomeUnreachable).resolved(macName: "Luke's MacBook Pro")
        #expect(resolved.headline == "Can't reach Luke's MacBook Pro")

        let unnamed = PairingCopy.entry(.outcomeUnreachable).resolved(macName: nil)
        #expect(unnamed.headline == "Can't reach your Mac")
        #expect(unnamed.headline?.contains("{mac}") == false)
    }

    /// Every string the user sees is sentence case (`DESIGN.md` §6). Tracked uppercase is the
    /// loudest web tell there is.
    @Test("nothing is shouted")
    func sentenceCase() {
        for (key, entry) in PairingCopy.all {
            let texts = [entry.headline, entry.body, entry.actionLabel, entry.secondaryActionLabel]
                .compactMap(\.self)
            for text in texts {
                let words = text.split(separator: " ").filter { $0.count > 3 }
                for word in words where word.allSatisfy({ $0.isUppercase || $0 == "." }) {
                    // "MCP" is three characters and excluded by the length filter above; anything
                    // else in caps is a shout.
                    Issue.record("\(key) shouts: '\(word)' in '\(text)'")
                }
            }
        }
    }
}
