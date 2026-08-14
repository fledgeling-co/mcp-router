import Foundation
import Testing
@testable import MCPRouterKit

/// The three copy manifests, and the claims their strings are forbidden to make.
///
/// **Asserted over the manifests' own resolved values, never over their source text.** A source
/// scan is the wrong instrument twice over here: `PhoneSourceGuardTests.stripped` removes string
/// literals before scanning — which is what I2's critic caught, and it makes a scan for copy
/// blind by construction — and the doc comments in these files *quote the rejected drafts* in
/// order to record why they were rejected. A scan would fail on the explanation of the fix.
@Suite("Triage, Queue and Library copy")
struct TriageCopyManifestTests {
    /// Every `{token}` written in a string, whether or not any enum declares it. This is what
    /// catches a typo'd `{mack}`, which renders literally to the user and passes every check that
    /// only enumerates the declared cases.
    static func placeholders(in text: String) -> Set<String> {
        var found: Set<String> = []
        var current: String?
        for character in text {
            if character == "{" { current = ""; continue }
            if character == "}" {
                if let name = current, !name.isEmpty { found.insert(name) }
                current = nil
                continue
            }
            if current != nil { current?.append(character) }
        }
        return found
    }

    static func words(_ entries: [(String, String)], contain needle: String) -> [String] {
        entries.filter { $0.1.lowercased().contains(needle.lowercased()) }.map(\.0)
    }

    // MARK: - Every key renders something

    /// A key with an empty body ships a blank pane, which is the failure a state matrix exists to
    /// prevent. Exhaustiveness comes from the compiler; non-emptiness does not.
    @Test("every Triage key renders a non-empty body")
    func triageKeysRender() {
        for key in TriageCopy.Key.allCases {
            #expect(!TriageCopy.entry(key).body.isEmpty, "\(key) has an empty body")
        }
    }

    @Test("every Queue key renders a non-empty body")
    func queueKeysRender() {
        for key in QueueCopy.Key.allCases {
            #expect(!QueueCopy.entry(key).body.isEmpty, "\(key) has an empty body")
        }
    }

    @Test("every Library key renders a non-empty body")
    func libraryKeysRender() {
        for key in LibraryCopy.Key.allCases {
            #expect(!LibraryCopy.entry(key).body.isEmpty, "\(key) has an empty body")
        }
    }

    /// Copy is rendered verbatim, so stray whitespace is visible to the user — an indented first
    /// word, or a sentence that ends in a space before a full stop the layout adds.
    ///
    /// **This catches a whole class rather than a string.** Swift strips a multiline literal's
    /// indentation relative to its **closing** delimiter, so a body whose content sits four columns
    /// right of its own `"""` keeps four leading spaces on every line — invisible in the source,
    /// where it looks like ordinary indentation, and visible in the app.
    @Test("no copy entry carries leading or trailing whitespace")
    func noStrayWhitespace() {
        var offenders: [String] = []

        func check(_ label: String, _ headline: String?, _ body: String, _ action: String?) {
            for (part, text) in [("headline", headline), ("body", body), ("action", action)] {
                guard let text, !text.isEmpty else { continue }
                if text != text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    offenders.append("\(label).\(part): \(text.debugDescription.prefix(60))")
                }
            }
        }

        for key in TriageCopy.Key.allCases {
            let entry = TriageCopy.entry(key)
            check("TriageCopy.\(key)", entry.headline, entry.body, entry.actionLabel)
        }
        for key in QueueCopy.Key.allCases {
            let entry = QueueCopy.entry(key)
            check("QueueCopy.\(key)", entry.headline, entry.body, entry.actionLabel)
        }
        for key in LibraryCopy.Key.allCases {
            let entry = LibraryCopy.entry(key)
            check("LibraryCopy.\(key)", entry.headline, entry.body, entry.actionLabel)
        }

        #expect(offenders.isEmpty, "copy carries stray whitespace: \(offenders)")
    }

    // MARK: - A25: the enumerated-token mechanism

    /// `DiscoverCopy`'s mechanism rather than `PairingCopy`'s, chosen because free interpolation
    /// renders a typo'd `{mack}` straight to the user and passes every other test.
    @Test("no manifest writes a placeholder its own Token enum does not declare")
    func everyPlaceholderIsDeclared() {
        let triageTokens = Set(TriageCopy.Token.allCases.map(\.rawValue))
        for key in TriageCopy.Key.allCases {
            let entry = TriageCopy.entry(key)
            let text = (entry.headline ?? "") + entry.body + (entry.actionLabel ?? "")
            for name in Self.placeholders(in: text) {
                #expect(triageTokens.contains(name), "TriageCopy \(key) writes undeclared {\(name)}")
            }
        }

        let queueTokens = Set(QueueCopy.Token.allCases.map(\.rawValue))
        for key in QueueCopy.Key.allCases {
            let entry = QueueCopy.entry(key)
            let text = (entry.headline ?? "") + entry.body + (entry.actionLabel ?? "")
            for name in Self.placeholders(in: text) {
                #expect(queueTokens.contains(name), "QueueCopy \(key) writes undeclared {\(name)}")
            }
        }

        let libraryTokens = Set(LibraryCopy.Token.allCases.map(\.rawValue))
        for key in LibraryCopy.Key.allCases {
            let entry = LibraryCopy.entry(key)
            let text = (entry.headline ?? "") + entry.body + (entry.actionLabel ?? "")
            for name in Self.placeholders(in: text) {
                #expect(libraryTokens.contains(name), "LibraryCopy \(key) writes undeclared {\(name)}")
            }
        }
    }

    /// A token with no supplied value is left as its placeholder rather than silently emptied: a
    /// visible `{mac}` is a bug report, and a sentence that quietly loses its subject is not.
    /// **Exercised with a PARTIAL dictionary, which is what the surfaces actually construct.**
    /// `resolved([:])` returns the entry unchanged — `Entry.resolved` iterates the dictionary, so an
    /// empty one never enters the loop — making any assertion over it a tautology on the identity
    /// function. The real risk is substituting one token on an entry that carries two.
    @Test("substituting one token leaves the others visible rather than emptying them")
    func unsuppliedTokenStaysVisible() {
        var exercised = 0
        for key in TriageCopy.Key.allCases {
            let entry = TriageCopy.entry(key)
            guard entry.body.contains(TriageCopy.Token.mac.placeholder) else { continue }
            exercised += 1

            // Supply everything EXCEPT `{mac}`, so a substitution pass that emptied unsupplied
            // tokens would be visible here.
            let others = Dictionary(
                uniqueKeysWithValues: TriageCopy.Token.allCases
                    .filter { $0 != .mac }
                    .map { ($0, "x") }
            )
            let resolved = entry.resolved(others)
            #expect(
                resolved.body.contains(TriageCopy.Token.mac.placeholder),
                "\(key) lost its {mac} when other tokens were substituted"
            )
        }
        #expect(exercised > 0, "no entry carries {mac} in its body, so this proved nothing")
    }

    @Test("supplying a token substitutes it everywhere it appears")
    func substitutionWorks() {
        let offline = TriageCopy.entry(.state(.offline)).resolved([.mac: "Luke's MacBook"])
        let text = (offline.headline ?? "") + offline.body
        #expect(text.contains("Luke's MacBook"))
        #expect(!text.contains("{mac}"), "a {mac} survived substitution")
    }

    // MARK: - A8: no recency, novelty or index-wide claim on Triage

    /// There is no feed, no cursor and no seen-state anywhere in this product, so "new", "since",
    /// "latest" and "unread" are all claims the surface cannot observe. The prototype's empty state
    /// said *"you have been through everything new since Tuesday"*.
    @Test("no Triage string claims a recency the surface cannot observe")
    func noRecencyClaims() {
        var offenders: [String] = []
        for key in TriageCopy.Key.allCases {
            let entry = TriageCopy.entry(key)
            let text = ((entry.headline ?? "") + " " + entry.body + " " + (entry.actionLabel ?? ""))
                .lowercased()
            // `" new "` needed a space on both sides, so it missed "What's new", "Nothing new."
            // and a sentence-initial "New". Matched on word boundaries instead.
            let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            if words.contains("new") { offenders.append("\(key): new") }
            for phrase in ["since ", "latest", "unread", "recently"] where text.contains(phrase) {
                offenders.append("\(key): \(phrase)")
            }
        }
        #expect(offenders.isEmpty, "Triage copy claims a recency: \(offenders)")
    }

    // MARK: - A15 / A21: the Queue promises no transfer, because nothing transfers

    /// I2's merged A21 forbids copy that promises an automatic send, and A15 forbids it on this
    /// surface specifically. There is no transport: nothing collects, nothing sends, the user opens
    /// their Mac. The rejected draft read *"Waiting for {mac} to collect them"*.
    @Test("no Queue string promises an automatic transfer")
    func queuePromisesNothing() {
        var offenders: [String] = []
        for key in QueueCopy.Key.allCases {
            let entry = QueueCopy.entry(key)
            let text = ((entry.headline ?? "") + " " + entry.body + " " + (entry.actionLabel ?? ""))
                .lowercased()
            let forbidden = [
                "waiting for", // "Waiting for {mac} to collect them"
                "to collect",
                "until your mac has",
                "automatic",
                "will be sent",
                "syncs",
                "syncing",
                "on its way",
                "last seen"
            ]
            for phrase in forbidden where text.contains(phrase) {
                offenders.append("\(key): \(phrase)")
            }
        }
        #expect(offenders.isEmpty, "Queue copy promises a transfer nothing performs: \(offenders)")
    }

    /// A15: the prototype's `WAITING` / `ADDED` / `NO` badges are removed rather than reworded, so
    /// the vocabulary must not reappear at any scope — including a section header, which is the
    /// door A15's "no section header" closes.
    @Test("the Queue carries no Mac-side status vocabulary")
    func noMacSideStatus() {
        for key in QueueCopy.Key.allCases {
            let entry = QueueCopy.entry(key)
            let text = ((entry.headline ?? "") + " " + entry.body).lowercased()
            for phrase in ["accepted", "rejected", "approved", "delivered", "received by"] {
                #expect(!text.contains(phrase), "\(key) states a Mac-side status: \(phrase)")
            }
        }
    }

    // MARK: - A30 / F6: the narrowing moved manifests, and stayed verbatim

    /// Deleting `.libraryAwaiting` moved the narrowing out of `PairingCopy`. The invariant the
    /// merged `narrowingPlacement` test protects — the narrowing is rendered on the surface most
    /// likely to be mistaken for an install surface — has to survive the move, so the Library's
    /// copy is asserted **identical to the shared constant**, not merely similar to it.
    @Test("the Library's narrowing is PairingCopy.neverInstalls verbatim")
    func narrowingIsVerbatim() {
        #expect(LibraryCopy.entry(.chrome(.narrowing)).body == PairingCopy.neverInstalls)
    }

    // MARK: - A20: the skills absence is stated as a fact

    /// Not an empty list, not a disabled filter, and not a "coming soon" — there is no skills index
    /// and no `/skills` route, and the copy says so.
    @Test("the skills absence names the router and points at the Mac, and promises nothing")
    func skillsAbsenceIsAFact() {
        let entry = LibraryCopy.entry(.state(.skillsAbsent))
        let text = ((entry.headline ?? "") + " " + entry.body).lowercased()

        #expect(text.contains("skills"))
        for phrase in ["coming soon", "not yet", "in a future", "will be added", "support for"] {
            #expect(!text.contains(phrase), "the skills absence promises a future: \(phrase)")
        }
    }

    // MARK: - A21: the never-started case is not rendered as a freshness

    /// `src/control.ts:156,159` compute `state: live?.state ?? 'idle'` and `idleSec: live?.idleSec
    /// ?? 0`, so a server that has never been started is byte-identical to one that went idle this
    /// instant. Rendering that as "idle 0s" states a freshness the router did not observe.
    @Test("a never-used server renders as never started, not as an idle duration")
    func neverStartedIsNotAFreshness() {
        let never = CheckFixtures.server(name: "fresh", calls: 0)
        let used = CheckFixtures.server(name: "used", calls: 12)

        #expect(LibraryRowFact.resolve(for: never) == .neverStarted)
        #expect(LibraryRowFact.resolve(for: used) != .neverStarted)

        let facts = TriagePresentation.libraryFacts(for: never)
        #expect(
            facts.contains { $0.lowercased().contains("never started") },
            "a never-used server did not say so: \(facts)"
        )
        #expect(
            !facts.contains { $0.lowercased().contains("idle") },
            "a never-used server rendered an idle duration it never had: \(facts)"
        )
    }

    // MARK: - A26: every number is a named field or the size of a locally-held set

    /// The permitted set is closed, and the two entries an earlier draft omitted — the size of the
    /// decoded servers array and the size of the filtered result set — are exactly what
    /// `LibraryCopy.subtitle` and the filtered-empty state render.
    @Test("the Library's numeric strings are counts of sets the app holds")
    func libraryNumbersAreLocal() {
        let subtitle = LibraryCopy.entry(.chrome(.subtitle))
        #expect(subtitle.tokens.contains(.count), "the subtitle lost its count token")

        let filtered = LibraryCopy.entry(.state(.emptyFiltered))
        #expect(filtered.tokens.contains(.count))

        let resolved = subtitle.resolved([.count: "4"])
        #expect(resolved.body.contains("4"))
        #expect(!resolved.body.contains("{count}"))
    }
}
