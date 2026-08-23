#if os(macOS)
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The retirement of the shell's placeholder, and the invariant that replaced it.
    ///
    /// **Split out of `ShellIntegrationTests` by M6**, on a real seam rather than to satisfy a
    /// number: these tests are all about one subject — whether every destination has a board and
    /// whether the placeholder can come back — while that suite is about the window, its menus and
    /// its keyboard. The split was forced by the 400-line file cap, which `make format`'s wrapping
    /// pushed the combined file past; the cap was met by splitting, never raised, per this repo's
    /// own lesson from R2R.
    @Suite("The scaffold is retired, and what replaced it")
    struct ShellScaffoldRetirementTests {
        /// Every destination has a board, asserted as a set equality rather than as a complement.
        ///
        /// **This test has been re-pointed twice, and the reason is worth keeping.** It first read
        /// "M1 installs no board, so every destination is scaffolded" and asserted `installed
        /// .isEmpty` — which was the *state* rather than the invariant, and a board landing failed it
        /// for doing exactly what it was supposed to. It then became a two-way complement, which held
        /// through M2–M7. As of M6 `scaffolded` is permanently empty, and a disjointness check
        /// against an empty set is vacuously true — a green that means nothing.
        ///
        /// So the assertion is now the thing that is actually still capable of being false: **every
        /// destination is installed**. Add a case to `Destination` and forget to register it and this
        /// fails, which is the one mistake the whole scaffold mechanism existed to prevent. The
        /// complement is kept as the second assertion because it is the same fact stated from the
        /// other side, and it is what fails first if `scaffolded` ever stops being derived.
        @Test("every destination has a board, and nothing is scaffolded")
        func everyDestinationIsInstalled() {
            #expect(
                BoardRegistry.installed == Set(Destination.allCases),
                "a Destination was added without registering its board"
            )
            #expect(BoardRegistry.scaffolded.isEmpty)
            #expect(BoardRegistry.installed.count == Destination.allCases.count)
            for destination in Destination.allCases {
                #expect(BoardRegistry.hasBoard(destination), "\(destination.title) has no board")
            }
        }

        /// The count, stated separately so a board landing or vanishing is a deliberate edit here
        /// rather than something a set-algebra assertion waves through.
        @Test("this build installs exactly the boards that have shipped")
        func installedIsTheShippedSet() {
            #expect(
                BoardRegistry.installed
                    == [
                        .servers, .activity, .skills, .harnesses,
                        .discover, .evals, .cleanup, .inbox, .insights
                    ],
                """
                M2 Activity, M3 Servers, M4 Skills, M5 Discover, M7 Evals + Cleanup, M6 Inbox — \
                M15 took M8's Settings board back out, into a Settings scene, and M22 added \
                Harnesses and Insights
                """
            )
            // `isEmpty` rather than `count == 0`, which the linter prefers and which says the same
            // thing. The count assertion that used to sit here pinned "one destination is still
            // scaffolded"; there is no such number left to pin, so what carries the weight now is
            // the set equality above.
            #expect(BoardRegistry.scaffolded.isEmpty)
        }

        /// M3's own half: the board is not merely written, it is **registered**.
        @Test("the Servers board is installed")
        func serversBoardIsInstalled() {
            #expect(BoardRegistry.hasBoard(.servers))
            #expect(!BoardRegistry.scaffolded.contains(.servers))
        }

        /// M2's own half, for the same reason.
        @Test("the Activity board is installed")
        func activityBoardIsInstalled() {
            #expect(BoardRegistry.hasBoard(.activity))
            #expect(!BoardRegistry.scaffolded.contains(.activity))
        }

        /// M6's own half, and the last one.
        @Test("the Inbox board is installed, which completes the set")
        func inboxBoardIsInstalled() {
            #expect(BoardRegistry.hasBoard(.inbox))
            #expect(!BoardRegistry.scaffolded.contains(.inbox))
        }

        /// The placeholder cannot come back.
        ///
        /// **This replaces two tests that lost their subject when M6 deleted the scaffold**, and it
        /// is deliberately a source-level assertion rather than a type-level one, because there is no
        /// longer a type to assert against — `ScaffoldedDestination` and `ScaffoldCopy` are gone, so
        /// `ScaffoldedDestination(.inbox) != nil` and `#require(scaffolded.first)` would not compile,
        /// let alone test anything.
        ///
        /// What is still capable of being false is that someone reintroduces the sentence. So this
        /// scans every shell and board source for it **as a string literal**, and passes only if the
        /// single occurrence is the documented comment in `ScaffoldPane.swift` that
        /// `scripts/acceptance/mac-shell.sh:884` reads to know what to search the Release bundle
        /// for. A `let` putting it back into the binary fails here, and would fail that gate too.
        @Test("the placeholder sentence exists only as the retired-string comment")
        func placeholderIsNotReintroduced() throws {
            let sentinel = "isn't built yet"
            for path in ShellTestSupport.shellFiles + ShellTestSupport.settingsFiles {
                let source = try ShellTestSupport.repoFile(path)
                guard source.contains(sentinel) else { continue }
                #expect(
                    path.hasSuffix("ScaffoldPane.swift"),
                    "\(path) reintroduced the placeholder sentence"
                )
                // In the registry file it must be a comment, never a compiled literal: every line
                // carrying it starts a doc comment.
                for line in source.split(separator: "\n") where line.contains(sentinel) {
                    #expect(
                        line.trimmingCharacters(in: .whitespaces).hasPrefix("///"),
                        "the sentinel is compiled into the binary rather than documented: \(line)"
                    )
                }
            }
        }

        /// The types the placeholder was built from are gone, asserted where a compiler cannot.
        ///
        /// A deleted type cannot be named in a test, so this reads the source instead. It is the
        /// half of the retirement that a build success does not prove: `ScaffoldPane.swift` still
        /// exists and still compiles, so nothing else would notice the pane being added back.
        @Test("the scaffold types are not reintroduced")
        func scaffoldTypesStayDeleted() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Shell/ScaffoldPane.swift"
            )
            for symbol in ["struct ScaffoldedDestination", "enum ScaffoldCopy", "struct ScaffoldPane"] {
                #expect(!source.contains(symbol), "\(symbol) came back")
            }
            // And the file still holds what four acceptance scripts read out of it.
            #expect(source.contains("installed: Set<Destination>"))
        }
    }
#endif
