import Foundation

// The Signal Path's rules, as values rather than as a view.
//
// **Why this is in the UI-free target**, and it is the same reason `ServerPresentation.swift` gives:
// the brief names state correctness as the thing that failed twice in the prototype — a warm server
// told it was about to be reaped, a lever raised for a process that was not running. Those are
// wrong answers from a branch, and a branch only a running app can exercise is a branch that ships
// wrong. Everything below is a pure function of what the router reported.
//
// Nothing here derives a figure the router did not send. The countdown is
// `ServerSubtitle.reapSeconds(_:idleMs:)` — the same function the row's own subtitle calls, against
// the same horizon the router sent — so the two readings of one server cannot disagree about how
// long is left.

// MARK: - What a jack is showing

/// The five conditions a jack draws. One dormant, four lit or marked.
///
/// It replaces `BreakerState`, and the split from four cases to five is the mock's: the lever had a
/// single `wantsYou` because a lamp is not separable from a lever, while a jack carries a **word**
/// as well as a colour, and `2 held changes` and `needs sign-in` are two different things to say.
public enum JackState: String, CaseIterable, Sendable {
    /// A child process is up.
    case live
    /// Failed, or placarded by the user. Inoperative either way.
    case tripped
    /// Holding tool-description changes until someone reads the diff.
    case held
    /// The upstream supports authorisation and has not been authorised.
    case needsSignIn
    /// No child process, and nothing to decide.
    case dormant

    /// The token that fills the plug, or `nil` when nothing is lit — an unplugged jack is
    /// `--jack-off`, which is a socket rather than a dimmed light.
    ///
    /// Four states, three colours: `held` and `needsSignIn` are both things waiting on a person, so
    /// they take the same hue and are told apart by their words. That is `DESIGN.md` §3 rule 10
    /// working the way it is supposed to — colour narrows, the word decides.
    public var indicator: ColorToken? {
        switch self {
        case .live: .live
        case .tripped: .fail
        case .held, .needsSignIn: .attention
        case .dormant: nil
        }
    }

    /// Whether a child process is up. The plug's whole meaning, as one property.
    public var isLit: Bool { self == .live }

    /// The legend's word for this state, and what a screen reader is told when there is no
    /// per-server condition to say instead.
    public var word: String {
        switch self {
        case .live: "awake"
        case .tripped: "tripped"
        case .held: "held"
        case .needsSignIn: "needs sign-in"
        case .dormant: "dormant"
        }
    }

    /// Which jack a server shows.
    ///
    /// **Running is checked first, and that is the invariant** — inherited from `BreakerState`
    /// unchanged, because the plug's meaning is the lever's: *"lights the moment something calls the
    /// server and goes dark when the reaper closes the child."* Lighting it for a server that is not
    /// running, or leaving it dark for one that is, is the only way this control can tell a lie.
    /// Attention therefore loses to running rather than the reverse, and what a running server is
    /// also waiting on is carried by its word, by the row's action and by the *Needs you* count.
    ///
    /// **An index error is not a sixth case, and that is a fact about the wire rather than a
    /// simplification.** `placardFor()` in `src/manifest.ts` returns the user's own placard first
    /// and `{ reason: entry.error }` second, so a server with an `indexError` always arrives
    /// carrying a placard and the `.tripped` arm below catches it. `JackPresentationTests` asserts
    /// that over the cross product rather than asserting this comment.
    public static func forServer(_ server: MCPServer) -> JackState {
        if server.state == .running { return .live }
        if server.placard != nil { return .tripped }
        if server.pendingChange != nil { return .held }
        if server.auth.supported, !server.auth.authorized { return .needsSignIn }
        return .dormant
    }
}

// MARK: - What a jack says

/// A jack's state and the two forms of the word under its name.
///
/// **Two strings, because the brief measured the need for them.** *"Where the width is tight, drop
/// the redundant word — the plug colour already says 'awake' — rather than clipping the
/// countdown."* A tail truncation would eat the end of the string, which is where the number is not;
/// dropping a word the plug is already carrying loses nothing. The **view** picks between them
/// against the real laid-out width, so neither form is chosen by a character budget guessed from a
/// glyph width.
///
/// `word` is what the accessibility label always carries, so the condition in full reaches a screen
/// reader at every width. The contraction is a drawing decision and never a state one.
public struct JackCondition: Equatable, Sendable {
    public let state: JackState
    /// The condition in full: `3:41 left`, `2 held changes`, `needs sign-in`, `never reaped`.
    public let word: String
    /// The same fact with the word the plug already carries removed: `3:41`, `2 held`. Equal to
    /// `word` wherever there is nothing redundant to drop.
    public let contracted: String

    public init(state: JackState, word: String, contracted: String? = nil) {
        self.state = state
        self.word = word
        self.contracted = contracted ?? word
    }

    /// What this server's jack shows, and what it says.
    ///
    /// **The word's precedence is not the plug's, and the difference is load-bearing.** The plug
    /// says whether a child is up, so nothing outranks `running`. The word is what a person reads,
    /// and `ServerSubtitle` has put `warm` above `running` since M3 because the reaper skips a warm
    /// server — *"a warm server never shows a reap countdown."* A single chain would draw
    /// `3:41 left` on a warm running server while the hub above it reads `1 at rest`, which is a
    /// contradiction on one surface about one server.
    ///
    /// So the word is computed from the state **plus** `warm`, and no input reaches a countdown
    /// with `warm == true`.
    public static func forServer(_ server: MCPServer, idleMs: Int?) -> JackCondition {
        let state = JackState.forServer(server)
        switch state {
        case .live:
            guard !server.warm else {
                return JackCondition(state: state, word: "never reaped", contracted: "warm")
            }
            return live(server, idleMs: idleMs)
        case .tripped:
            return JackCondition(state: state, word: "tripped")
        case .held:
            let count = server.pendingChange?.count ?? 0
            let noun = count == 1 ? "change" : "changes"
            return JackCondition(
                state: state, word: "\(count) held \(noun)", contracted: "\(count) held"
            )
        case .needsSignIn:
            return JackCondition(state: state, word: "needs sign-in")
        case .dormant:
            return JackCondition(state: state, word: server.warm ? "warm" : "dormant")
        }
    }

    /// A running server that is not warm: how long until the reaper would close it.
    ///
    /// An **unknown** horizon says `awake` and no number, because "how long is left" is a question
    /// nothing has answered. `ServersBoardModel` passes `idleMs` through rather than defaulting it,
    /// and the prototype's hardcoded 300 seconds is precisely the invention `DESIGN.md` §6 forbids.
    private static func live(_ server: MCPServer, idleMs: Int?) -> JackCondition {
        guard let idleMs else {
            return JackCondition(state: .live, word: "awake")
        }
        let clock = mmss(ServerSubtitle.reapSeconds(server, idleMs: idleMs))
        return JackCondition(state: .live, word: "\(clock) left", contracted: clock)
    }

    /// Seconds as the mock writes them — `3:41`, and `221:00` rather than a rolled-over hour, because
    /// a horizon is minutes and an hours field would be a column of zeros on every row that has one.
    static func mmss(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
