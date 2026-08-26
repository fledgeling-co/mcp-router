#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// What the shell's suites share: the oracle reader, the scratch defaults domain, and the list
    /// of files the source-level gates scan.
    ///
    /// This is a namespace rather than a base type because Swift Testing suites are independent
    /// structs — four suites each re-declaring `repoFile` would be four chances for one of them to
    /// drift into reading a different file than the gate it backs.
    enum ShellTestSupport {
        enum OracleError: Error {
            case fileNotFound(String)
            case sectionNotFound(String)
        }

        /// The body of one declaration, extracted by balancing braces rather than by splitting on an
        /// indented `}`.
        ///
        /// The split form it replaces was **vacuous in two ways at once**, and two out-of-family
        /// reviews from different model families found both:
        ///
        /// 1. `components(separatedBy:)` never returns an empty array, so `.first` and `.last` are
        ///    non-`nil` even when the delimiter is absent entirely. Every `#require` guarding one of
        ///    those was unfailable, and its diagnostic string could never print.
        /// 2. Splitting on the FIRST `"\n        }"` ends the body at the first member-indented
        ///    brace. Today that is the declaration's own end, so the gates using it were correct by
        ///    layout; a nested `if`/closure closing at that indent — which `swiftformat` is free to
        ///    produce — would silently truncate the body, and every `!body.contains(…)` assertion
        ///    downstream would pass on text that no longer includes the region it is denying.
        ///
        /// Both failures are silent and both are green, which is the pair worth removing rather than
        /// patching. This throws where the old form returned something plausible.
        ///
        /// `marker` must appear exactly once: a second occurrence — an overload, or a comment
        /// quoting the signature — makes "which declaration" ambiguous, and picking either end of
        /// that ambiguity is how a scoped gate reads the wrong function.
        ///
        /// **What comes back is code with its line comments removed**, and that is the third hole a
        /// reviewer found rather than a tidiness point. Every gate built on this asks whether some
        /// string is in a view's body; the bodies in this repo carry long comments that *discuss the
        /// modifiers being asserted about*, so `body.contains(".accessibilityLabel(")` was satisfied
        /// by a paragraph explaining `.accessibilityLabel`, and a negative assertion is one careless
        /// sentence away from going vacuous the same way. Comments are prose about the code, not the
        /// code, so they are not what a source gate should be reading.
        static func declarationBody(of marker: String, in source: String) throws -> String {
            let occurrences = source.components(separatedBy: marker).count - 1
            guard occurrences == 1 else {
                throw OracleError.sectionNotFound(
                    "'\(marker)' appears \(occurrences) times, so which declaration is meant is ambiguous"
                )
            }
            guard let markerRange = source.range(of: marker),
                  let open = source[markerRange.upperBound...].firstIndex(of: "{")
            else {
                throw OracleError.sectionNotFound("'\(marker)' opens no brace")
            }

            var depth = 0
            var index = open
            var code = ""
            while index < source.endIndex {
                if let span = nonCodeSpan(source, from: index) {
                    // A string literal is code and stays; a comment is prose about the code and goes.
                    if span.isString, depth > 0 { code += source[index ..< span.end] }
                    index = span.end
                    continue
                }
                let character = source[index]
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 { return code }
                }
                if depth > 0 { code.append(character) }
                index = source.index(after: index)
            }
            throw OracleError.sectionNotFound("'\(marker)' is never closed")
        }

        /// The span of the comment or string literal starting at `index`, or `nil` when code starts
        /// there.
        ///
        /// Both are stepped over **whole**, by looking ahead rather than by remembering the previous
        /// character, and that is what makes the walk above safe on this repo's own source: a `}` or
        /// a `//` inside a string literal is text. `LoopbackAddress.controlEndpoint` returns
        /// `"http://\(hostPort(port))/mcp"`, so a scanner that treated `//` as a comment opener
        /// wherever it found one would swallow the rest of that line — which is the class of silent
        /// truncation this whole reader exists to remove, reintroduced one layer down.
        private static func nonCodeSpan(
            _ source: String,
            from index: String.Index
        ) -> (end: String.Index, isString: Bool)? {
            let rest = source[index...]
            if rest.hasPrefix("//") {
                return (rest.firstIndex(of: "\n") ?? source.endIndex, false)
            }
            if rest.hasPrefix("/*") {
                let after = source.index(index, offsetBy: 2)
                let close = source[after...].range(of: "*/")
                return (close?.upperBound ?? source.endIndex, false)
            }
            guard source[index] == "\"" else { return nil }
            return (endOfStringLiteral(source, openedAt: index), true)
        }

        /// Where the string literal opened at `index` closes, honouring backslash escapes.
        private static func endOfStringLiteral(
            _ source: String,
            openedAt index: String.Index
        ) -> String.Index {
            var cursor = source.index(after: index)
            while cursor < source.endIndex {
                if source[cursor] == "\\" {
                    cursor = source.index(cursor, offsetBy: 2, limitedBy: source.endIndex) ?? source.endIndex
                    continue
                }
                if source[cursor] == "\"" { return source.index(after: cursor) }
                cursor = source.index(after: cursor)
            }
            return source.endIndex
        }

        /// Waits for a condition to hold rather than for a duration to elapse.
        ///
        /// A fixed `Task.sleep` reads like a wait but is really a bet on scheduler latency, and the
        /// bet is lost exactly when the machine is busy. M5 measured the consequence: a 120ms sleep
        /// before asserting a poll had run passed 5 of 5 in isolation and failed about **four runs
        /// in five under full-suite load**, so every other item's gate had a standing chance of
        /// going red for reasons unrelated to its work — which is the worst kind of gate, because it
        /// teaches the reader to re-run until green.
        ///
        /// The timeout bounds only the failure case. A healthy poll satisfies the condition in a few
        /// milliseconds, so this is also *faster* than the sleep it replaces in the common case.
        ///
        /// Use it only where the assertion is that something BECOMES true. Where the assertion is
        /// that a state *stays* put — `ShellTests.loadingIsTheAbsenceOfAnAnswer` races a
        /// never-returning refresh — there is no condition to wait for and a fixed delay is correct.
        ///
        /// **30 seconds, not 5.** The ceiling is not a guess at how long the work takes — it is the
        /// point past which a stuck condition is worth reporting, and a bound that generous costs a
        /// passing test nothing because it returns the moment the condition holds. Five seconds was
        /// measured to be inside the noise: on 20 Aug 2026 `make test` reported four failures at a
        /// one-minute load average of ~700 and passed all 1473 tests on the same source at load 46,
        /// minutes apart (DEF-030). A suite that reports a defect the product does not have is the
        /// failure this campaign has already paid for once, in DEF-029, where a dead instrument
        /// read as a dead product for ten consecutive runs.
        @MainActor
        static func waitUntil(
            within timeout: Duration = .seconds(30),
            polling interval: Duration = .milliseconds(5),
            _ isSatisfied: () -> Bool
        ) async throws {
            let deadline = ContinuousClock.now + timeout
            while !isSatisfied(), ContinuousClock.now < deadline {
                try await Task.sleep(for: interval)
            }
        }

        /// Walks up to the repository root, the way `MenuCommandTests` finds its oracle.
        ///
        /// `#filePath` defaults to the *calling* file, and every shell suite sits in this same
        /// directory, so the walk is the same distance from each of them.
        static func repoFile(_ relativePath: String, from filePath: String = #filePath) throws -> String {
            var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            for _ in 0 ..< 8 {
                let candidate = dir.appendingPathComponent(relativePath)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return try String(contentsOf: candidate, encoding: .utf8)
                }
                dir = dir.deletingLastPathComponent()
            }
            throw OracleError.fileNotFound(relativePath)
        }

        /// The repository root, found by the file that is only ever at it.
        static func repoRoot(from filePath: String = #filePath) throws -> URL {
            var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            for _ in 0 ..< 8 {
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent("DESIGN.md").path) {
                    return dir
                }
                dir = dir.deletingLastPathComponent()
            }
            throw OracleError.fileNotFound("DESIGN.md")
        }

        /// A scratch `UserDefaults` domain, so restoration is tested against real defaults behaviour
        /// without writing into the developer's own preferences.
        ///
        /// A struct rather than a tuple: three anonymous members at a call site is three chances to
        /// unpack them in the wrong order, and the last two exist only to be torn down together.
        struct ScratchStore {
            let store: ShellRestoration
            let defaults: UserDefaults
            let suiteName: String

            func tearDown() {
                defaults.removePersistentDomain(forName: suiteName)
            }
        }

        static func scratchStore() throws -> ScratchStore {
            let suite = "mcprouter.tests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return ScratchStore(
                store: ShellRestoration(defaults: defaults),
                defaults: defaults,
                suiteName: suite
            )
        }

        @MainActor
        static func model(
            _ scenario: FixtureControlAPIClient.Scenario,
            at now: Date = Date(timeIntervalSince1970: 1_000_000)
        ) throws -> ShellModel {
            let scratch = try scratchStore()
            return ShellModel(client: FixtureControlAPIClient(scenario), store: scratch.store, clock: { now })
        }

        /// Every Swift file in the measurement harness, joined, so a test can read the target
        /// rather than one of its files.
        ///
        /// An empty directory throws rather than returning "", because a harness that had been
        /// moved or renamed would otherwise satisfy every `!contains` assertion written against it
        /// and report a surface nobody had read.
        static func measureDumpSources(from filePath: String = #filePath) throws -> String {
            let dir = try repoRoot(from: filePath).appendingPathComponent("app/Sources/MeasureDump")
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()
            guard !names.isEmpty else { throw OracleError.fileNotFound("app/Sources/MeasureDump") }
            return try names
                .map { try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }
                .joined(separator: "\n")
        }

        /// Everything the boundary gates scan.
        static var gatedFiles: [String] {
            shellFiles + boardFiles + activityFiles + settingsFiles
        }

        /// Every file that draws a surface, and so must obey §7's entry-motion rule.
        static var animatedSurfaceFiles: [String] {
            shellFiles + boardFiles + activityFiles + settingsFiles
        }
    }
#endif
