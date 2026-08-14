#if os(macOS)
    import MCPRouterKit

    /// Which destinations have a board.
    ///
    /// **Every destination now has one, and the placeholder this file was named for is gone.** M6
    /// was the eighth and last board; `ScaffoldedDestination`, `ScaffoldCopy` and `ScaffoldPane` are
    /// deleted rather than left registering an empty set, because
    /// `scripts/acceptance/mac-shell.sh:952` requires the Release bundle **not** to contain the
    /// placeholder sentence once `installed` covers every destination — and a compiled
    /// `ScaffoldCopy.sentinel` *is* that sentence.
    ///
    /// **Why this file survives with a name it no longer earns.** Four acceptance scripts read
    /// `installed` out of this exact path — `mac-shell.sh`, `m2-activity.sh`, `m5-discover.sh` and
    /// `m7-evals-cleanup.sh` — and `mac-shell.sh:884` additionally greps the sentinel out of it, and
    /// *blocks* when it cannot find one. So deleting the file would not satisfy that gate; it would
    /// stop it running. Renaming it means editing four other items' scripts inside this item's diff,
    /// which the diff-scope rule forbids. The rename is registered as `D-m6-c` for whoever can move
    /// the scripts in the same change.
    ///
    /// The sentence itself is recorded below **as a comment**, in the shape that grep matches.
    /// A comment is not compiled, so the gate can still read the string it must search the bundle
    /// for while the bundle no longer contains it — which is what lets the Release assertion be
    /// *reached* rather than blocked. A `let` would put it straight back into the binary.
    ///
    ///     sentinel = "isn't built yet"
    ///
    public enum BoardRegistry {
        /// Destinations whose real surface is compiled into this build — now all of them.
        ///
        /// M2–M8 each added exactly one entry here alongside the view that justified it, and this
        /// line rather than the view was the moment each item shipped: without it `ContentZone`
        /// rendered a placeholder however complete the view was. M6's `.inbox` closes the set.
        ///
        /// **This declaration wraps**, and must keep doing so carefully: the reader in
        /// `scripts/acceptance/board-registry.sh` collects from `[` to the matching `]` across any
        /// number of lines, so a change to this shape wants that awk block checked. The comment
        /// above sits deliberately **before** the declaration rather than between it and its
        /// closing bracket, where a stray `[` would be swept into the collected line.
        public static let installed: Set<Destination> = [
            .servers, .skills, .activity, .settings, .discover, .evals, .cleanup, .inbox
        ]

        public static func hasBoard(_ destination: Destination) -> Bool {
            installed.contains(destination)
        }

        /// The destinations still showing a placeholder, in sidebar order.
        ///
        /// Permanently empty now, and kept rather than deleted because it is what
        /// `ShellIntegrationTests` asserts the complement against: a `Destination` added later and
        /// forgotten here appears in this list, and that assertion fails. An empty computed property
        /// is the cheapest possible tripwire for the one mistake this whole mechanism existed to
        /// prevent.
        public static var scaffolded: [Destination] {
            Destination.ordered.filter { !hasBoard($0) }
        }
    }
#endif
