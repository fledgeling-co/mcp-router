#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The capability document panel: its three tabs, its designed states, and the two claims the
    /// brief makes about how it draws.
    @MainActor
    @Suite("M19 — the capability document panel")
    struct CapabilityDocumentSheetTests {
        private func document() throws -> CapabilityDocument {
            try #require(FixtureCapabilityDocumentSource.build())
        }

        // MARK: - The three tabs

        /// Three tabs over one panel, not one long scroll — `spec-M19.md` §2's third assumption.
        /// The titlebar draws all three whatever the capability published, because a tab that
        /// disappeared would make the panel's shape depend on the capability and a reader could not
        /// tell "no changelog" from "this app does not show changelogs".
        @Test("all three tabs are always offered, and each renders a different document")
        func tabsAreIndependent() throws {
            let document = try document()
            #expect(CapabilityDocument.Tab.allCases.count == 3)
            let counts = CapabilityDocument.Tab.allCases.map { document.blocks(for: $0)?.count ?? 0 }
            #expect(counts.allSatisfy { $0 > 0 })
            #expect(Set(counts).count > 1, "three tabs rendering identical block counts is one document")
        }

        /// A tab the capability published nothing for. Real copy, naming the missing document and
        /// saying the others are still there (`DESIGN.md` §5, §6).
        @Test("an unpublished tab says which document is missing, not \"no content\"")
        func absentTabCopy() {
            for tab in CapabilityDocument.Tab.allCases {
                let sentence = tab.absentSentence
                #expect(sentence.contains("still here"))
                #expect(!sentence.lowercased().contains("no content"))
                #expect(!sentence.lowercased().contains("error"))
            }
            #expect(Set(CapabilityDocument.Tab.allCases.map(\.absentSentence)).count == 3)
        }

        /// A document present for one tab and absent for another is a panel that draws both states
        /// at once, which is the case the dictionary exists for.
        @Test("a capability publishing one document reports exactly that one as published")
        func partialPublication() throws {
            var document = try document()
            document.tabs.removeValue(forKey: .changelog)
            #expect(document.publishedTabs == [.readMe, .capabilities])
            #expect(document.blocks(for: .changelog) == nil)
        }

        // MARK: - The states

        /// `DESIGN.md` §5: a populated-only screen is a third of a design. Three states, and the
        /// two unhappy ones are real conditions rather than placeholders.
        @Test("the panel's three states each construct and each carry their own content")
        func statesConstruct() throws {
            let loading = CapabilityDocumentSheet(content: .loading)
            let populated = try CapabilityDocumentSheet(content: .document(document()))
            let unavailable = CapabilityDocumentSheet(content: .unavailable(.notServed))
            #expect(loading.content == .loading)
            #expect(populated.content != .loading)
            if case let .unavailable(error) = unavailable.content {
                #expect(!error.headline.isEmpty)
                #expect(!error.advice.isEmpty)
            } else {
                Issue.record("the unavailable state did not carry its error")
            }
        }

        // MARK: - What the panel refuses to draw

        /// The mock draws `What changed…`, `Install…` and `Update to 1.5.0`. This panel can perform
        /// none of the three, so it renders none of them unless a caller supplies one — a press that
        /// does nothing is `DESIGN.md` §6's honesty rule pointed outward at the reader. Declared as
        /// D2 in `planning/fidelity/readme.layers.json`; this is the assertion behind the note.
        @Test("the panel fabricates no action, and the seam a caller uses is the only way in")
        func noFabricatedActions() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Document/CapabilityDocumentSheet.swift"
            )
            for label in ["Install…", "Install...", "Update to", "What changed"] {
                #expect(!source.contains("\"\(label)"), "the panel spells its own \(label) action")
            }
            #expect(CapabilityDocumentSheet(content: .loading).actions.isEmpty)
        }

        /// The mock's foot says `Open on GitHub`. The destination is whatever the capability
        /// declared and this app has not resolved it, so the button says what it does. D7.
        @Test("the repository button names the act, not a host nobody checked")
        func repositoryButtonNamesTheAct() {
            #expect(!CapabilityDocumentSheet.openLabel.contains("GitHub"))
            #expect(CapabilityDocumentSheet.openLabel == "Open in your browser")
        }

        /// A repository URL is a third-party string, filtered where it is constructed rather than
        /// where it is pressed — so no view ever holds one this app would not open.
        @Test("a non-https repository never reaches the identity")
        func repositoryIsFilteredAtConstruction() {
            for spelling in ["http://example.com", "javascript:alert(1)", "file:///etc/passwd"] {
                let identity = CapabilityDocument.Identity(
                    name: "x", publisher: "y", pitch: "z", repository: URL(string: spelling)
                )
                #expect(identity.repository == nil, "\(spelling) survived")
            }
            let good = CapabilityDocument.Identity(
                name: "x", publisher: "y", pitch: "z",
                repository: URL(string: "https://example.com/a")
            )
            #expect(good.repository?.absoluteString == "https://example.com/a")
        }

        // MARK: - The shields, and the acceptance line M21 unparked

        /// The brief's second acceptance line: *the shield colours are the token values rather than
        /// the badge's own*. Two halves. The structural half is that `Shield` has nowhere to put a
        /// colour — asserted in `MarkdownSecurityTests`. This is the other half: the view reaches
        /// for one of exactly two `ColorToken`s, both of them fills that carry `--on-accent`.
        @Test("a shield's fill is one of the app's own two text-safe fills, never the badge's")
        func shieldFillsAreTokens() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Document/ShieldView.swift"
            )
            let body = try ShellTestSupport.declarationBody(
                of: "private var valueFill: ColorToken", in: source
            )
            #expect(body.contains(".shieldGood"))
            #expect(body.contains(".accentInk"))
            // Both are `fill` tokens carrying `--on-accent`, which is what the contrast floor was
            // measured for. A `text` token here would be measuring the wrong pair.
            #expect(ColorToken.shieldGood.contrastRole == ColorToken.accentInk.contrastRole)
            #expect(ColorToken.shieldGood.isReservedMeaning)
        }

        /// Every tone maps to a token, so a third tone cannot ship drawing nothing.
        @Test("every shield tone has a fill")
        func everyToneHasAFill() {
            #expect(Shield.Tone.allCases.count == 2)
            for tone in Shield.Tone.allCases {
                let shield = Shield(key: "k", value: "v", tone: tone)
                #expect(!ShieldView(shield: shield, index: 0).accessibilityText.isEmpty)
            }
        }

        // MARK: - The body is capped

        /// The brief: long documents scroll inside the sheet body, which is capped rather than
        /// growing the sheet past its window.
        @Test("the body caps below the sheet's own width, so a long document scrolls")
        func bodyIsCapped() {
            #expect(DocumentMetrics.bodyMaxHeight > 0)
            #expect(DocumentMetrics.bodyMaxHeight < DocumentMetrics.sheetWidth)
        }
    }
#endif
