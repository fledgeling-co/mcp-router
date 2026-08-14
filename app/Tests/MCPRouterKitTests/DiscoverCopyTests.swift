import Foundation
import Testing
@testable import MCPRouterKit

/// A28 and A20: every string is in the manifest, every template's substitutions are enumerated,
/// and the narrowing is on every commit state.
///
/// Asserted three ways, as I1's pairing copy is: the key set is complete and reachable, the
/// literals are pinned, and every `{token}` a template carries is a declared `Token`.
@Suite("Discover copy — A28 and A20")
struct DiscoverCopyTests {
    // MARK: - The key set

    /// `Key.allCases` is hand-written, because `CaseIterable` is not synthesised for an enum with
    /// associated values. That hand-written concatenation is the one place a whole group could be
    /// dropped silently, shrinking the set every other completeness check runs over — so it is
    /// checked from the other direction: every case of every element type must be reachable.
    @Test("every element key is reachable from Key.allCases")
    func everyElementKeyIsReachable() {
        let all = Set(DiscoverCopy.Key.allCases)

        for key in DiscoverCopy.BandKey.allCases {
            #expect(all.contains(.band(key)))
        }
        for key in DiscoverCopy.WindowKey.allCases {
            #expect(all.contains(.window(key)))
        }
        for key in DiscoverCopy.UnitKey.allCases {
            #expect(all.contains(.unit(key)))
        }
        for key in DiscoverCopy.ListKey.allCases {
            #expect(all.contains(.list(key)))
        }
        for key in DiscoverCopy.DetailKey.allCases {
            #expect(all.contains(.detail(key)))
        }
        for key in DiscoverCopy.PlateKey.allCases {
            #expect(all.contains(.plate(key)))
        }
        for key in DiscoverCopy.CommitKey.allCases {
            #expect(all.contains(.commit(key)))
        }

        // The residual hole the loops above cannot see: a whole element type added to `Key` and
        // omitted from both `allCases` and this test. The total is pinned so that shows up.
        #expect(all.count == 53, "the manifest holds \(all.count) keys")
        #expect(DiscoverCopy.Key.allCases.count == all.count, "allCases contains a duplicate")
    }

    @Test("every key has non-empty copy and a distinct name")
    func everyKeyHasCopy() {
        var names: Set<String> = []
        for key in DiscoverCopy.Key.allCases {
            let entry = DiscoverCopy.entry(key)
            #expect(!entry.body.isEmpty, "\(key.name) has an empty body")
            #expect(entry.headline?.isEmpty != true, "\(key.name) has an empty headline")
            #expect(entry.actionLabel?.isEmpty != true, "\(key.name) has an empty action label")
            #expect(names.insert(key.name).inserted, "\(key.name) is not unique")
        }
    }

    /// A28: where copy carries a substitution, the template is pinned and its substitutions are
    /// enumerated. A typo'd `{mack}` would otherwise render literally to the user.
    @Test("every brace in every template is a declared Token")
    func everyBraceIsADeclaredToken() {
        for key in DiscoverCopy.Key.allCases {
            let entry = DiscoverCopy.entry(key)
            let text = (entry.headline ?? "") + entry.body + (entry.actionLabel ?? "")

            let declared = DiscoverCopy.Token.allCases.map(\.placeholder)
            var cursor = text.startIndex
            while let found = text.range(
                of: #"\{[a-zA-Z]+\}"#,
                options: .regularExpression,
                range: cursor ..< text.endIndex
            ) {
                let placeholder = String(text[found])
                #expect(
                    declared.contains(placeholder),
                    "\(key.name) carries \(placeholder), which is not a Token"
                )
                cursor = found.upperBound
            }
        }
    }

    /// A token with no supplied value stays visible rather than emptying the sentence.
    @Test("an unsupplied token is left as its placeholder, not silently removed")
    func unsuppliedTokenSurvives() {
        let entry = DiscoverCopy.entry(.commit(.alreadyDeclared)).resolved([.name: "GitHub"])
        #expect(entry.body.contains("GitHub"))
        #expect(entry.body.contains("{mac}"), "a dropped subject reads as finished prose")
    }

    // MARK: - A20

    @Test("the narrowing set is exactly the seven commit states")
    func narrowingCoversEveryCommitState() {
        #expect(DiscoverCopy.narrowingKeys.count == 7)
        for key in DiscoverCopy.CommitKey.allCases {
            #expect(DiscoverCopy.narrowingKeys.contains(.commit(key)), "\(key) is not narrowed")
            #expect(DiscoverCopy.entry(.commit(key)).carriesNarrowing, "\(key) does not carry it")
        }
        // Nothing outside the commit carries it, so the claim stays a claim about the commit.
        for key in DiscoverCopy.Key.allCases where key.surface != .commit {
            #expect(!DiscoverCopy.entry(key).carriesNarrowing, "\(key.name) narrows unexpectedly")
        }
    }

    /// The narrowing is `PairingCopy.neverInstalls` **verbatim**, never a paraphrase. Three
    /// paraphrases of a permission boundary is how a user ends up believing the loosest one.
    @Test("the narrowing sentence is PairingCopy's, and states the boundary it names")
    func narrowingIsShared() {
        let narrowing = PairingCopy.neverInstalls.lowercased()
        #expect(!narrowing.isEmpty)
        // The two halves of the boundary: what this app does, and what only the Mac does.
        #expect(narrowing.contains("queues items for review"))
        #expect(narrowing.contains("cannot install"))
    }

    // MARK: - Pinned literals

    @Test("the band notes scope themselves to the results shown, and name both stamps")
    func bandNotesArePinned() {
        let mostUsed = DiscoverCopy.entry(.band(.mostUsedNote)).body
        #expect(mostUsed.contains("of the results shown"))
        #expect(mostUsed.contains("rather than ranked at zero"))

        // H5: `updatedAt` is an update stamp for one index and a creation stamp for the other, and
        // the note is the one place that difference is stated.
        let changed = DiscoverCopy.entry(.band(.recentlyChangedNote)).body
        #expect(changed.contains("of the results shown"))
        #expect(changed.contains("last edited"))
        #expect(changed.contains("created"))
    }

    /// A6: the popularity figure names the quantity *and* who published it.
    @Test("the popularity unit says sessions on Smithery, never installs or downloads")
    func popularityUnitIsPinned() {
        let unit = DiscoverCopy.entry(.unit(.useCount)).body
        #expect(unit == "{count} sessions on Smithery")
        #expect(!unit.lowercased().contains("install"))
        #expect(!unit.lowercased().contains("download"))
    }

    /// A9: plural, because two indexes are searched and either can fail alone — and it never
    /// promises skills, because there is no skills index on either router.
    @Test("the search placeholder is plural and promises no skills")
    func placeholderIsPinned() {
        let placeholder = DiscoverCopy.entry(.unit(.searchPlaceholder)).body
        #expect(placeholder == "Search the server registries")
        #expect(!placeholder.lowercased().contains("skill"))
    }

    /// A16: verb-first, and no ellipsis — it commits now rather than opening a further view.
    @Test("no commit label carries an ellipsis, and none says install")
    func commitLabelsCommitNow() throws {
        for key in DiscoverCopy.CommitKey.allCases {
            let entry = DiscoverCopy.entry(.commit(key))
            let label = try #require(entry.actionLabel)
            #expect(!label.contains("…"), "\(key) opens a further view")
            #expect(!label.contains("..."), "\(key) opens a further view")
            #expect(!label.lowercased().contains("install"), "\(key) reads as installing")
            #expect(!label.lowercased().contains("add to"), "\(key) reads as installing")
        }
    }

    /// A21: no item owns flush-on-reachable, so no copy may promise one.
    @Test("no copy promises an automatic send")
    func nothingPromisesAnAutomaticSend() {
        let promises = ["automatically", "on its own", "when it reconnects", "will send itself"]
        for key in DiscoverCopy.Key.allCases {
            let entry = DiscoverCopy.entry(key)
            let text = ((entry.headline ?? "") + entry.body).lowercased()
            for promise in promises {
                #expect(!text.contains(promise), "\(key.name) promises \(promise)")
            }
        }
    }

    /// A5 + A4: three band-empty sentences, because one cannot be true of all three cases.
    ///
    /// The single shared template rendered "Nothing in these results changed in the last Any time
    /// days" under the default window — ungrammatical, and false, since under Any time no window
    /// is applied. It was also used for Most used, which the window does not reach at all.
    @Test("each band-empty sentence fits the case it describes")
    func bandEmptyCopyIsSplit() {
        // Most used: no window language, and no action, because none would change what is shown.
        let mostUsed = DiscoverCopy.entry(.list(.bandEmptyMostUsed))
        #expect(mostUsed.headline?.contains("session count") == true)
        #expect(mostUsed.actionLabel == nil, "Most used offers an action the window cannot deliver")
        #expect(!(mostUsed.headline ?? "").contains("{window}"))
        #expect(!(mostUsed.body).lowercased().contains("widen the window"))

        // Recently changed under Any time: no window was applied, so it says something else.
        let anyTime = DiscoverCopy.entry(.list(.bandEmptyRecentlyChangedAnyTime))
        #expect(anyTime.actionLabel == nil, "the action reset the window already selected")
        #expect(!(anyTime.headline ?? "").contains("{window}"))

        // Only the windowed sentence carries the substitution and the reset.
        let windowed = DiscoverCopy.entry(.list(.bandEmptyRecentlyChangedWindowed))
        #expect(windowed.headline?.contains("{window}") == true)
        #expect(windowed.actionLabel == "Any time")
    }

    /// A23: the router compares display names, so the copy may not assert an identity the
    /// comparison cannot establish.
    @Test("already-declared copy states the name match rather than an identity")
    func alreadyDeclaredIsHonest() {
        let body = DiscoverCopy.entry(.commit(.alreadyDeclared)).body
        #expect(body.contains("A server called {name}"))
        #expect(!body.lowercased().contains("this server is already installed"))
    }
}
