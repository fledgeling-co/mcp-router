#if os(macOS)
    import MCPRouterKit

    /// Which destinations have a board.
    ///
    /// **Every destination now has one, and the placeholder this file was named for is gone.** M6
    /// was the eighth and last board; `ScaffoldedDestination`, `ScaffoldCopy` and `ScaffoldPane` are
    /// deleted rather than left registering an empty set, because `mac-shell.sh` requires the
    /// Release bundle not to carry the placeholder once `installed` covers every destination — and
    /// a compiled `ScaffoldCopy` is exactly that.
    ///
    /// **Why this file survives with a name it no longer earns.** Four acceptance scripts read
    /// `installed` out of this exact path — `mac-shell.sh`, `m2-activity.sh`, `m5-discover.sh` and
    /// `m7-evals-cleanup.sh`. So deleting the file would not satisfy those gates; it would stop
    /// them running. Renaming it means editing four other items' scripts inside this item's diff,
    /// which the diff-scope rule forbids. The rename is registered as `D-m6-c` for whoever can move
    /// the scripts in the same change.
    ///
    /// The retired sentence is recorded below **as a comment**, in the shape a grep matches, and
    /// `ShellScaffoldRetirementTests.placeholderIsNotReintroduced` keys off it: it scans the files
    /// in `ShellTestSupport.shellFiles` and passes only if the sole occurrence among them is this
    /// comment. **That list is `MCPRouterUI/Shell/` only**, so it does not reach
    /// `MCPRouterKit/Shell/MenuCommand.swift`, where the same sentence lives — legitimately — as
    /// `CommandAvailability.surfaceAbsent`'s help tag. So the guard covers this directory, not the
    /// whole app, and a `let` in the Kit would not fail it. Stated rather than implied, because a
    /// guard believed to be wider than it is, is worse than a narrow one.
    ///
    ///     sentinel = "isn't built yet"
    ///
    /// **M14 changed what the Release gate greps for, and this comment used to describe the old
    /// arrangement.** `mac-shell.sh` no longer reads the sentence out of this file, because that
    /// sentence is also `surfaceAbsent`'s live help tag — a legitimate reason for a build genuinely
    /// missing a board — so matching it in the bundle reported "the scaffold outlived the surface
    /// it stood in for" about a scaffold that had been deleted. The gate now searches the Release
    /// bundle for `ScaffoldCopy` and `ScaffoldedDestination`, the two types only the placeholder
    /// ever declared. `scaffoldTypesStayDeleted` covers the same names **in this file only**; the
    /// gate is what covers the shipping artifact wherever they are declared. `ScaffoldPane` is not
    /// one of the needles: this file's own **name** survives in the binary's metadata, so it would
    /// fail for a benign reason.
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
