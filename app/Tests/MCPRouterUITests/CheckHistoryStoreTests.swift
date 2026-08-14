#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The bounded local history: what it keeps, what it refuses, and what it does with a bad file.
    ///
    /// The store was written with none of this, which the plan's own Phase B asked for by name
    /// ("cap, eviction, refusal-to-write, corrupt-file recovery"). Every assertion here is against
    /// the **file on disk** rather than only the in-memory dictionary, because three of the four
    /// rules are about persistence and an in-memory-only check would pass for a store that never
    /// wrote anything.
    @Suite("The check history store")
    struct CheckHistoryStoreTests {
        private static func scratch() throws -> URL {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("m7-history-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        private static func results() -> [CheckResult] {
            [CheckResult(.indexes, .passed), CheckResult(.callsSucceed, .unknown)]
        }

        private static let subject = SubjectKey.server("alpha")

        /// A12, and asserted where the rule actually lives: **the bytes on disk**.
        ///
        /// `record` returning false is the cheap half. The half that matters is that nothing was
        /// written, because a row stored without a stamp is a row that can never be known to be out
        /// of date — which is a worse answer than no row. A `.standalone` skill and a
        /// never-declared server both reach this path through `Stamp`'s failable initialiser.
        @MainActor
        @Test("A12: a run with no stamp is refused, and the file is not touched")
        func unstampedRunWritesNothing() throws {
            let directory = try Self.scratch()
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("check-history.json")
            let store = CheckHistoryStore(directory: directory)

            // A stamped run first, so there is a real file to leave unchanged — otherwise "no file"
            // would satisfy this test for a store that also refuses stamped runs.
            let stamp = try #require(Stamp("abc123"))
            #expect(store.record(subject: Self.subject, stamp: stamp, results: Self.results()))
            let before = try Data(contentsOf: file)

            #expect(store.record(subject: Self.subject, stamp: Stamp(nil), results: Self.results()) == false)
            #expect(store
                .record(subject: Self.subject, stamp: Stamp("   "), results: Self.results()) == false)

            let after = try Data(contentsOf: file)
            #expect(before == after, "an unstamped run changed the file")
            #expect(store.history(for: Self.subject).count == 1)
        }

        /// A13: the cap is real, and it evicts the **oldest**, which is the half a count alone misses.
        @MainActor
        @Test("A13: the 21st run evicts the oldest, and twenty survive")
        func capacityEvictsTheOldest() throws {
            let directory = try Self.scratch()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CheckHistoryStore(directory: directory)
            let base = Date(timeIntervalSince1970: 1_000_000)

            for index in 0 ..< (CheckHistoryStore.capacity + 1) {
                let stamp = try #require(Stamp("v\(index)"))
                store.record(
                    subject: Self.subject,
                    stamp: stamp,
                    results: Self.results(),
                    at: base.addingTimeInterval(Double(index))
                )
            }

            let history = store.history(for: Self.subject)
            #expect(history.count == CheckHistoryStore.capacity)
            // Newest first, so the survivor list runs v20 … v1 and v0 is gone.
            #expect(history.first?.stamp.value == "v20")
            #expect(history.last?.stamp.value == "v1")
            #expect(!history.contains { $0.stamp.value == "v0" }, "the oldest run was not the one evicted")
        }

        /// A11: an invalidated run stays in history rather than being deleted.
        ///
        /// Invalidation is a *rendering* decision made by `historyRowState`; the run itself is
        /// evidence of what was observed at the time and remains true. Dropping it would quietly
        /// erase the record whenever a server's declaration was edited.
        @MainActor
        @Test("A11: a run whose stamp has since moved is still in the history")
        func invalidatedRunSurvives() throws {
            let directory = try Self.scratch()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CheckHistoryStore(directory: directory)

            let gathered = try #require(Stamp("hash-one"))
            store.record(subject: Self.subject, stamp: gathered, results: Self.results())

            let live = try #require(Stamp("hash-two"))
            let run = try #require(store.history(for: Self.subject).first)
            let state = CheckPresentation.historyRowState(run: run, live: live)
            #expect(state == .invalidated(stored: "hash-one", live: "hash-two"))
            #expect(state.isInvalidated)
            #expect(store.history(for: Self.subject).count == 1, "an invalidated run was dropped")
        }

        /// Persistence is real: a second store over the same directory reads what the first wrote.
        @MainActor
        @Test("a run recorded by one store is read back by the next")
        func historySurvivesANewStore() throws {
            let directory = try Self.scratch()
            defer { try? FileManager.default.removeItem(at: directory) }
            let stamp = try #require(Stamp("abc123"))
            CheckHistoryStore(directory: directory)
                .record(subject: Self.subject, stamp: stamp, results: Self.results())

            let reopened = CheckHistoryStore(directory: directory)
            #expect(reopened.loadError == nil)
            #expect(reopened.history(for: Self.subject).count == 1)
            #expect(reopened.history(for: Self.subject).first?.stamp.value == "abc123")
        }

        /// A corrupt file starts empty, keeps the board working, and **says so**.
        ///
        /// The last clause is the one worth testing: "there is no history" and "the history could
        /// not be read" are different claims, and a store that swallowed the error would leave the
        /// pane making the first one when the second is true.
        @MainActor
        @Test("a corrupt history file starts empty and reports why rather than claiming none")
        func corruptFileIsReportedNotSwallowed() throws {
            let directory = try Self.scratch()
            defer { try? FileManager.default.removeItem(at: directory) }
            try Data("{ not json at all".utf8)
                .write(to: directory.appendingPathComponent("check-history.json"))

            let store = CheckHistoryStore(directory: directory)
            #expect(store.history(for: Self.subject).isEmpty)
            let error = try #require(store.loadError, "a corrupt file was read as an empty history")
            #expect(!error.isEmpty)
        }

        /// Subjects do not bleed into each other, including across kinds with the same id.
        @MainActor
        @Test("a server and a skill sharing an id keep separate histories")
        func subjectsAreKeyedByKindAndId() throws {
            let directory = try Self.scratch()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CheckHistoryStore(directory: directory)
            let stamp = try #require(Stamp("v1"))

            store.record(subject: .server("shared"), stamp: stamp, results: Self.results())
            #expect(store.history(for: .server("shared")).count == 1)
            #expect(
                store.history(for: SubjectKey(kind: .skill, id: "shared")).isEmpty,
                "a skill read a server's history because the key ignored the kind"
            )
        }

        /// A10, restated structurally as the plan requires.
        ///
        /// The first draft asserted "there is no input for which a stale verdict renders as a
        /// current pass", which is unbounded and untestable. This is the property that replaces it:
        /// **no board view or row type can reach the store at all**, so the code path a stale
        /// verdict would need does not exist. A property nothing can violate beats a claim nothing
        /// can check.
        ///
        /// `ShellModel` is the one legitimate reference — it constructs the store and hands it to
        /// the Evals board model — so it is excluded by name rather than by a loose pattern.
        @Test("A10: no board row or view type can reach the history store")
        func noBoardRowReachesTheStore() throws {
            let allowed = Set(["ShellModel.swift", "EvalsBoardModel.swift", "CheckHistoryStore.swift"])
            var offenders: [String] = []
            for file in ShellTestSupport.gatedFiles {
                let name = URL(fileURLWithPath: file).lastPathComponent
                guard !allowed.contains(name) else { continue }
                if try ShellTestSupport.repoFile(file).contains("CheckHistoryStore") {
                    offenders.append(name)
                }
            }
            #expect(
                offenders.isEmpty,
                "these reach the history store and could render a stored verdict as current: \(offenders)"
            )
            // Proven non-vacuous: the scan does cover a file that legitimately names the type.
            #expect(ShellTestSupport.gatedFiles.contains { $0.hasSuffix("EvalsBoardModel.swift") })
        }
    }
#endif
