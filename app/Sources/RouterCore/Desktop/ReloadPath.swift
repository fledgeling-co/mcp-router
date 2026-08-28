import Foundation

/// Whether a change reaches a running client, and **what established that** — R32.
///
/// The item this comes from is about a boundary rather than a mechanism. Claude Code sessions are
/// addressable while they run; Claude Desktop is a different application with a different lifecycle,
/// and the honest answer for it is not "no" but a shape this type exists to make un-blurrable: a
/// reload path was *located in the shipped artifact* and was *not exercised*.
///
/// That distinction is the whole value. A located path is a lead — it tells the next person where to
/// look and what to try. It is not a capability, and code that treats it as one propagates a change
/// and assumes it landed, which is the failure the brief names. So ``isReliable`` is true for
/// exactly one case, and every other case carries the sentence a person needs instead.
///
/// It follows ``HTTPCapability``'s design deliberately: the provenance lives in the case rather than
/// in a comment, because provenance in a comment is not read by the code that acts on the value.
public enum ReloadPath: Sendable, Hashable {
    /// Driven end to end and observed to work. `probe` is what was run, so it can be re-taken.
    case exercised(mechanism: String, actuation: Actuation, artifact: String, probe: String, on: String)

    /// Found in the shipped artifact and **not driven**. The strongest thing a static read can say,
    /// and weaker than it sounds: nothing here establishes that the mechanism works, only that it
    /// is there. `evidence` is what was read.
    case locatedNotExercised(
        mechanism: String, actuation: Actuation, artifact: String, evidence: String, on: String
    )

    /// Established absent — something was looked for and was not there. Carries its evidence for the
    /// same reason the other cases do: an absence claim with no instrument behind it is a guess.
    case absent(artifact: String, evidence: String, on: String)

    /// Nobody has looked. The honest default, and never a synonym for ``absent``.
    case unknown

    /// How the mechanism is actuated once you have it — which decides whether the router can use it.
    public enum Actuation: Sendable, Hashable {
        /// Reachable by another program: a socket, a signal, a CLI, a watched file.
        case programmatic
        /// A person clicks or types something. The router can *ask*; it cannot do.
        case humanOnly
        /// The application has to be started again, discarding whatever it held.
        case processRestart
    }

    /// **The only true case is ``exercised``.**
    ///
    /// A caller deciding whether to propagate a change silently reads this. `locatedNotExercised` is
    /// deliberately false: a path nobody has driven is a lead, and treating a lead as a capability
    /// is how a change gets reported as delivered because a mechanism that might exist was invoked.
    public var isReliable: Bool {
        if case .exercised = self { return true }
        return false
    }

    /// The actuation, where one is known. `nil` for ``absent`` and ``unknown``, which have none.
    public var actuation: Actuation? {
        switch self {
        case let .exercised(_, actuation, _, _, _), let .locatedNotExercised(_, actuation, _, _, _):
            actuation
        case .absent, .unknown:
            nil
        }
    }

    /// One line for a report, leading with the provenance rather than with the verdict.
    public var summary: String {
        switch self {
        case let .exercised(mechanism, actuation, artifact, probe, on):
            "\(mechanism) — \(actuation.described), exercised on \(artifact), \(on): \(probe)"
        case let .locatedNotExercised(mechanism, actuation, artifact, evidence, on):
            "\(mechanism) — \(actuation.described), located in \(artifact) on \(on) and NOT "
                + "exercised: \(evidence)"
        case let .absent(artifact, evidence, on):
            "no reload path — established absent on \(artifact), \(on): \(evidence)"
        case .unknown:
            "no reload path established, and none looked for"
        }
    }
}

public extension ReloadPath.Actuation {
    var described: String {
        switch self {
        case .programmatic: "a program can drive it"
        case .humanOnly: "only a person can drive it"
        case .processRestart: "the application has to be restarted"
        }
    }
}

public extension ReloadPath {
    /// What reaches a running Claude Desktop when `claude_desktop_config.json` changes underneath
    /// it, as measured on 2026-08-28.
    ///
    /// Four readings of Claude Desktop 1.30096.1's `app.asar`, and the transcript of each is in
    /// `planning/evidence/R32-acceptance.md`:
    ///
    ///   * the config is read by one `readFileSync` and memoised into a module-global, behind a
    ///     getter whose force-refresh parameter defaults to false;
    ///   * nothing watches the file — the bundle constructs no store with watching enabled, and its
    ///     single `watchFile(` is a library method that construction would have to reach;
    ///   * the force-refresh parameter has exactly one call site in the whole bundle, and it is a
    ///     menu item labelled **Reload MCP Configuration** under the Developer menu;
    ///   * there is no other way in: the only URL schemes the bundle registers are `claude:` and an
    ///     MSAL callback, and it ships no CLI and opens no local control socket.
    ///
    /// So the path is real and a person has to click it. It is `locatedNotExercised` rather than
    /// `exercised` because this item measured the artifact and never drove the application: Claude
    /// Desktop was not running when this was taken, and starting it to find out would put a window
    /// in front of whoever owns the machine.
    static let claudeDesktopConfigChange = ReloadPath.locatedNotExercised(
        mechanism: "Developer ▸ Reload MCP Configuration",
        actuation: .humanOnly,
        artifact: "Claude Desktop 1.30096.1 app.asar",
        evidence: "the memoised config getter's force-refresh arm has one call site, and it is "
            + "that menu item; no file watcher, no url scheme, no socket, no CLI",
        on: "2026-08-28"
    )
}
