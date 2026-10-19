using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Model.Cleanup;

/// <summary>
/// The Cleanup board's state, derived from the router's own <c>GET /servers</c> answer and from
/// nothing else.
///
/// <para><b>DEF-302. There is no sample data here any more, and that is the point.</b> This model
/// used to carry a <c>PopulateSampleData</c> that invented five rows — <c>pocketsmith</c>,
/// <c>ai-elements</c>, <c>graphify</c>, <c>media-gen-pro</c>, <c>acceptance-e2e</c> — and the board
/// offered to remove them. A destructive control over rows that are not the operator's is worse
/// than an inert one, because the inert one at least cannot act on the wrong thing. The only way
/// a row reaches this model now is <see cref="Adopt"/>, which takes a
/// <see cref="ServersEnvelope"/> the router answered; a board that never got an answer has no rows
/// and says why (<see cref="Fail"/>), rather than falling back to a list somebody typed.</para>
///
/// <para><b>What this model deliberately cannot see.</b> <see cref="CleanupKind.Skill"/> exists in
/// the row vocabulary and is never produced here. The router serves no skills route on this build
/// — spec-WIN6 §2.1, and the Skills board's own live reads answer 404 — so there is no reading
/// from which "this skill is unused" could be derived. Inventing one would be exactly the defect
/// above wearing a different noun. <see cref="SkillsNotEnumerated"/> is the sentence the board
/// draws instead.</para>
/// </summary>
public sealed class CleanupBoardModel
{
    private readonly List<CleanupRow> _neverCalledRows = new();
    private readonly List<CleanupRow> _quietRows = new();

    /// <summary>
    /// Which rows the operator has ticked, by id, kept ACROSS refreshes.
    /// </summary>
    /// <remarks>
    /// The board polls, so every refresh rebuilds both lists. Holding selection in the rows alone
    /// would clear the operator's ticks every few seconds and leave the Remove button permanently
    /// disabled — a control that cannot be pressed reads exactly like one that does nothing, which
    /// is the shape DEF-302 was filed against. A selection whose server the router has stopped
    /// listing is dropped on the next <see cref="Adopt"/>, so nothing stays ticked that could no
    /// longer be removed.
    /// </remarks>
    private readonly HashSet<string> _selected = new(StringComparer.Ordinal);

    /// <summary>The last router answer adopted, and the clock it was adopted at, so a change of
    /// window can re-derive the rows without waiting for the next poll.</summary>
    private (ServersEnvelope Envelope, DateTimeOffset At)? _reading;

    /// <summary>
    /// The window the quiet list is judged over, in days. Changed only through
    /// <see cref="SetQuietWindow"/>, so the list cannot be judged over a window the board never offers.
    /// </summary>
    public int SelectedDaysWindow { get; private set; } = 30;

    /// <summary>The windows the operator may pick between: the two the design names. The design
    /// captions the selector "Unused for 30 days", and its loading state counts "90 days of calls".</summary>
    public static IReadOnlyList<int> QuietWindowChoices { get; } = new[] { 30, 90 };

    /// <summary>True until the first answer or the first failure. Not a spinner: it is the state
    /// that keeps the board from drawing "nothing to propose" over a router it has not asked.</summary>
    public bool IsLoading { get; private set; } = true;

    public string? ErrorMessage { get; private set; }

    /// <summary>When the reading the rows were built from was taken, or null if none has been.</summary>
    public DateTimeOffset? AnsweredAt { get; private set; }

    public IReadOnlyList<CleanupRow> NeverCalledRows => _neverCalledRows;
    public IReadOnlyList<CleanupRow> QuietRows => _quietRows;

    public int TotalCandidates => _neverCalledRows.Count + _quietRows.Count;
    public int SelectedCount => _neverCalledRows.Count(r => r.IsSelected) + _quietRows.Count(r => r.IsSelected);

    public const string SkillsNotEnumerated =
        "Only MCP servers are listed. The router serves no skills route on this build, so whether "
        + "a skill is unused is something this board has no reading for and does not guess.";

    /// <summary>The caption on the window selector, and the sentence it states the window with.</summary>
    public static string WindowCaption(int days) => $"Unused for {days} days";

    /// <summary>The heading over the quiet list, which moves with the window it is judged over.</summary>
    public static string QuietHeading(int days) => $"Quiet for {days} days or more";

    /// <summary>
    /// Change the window the quiet list is judged over, and re-derive the rows from the last answer
    /// at once rather than at the next poll.
    /// </summary>
    /// <param name="days">One of <see cref="QuietWindowChoices"/>.</param>
    /// <exception cref="ArgumentOutOfRangeException">The window is not one the board offers.</exception>
    public void SetQuietWindow(int days)
    {
        if (!QuietWindowChoices.Contains(days))
        {
            throw new ArgumentOutOfRangeException(nameof(days), days,
                "The board offers only the windows the design names.");
        }

        SelectedDaysWindow = days;
        if (_reading is { } reading)
        {
            Adopt(reading.Envelope, reading.At);
        }
    }

    /// <summary>
    /// Take the router's answer and derive the candidates from it.
    /// </summary>
    /// <param name="envelope">The router's own <c>GET /servers</c> reading.</param>
    /// <param name="now">The clock, passed in so the quiet window is testable without waiting.</param>
    public void Adopt(ServersEnvelope envelope, DateTimeOffset now)
    {
        if (envelope is null) throw new ArgumentNullException(nameof(envelope));

        _neverCalledRows.Clear();
        _quietRows.Clear();
        IsLoading = false;
        ErrorMessage = null;
        AnsweredAt = now;
        _reading = (envelope, now);

        foreach (var server in envelope.Servers.OrderBy(s => s.Name, StringComparer.Ordinal))
        {
            var firstSeen = FormatDate(server.Usage.FirstSeen);
            var selected = _selected.Contains(server.Name);

            if (server.Usage.Calls == 0)
            {
                _neverCalledRows.Add(new CleanupRow(
                    Id: server.Name,
                    Name: server.Name,
                    Kind: CleanupKind.Server,
                    ToolCount: server.Tools,
                    InstalledDate: firstSeen,
                    WhyItMightStillMatter: CleanupPresentation.NeverCalled,
                    SecondaryActionLabel: string.Empty,
                    IsSelected: selected));
                continue;
            }

            var quietDays = DaysSince(server.Usage.LastUsed, now);
            if (quietDays is int days && days >= SelectedDaysWindow)
            {
                _quietRows.Add(new CleanupRow(
                    Id: server.Name,
                    Name: server.Name,
                    Kind: CleanupKind.Server,
                    ToolCount: server.Tools,
                    InstalledDate: firstSeen,
                    WhyItMightStillMatter: QuietFor(days, server.Usage.Calls),
                    SecondaryActionLabel: string.Empty,
                    IsSelected: selected));
            }
        }

        // A tick is kept only while its row is on the board. A server the router stopped listing,
        // or one that is no longer a candidate under the current window, cannot be acted on from
        // here, so its tick is dropped rather than waiting to re-arm itself.
        _selected.IntersectWith(_neverCalledRows.Select(r => r.Id).Concat(_quietRows.Select(r => r.Id)));
    }

    /// <summary>The router did not answer. The rows already on screen are dropped rather than
    /// kept: this board's one action is destructive, and acting on a list whose provenance has
    /// lapsed is the thing to avoid, not the refresh.</summary>
    public void Fail(string message)
    {
        _neverCalledRows.Clear();
        _quietRows.Clear();
        IsLoading = false;
        ErrorMessage = message;
        AnsweredAt = null;
        _reading = null;
    }

    public void SetSelection(string id, bool isSelected)
    {
        if (isSelected) _selected.Add(id); else _selected.Remove(id);

        for (int i = 0; i < _neverCalledRows.Count; i++)
        {
            if (_neverCalledRows[i].Id == id)
            {
                _neverCalledRows[i] = _neverCalledRows[i] with { IsSelected = isSelected };
                return;
            }
        }
        for (int i = 0; i < _quietRows.Count; i++)
        {
            if (_quietRows[i].Id == id)
            {
                _quietRows[i] = _quietRows[i] with { IsSelected = isSelected };
                return;
            }
        }
    }

    public void MarkAllAsKeep()
    {
        _selected.Clear();
        for (int i = 0; i < _neverCalledRows.Count; i++)
        {
            _neverCalledRows[i] = _neverCalledRows[i] with { IsSelected = false };
        }
        for (int i = 0; i < _quietRows.Count; i++)
        {
            _quietRows[i] = _quietRows[i] with { IsSelected = false };
        }
    }

    public List<CleanupRow> GetSelectedRows()
    {
        var list = _neverCalledRows.Where(r => r.IsSelected).ToList();
        list.AddRange(_quietRows.Where(r => r.IsSelected));
        return list;
    }

    // ------------------------------------------------------------------ derivations

    /// <summary>Whole days between the router's <c>lastUsed</c> stamp and now, or null when the
    /// router sent no stamp or one this client cannot read. Null is NOT zero and not "long ago":
    /// a server whose last use is unknown is left out of the quiet list entirely, because the
    /// board would otherwise propose removing something on the strength of a field it failed to
    /// parse.</summary>
    public static int? DaysSince(string? stamp, DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(stamp)) return null;
        if (!DateTimeOffset.TryParse(stamp, CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var used))
        {
            return null;
        }
        var days = (int)Math.Floor((now - used).TotalDays);
        return days < 0 ? 0 : days;
    }

    public static string QuietFor(int days, int calls)
    {
        var callWord = calls == 1 ? "call" : "calls";
        return $"{calls} {callWord} recorded, and nothing in the last {days} days.";
    }

    public static string FormatDate(string? stamp)
    {
        if (string.IsNullOrWhiteSpace(stamp)) return "Unknown";
        return DateTimeOffset.TryParse(stamp, CultureInfo.InvariantCulture,
                   DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var when)
            ? when.ToLocalTime().ToString("d MMM yyyy", CultureInfo.CurrentCulture)
            : "Unknown";
    }
}
