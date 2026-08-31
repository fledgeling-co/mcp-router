namespace MCPRouter.Shell.Model.Servers;

/// <summary>
/// The five conditions a jack draws. One dormant, four lit or marked.
///
/// The split from four cases to five is the design of record's, and the words are §6's — one
/// name per state across both devices, taken from the Mac's <c>JackState</c> rather than
/// respelled. What outranks what lives in <see cref="ForServer"/>; the enum carries only the
/// word and nothing else, so a state and its name cannot drift apart.
/// </summary>
public enum JackState
{
    /// <summary>A child process is up.</summary>
    Live,

    /// <summary>Failed, or placarded by the user. Inoperative either way.</summary>
    Tripped,

    /// <summary>Holding tool-description changes until someone reads the diff.</summary>
    Held,

    /// <summary>The upstream supports authorisation and has not been authorised.</summary>
    NeedsSignIn,

    /// <summary>No child process, and nothing to decide.</summary>
    Dormant,
}

/// <summary>
/// The Signal Path's rules, as values rather than as a view — the port of the Mac's
/// <c>JackPresentation.swift</c>, for the reason that file gives: state correctness is the thing
/// that failed twice in the prototype, and a branch only a running app can exercise is a branch
/// that ships wrong. Everything here is a pure function of what the router reported, and nothing
/// derives a figure the router did not send.
/// </summary>
public static class JackPresentation
{
    /// <summary>The legend's word for this state, and what a screen reader is told when there is
    /// no per-server condition to say instead.</summary>
    public static string Word(this JackState state) => state switch
    {
        JackState.Live => "awake",
        JackState.Tripped => "tripped",
        JackState.Held => "held",
        JackState.NeedsSignIn => "needs sign-in",
        JackState.Dormant => "dormant",
        _ => "dormant",
    };

    /// <summary>
    /// Which jack a server shows.
    ///
    /// <para><b>Running is checked first, and that is the invariant</b> — the plug's meaning is
    /// *"lights the moment something calls the server and goes dark when the reaper closes the
    /// child"*. Lighting it for a server that is not running, or leaving it dark for one that
    /// is, is the only way this control can tell a lie. Attention therefore loses to running
    /// rather than the reverse.</para>
    ///
    /// <para><b>A disabled server outranks everything</b>, including running: a disabled server
    /// that happens to still have a child is being served to nobody, and the reaper is on its
    /// way to close it, so a lit plug would be telling the truth about the process and a lie
    /// about the product.</para>
    ///
    /// <para><b>An index error is not a sixth case, and that is a fact about the wire rather
    /// than a simplification.</b> A server with an <c>indexError</c> always arrives carrying a
    /// placard, so the tripped arm below catches it.</para>
    /// </summary>
    public static JackState ForServer(ServerRow server)
    {
        if (server.Disabled) return JackState.Dormant;
        if (server.IsRunning) return JackState.Live;
        if (server.Placard is not null) return JackState.Tripped;
        if (server.PendingChange is not null) return JackState.Held;
        if (server.Auth.Supported && !server.Auth.Authorized) return JackState.NeedsSignIn;
        return JackState.Dormant;
    }

    /// <summary>
    /// Seconds until the reaper would close this server, floored at zero.
    ///
    /// <c>idleMs</c> is a whole-router setting the envelope carries; <c>idleSec</c> is how long
    /// this server has already been idle. Both are the router's. A server past its horizon reads
    /// 0 rather than a negative number — the reaper runs on its own schedule, so "overdue" is a
    /// real moment and not an error.
    /// </summary>
    public static int ReapSeconds(ServerRow server, int idleMs) =>
        Math.Max(0, idleMs / 1000 - server.IdleSec);

    /// <summary>Seconds as the design of record writes them — <c>3:41</c>, and <c>221:00</c>
    /// rather than a rolled hour, because a horizon is minutes and an hours field would be a
    /// column of zeros on every row that has one.</summary>
    public static string Mmss(int seconds)
    {
        var s = Math.Max(0, seconds);
        return $"{s / 60}:{s % 60:D2}";
    }

    /// <summary>The row's state cell. The state's word is always present — on Windows the word
    /// is the only channel some users have (§12's 1.00:1 finding), so a live row never draws a
    /// bare clock under a success-coloured dot: "Awake · 3:41 left", not "3:41 left".</summary>
    public static string StateCell(ServerRow server, int? idleMs)
    {
        var condition = JackCondition.ForServer(server, idleMs);
        return condition.State switch
        {
            JackState.Live when condition.Word != "awake" => $"Awake · {condition.Word}",
            _ => Sentence(condition.Word),
        };
    }

    /// <summary>Relative time as the design of record writes it, from the router's ISO stamp.
    /// <c>never</c> is a state, not a formatting failure: a server nobody has called has no last
    /// call, and a dash would understate that.</summary>
    public static string RelativeLastCall(ServerRow server, DateTimeOffset now)
    {
        if (server.Usage.LastUsed is not { Length: > 0 } iso
            || !DateTimeOffset.TryParse(iso, out var used))
        {
            return "never";
        }

        var span = now - used;
        return span.TotalSeconds < 60 ? $"{(int)span.TotalSeconds} s ago"
             : span.TotalMinutes < 60 ? $"{(int)span.TotalMinutes} min ago"
             : span.TotalHours < 24 ? $"{(int)span.TotalHours} h ago"
             : $"{(int)span.TotalDays} d ago";
    }

    private static string Sentence(string word) =>
        char.IsAsciiLetterUpper(word[0]) || !char.IsAsciiLetter(word[0])
            ? word
            : char.ToUpperInvariant(word[0]) + word[1..];
}

/// <summary>
/// A jack's state and the two forms of the word under its name.
///
/// <para><b>Two strings</b> for the reason the Mac measured: where the width is tight, drop the
/// redundant word — the plug colour already says "awake" — rather than clipping the countdown.
/// <see cref="Word"/> is what the accessibility label always carries, so the condition in full
/// reaches a screen reader at every width; the contraction is a drawing decision and never a
/// state one.</para>
///
/// <para><b>The word's precedence is not the plug's, and the difference is load-bearing.</b> The
/// plug says whether a child is up, so nothing outranks running. The word is what a person
/// reads, and the reaper skips a warm server — a jack counting down to a reap the reaper will
/// never perform, beside a hub counting that server at rest, is a contradiction on one surface
/// about one server. So a warm live server reads "never reaped", and no input reaches a
/// countdown with <c>Warm</c> true.</para>
/// </summary>
public sealed record JackCondition(JackState State, string Word, string Contracted)
{
    /// <summary>The state whose contraction is the word itself — the common case, and the
    /// Swift model's `contracted ?? word`.</summary>
    public JackCondition(JackState state, string word) : this(state, word, word) { }

    public static JackCondition ForServer(ServerRow server, int? idleMs)
    {
        var state = JackPresentation.ForServer(server);

        // Ahead of the switch, because disabled is a fact about the whole server rather than a
        // refinement of one jack state: the plug is dormant and the word says which kind of
        // dormant — the distinction the design of record draws by giving the row "Disabled by
        // you" where its neighbour reads "Dormant".
        if (server.Disabled)
        {
            return new JackCondition(state, "disabled by you", "disabled");
        }

        switch (state)
        {
            case JackState.Live:
                if (server.Warm) return new JackCondition(state, "never reaped", "warm");
                if (idleMs is null) return new JackCondition(state, "awake", "awake");
                var clock = JackPresentation.Mmss(JackPresentation.ReapSeconds(server, idleMs.Value));
                return new JackCondition(state, $"{clock} left", clock);
            case JackState.Tripped:
                return new JackCondition(state, "tripped");
            case JackState.Held:
                var count = server.PendingChange?.Count ?? 0;
                var noun = count == 1 ? "change" : "changes";
                return new JackCondition(state, $"{count} held {noun}", $"{count} held");
            case JackState.NeedsSignIn:
                return new JackCondition(state, "needs sign-in");
            default:
                return new JackCondition(state, server.Warm ? "warm" : "dormant");
        }
    }
}
