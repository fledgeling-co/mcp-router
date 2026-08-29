import Foundation

/// Which CLI runs the judgement, and with which model.
///
/// **A closed set of five, taken from `PRD.md` §6.3 rather than from a free-text field.** The whole
/// argument for this design is that the analyst costs nothing and needs no key: it runs through a
/// binary the user is already signed into. A lane the user could type would be a lane the router
/// would have to spawn without knowing what it is, and the promise that nothing leaves this Mac
/// would rest on the spelling of a string in a settings file.
public enum AnalystLane: String, Sendable, Hashable, CaseIterable {
    case claude
    case cursor
    case grok
    case codex
    case gemini

    /// The binary this lane runs. Resolved on `PATH` by the runner, never as an absolute path: the
    /// three CLIs here install to at least four different prefixes between Homebrew, npm and a
    /// vendor installer, and a pinned path is a lane that works on one machine.
    public var binary: String {
        switch self {
        case .claude: "claude"
        case .cursor: "cursor-agent"
        case .grok: "grok"
        case .codex: "codex"
        case .gemini: "agy"
        }
    }

    /// The model this lane judges with. The cheap rung of each family, which is the point of the
    /// feature: an analyst that costs a paid call per run is one nobody leaves switched on.
    public var model: String {
        switch self {
        case .claude: "claude-haiku-4-5"
        case .cursor: "composer"
        case .grok: "grok-4.6"
        case .codex: "gpt-5.6-luna"
        case .gemini: "gemini-3.7-flash-high"
        }
    }

    /// What the Insights card shows — the design's own spelling, `Claude CLI · haiku`.
    public var label: String {
        switch self {
        case .claude: "Claude CLI · haiku"
        case .cursor: "Cursor CLI · composer"
        case .grok: "Grok CLI · grok-4.6 medium"
        case .codex: "Codex CLI · gpt-5.6-luna low"
        case .gemini: "Antigravity · gemini-3.7-flash-high"
        }
    }

    /// The whole argument vector, prompt included, with **no shell anywhere**.
    ///
    /// The prompt carries excerpts of the user's own session logs, which is the most quoting-hostile
    /// input this router handles: a backtick or a `$(` in a command somebody ran would be executed
    /// by a shell that saw it. `Process` is given `arguments` directly, so there is no shell to
    /// see it, and this function returns the vector rather than a command line so that no caller
    /// can join it back into one.
    ///
    /// Each lane's effort is pinned rather than inherited, for the reason the referral lanes are
    /// pinned everywhere else in this repository: a lane running at its config default is not the
    /// lane that was chosen, and the run would report a model it did not use.
    public func arguments(prompt: String) -> [String] {
        switch self {
        case .claude: ["--model", model, "-p", prompt]
        case .cursor: ["-p", "--force", "--model", model, prompt]
        case .grok: ["-m", model, "--effort", "medium", "-p", prompt]
        case .codex:
            ["exec", "-m", model, "-c", "model_reasoning_effort=\"low\"", "-s", "read-only", prompt]
        case .gemini: ["--new-project", "--model", model, "-p", prompt]
        }
    }
}

/// How often the analyst is meant to run.
///
/// **A setting, and this item does not turn it into a schedule** — `spec-F7.md` §2 records why, and
/// the wire carries `scheduled: false` beside it so that no surface can read `Every 6 hours` as a
/// promise the router keeps. ``nextRunAt(after:)`` is what a schedule *would* fire on, computed
/// from the last run so the readout is derived rather than asserted.
public enum AnalystCadence: String, Sendable, Hashable, CaseIterable {
    case manual
    case sixHourly
    case twelveHourly
    case daily

    public var label: String {
        switch self {
        case .manual: "Only when I ask"
        case .sixHourly: "Every 6 hours"
        case .twelveHourly: "Every 12 hours"
        case .daily: "Once a day"
        }
    }

    /// `nil` for ``manual``, which is an absence rather than a very long interval: a surface that
    /// received a number here would draw a next-run time for a cadence that has none.
    public var intervalMilliseconds: Double? {
        switch self {
        case .manual: nil
        case .sixHourly: 6 * 3_600_000
        case .twelveHourly: 12 * 3_600_000
        case .daily: 24 * 3_600_000
        }
    }

    /// When a run would next be due, or `nil` when there is no cadence or no run to count from.
    public func nextRunAt(after lastRunMilliseconds: Double?) -> Double? {
        guard let interval = intervalMilliseconds, let last = lastRunMilliseconds else { return nil }
        return last + interval
    }
}
