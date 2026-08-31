using System.Globalization;

namespace MCPRouter.Shell.Model.Registry;

/// <summary>
/// Every decision the Discover board makes, with no UI framework in sight — the Windows port of
/// the Mac's <c>RegistryPresentation</c>. The four rules it documents there hold here unchanged:
/// provenance from evidence rather than the <c>source</c> label; a figure carries its unit and
/// its universe; an ordering is offered only where its signal is complete; and every third-party
/// string is sanitised before a view sees it.
/// </summary>
public static class RegistryPresentation
{
    // ----------------------------------------------------------------- provenance

    /// <summary>Which index actually supplied a row, established from evidence rather than from
    /// the <c>source</c> label. The wire's own fixture proves the label can lie: two Smithery
    /// rows colliding on a display name merge to <c>source: "both"</c> with nothing official
    /// behind them. The reliable evidence is the id prefix the merge stamps — Smithery-built
    /// rows carry <c>smithery:</c>, official-built rows carry the entry's own name.</summary>
    public const string SmitheryIdPrefix = "smithery:";

    public readonly record struct Provenance(bool IsOfficial, bool IsSmithery)
    {
        /// <summary>True only for a row an official entry actually underlies.</summary>
        public bool ShowsOfficialMark => IsOfficial;
    }

    public static Provenance ProvenanceFor(RegistryEntry entry)
    {
        var smitheryBased = entry.Id.StartsWith(SmitheryIdPrefix, StringComparison.Ordinal);
        var isSmithery = smitheryBased
            || entry.Source == "smithery"
            || entry.Source == "both";
        return new Provenance(IsOfficial: !smitheryBased, IsSmithery: isSmithery);
    }

    // ----------------------------------------------------------------- the header

    /// <summary>The subtitle under "Discover": names both indexes and counts what is on screen,
    /// not what matched — saying "47 servers" above a list of 30 would be the board contradicting
    /// itself.</summary>
    public static string Subtitle(RegistrySearchResponse response)
    {
        var shown = response.Results.Count;
        return $"Official registry · Smithery · {shown} {(shown == 1 ? "server" : "servers")}";
    }

    // ----------------------------------------------------------------- dates

    public enum DateMeaning
    {
        /// <summary>The official registry's stamp: when the registry entry was last updated.</summary>
        EntryUpdated,
        /// <summary>Smithery's stamp: when the entry was first published.</summary>
        FirstPublished,
    }

    public sealed record DateCell(string Text, DateMeaning Meaning);

    /// <summary>What a row's <c>updatedAt</c> actually means. One wire field, two meanings, and
    /// which one is settled by provenance rather than by the <c>source</c> label.</summary>
    public static DateMeaning MeaningOf(RegistryEntry entry) =>
        ProvenanceFor(entry).IsOfficial ? DateMeaning.EntryUpdated : DateMeaning.FirstPublished;

    /// <summary>The date as it reads on a row, or null when there is no parseable date — the cell
    /// is simply not drawn.</summary>
    public static DateCell? DateCellFor(RegistryEntry entry)
    {
        var when = RegistryText.TryParseTimestamp(entry.UpdatedAt);
        if (when is null) return null;
        var verb = MeaningOf(entry) == DateMeaning.EntryUpdated
            ? DiscoverCopy.DateUpdatedVerb
            : DiscoverCopy.DateAddedVerb;
        return new DateCell($"{verb} {RegistryText.Day(when.Value)}", MeaningOf(entry));
    }

    // ----------------------------------------------------------------- the figure

    public sealed record Figure(string Text, string Attribution);

    /// <summary>The one number a row carries, with its unit and where it came from. Never a bare
    /// integer: "2,984" and "9" on adjacent rows under one heading would read as one scale, and
    /// they are not on one scale.</summary>
    public static Figure? FigureFor(RegistryEntry entry)
    {
        if (entry.UseCount is { } uses)
        {
            return new Figure(
                DiscoverCopy.UnitSessions.Replace("{count}", RegistryText.Decimal(uses), StringComparison.Ordinal),
                "sessions started, as counted by Smithery");
        }

        if (entry.Stars is { } stars)
        {
            return new Figure(
                DiscoverCopy.UnitStars.Replace("{count}", RegistryText.Decimal(stars), StringComparison.Ordinal),
                "stars on GitHub");
        }

        // null rather than a zero: a rendered 0 claims the number was measured and found to be
        // none. For an official-only row there is no usage figure in existence to be zero.
        return null;
    }

    // ----------------------------------------------------------------- row facts

    public static string? ArchivedNoteFor(RegistryEntry entry) =>
        (entry.Archived ?? false) ? DiscoverCopy.RowArchived : null;

    public static string? ProvenanceSentenceFor(RegistryEntry entry)
    {
        var p = ProvenanceFor(entry);
        var verified = (entry.Verified ?? false) ? DiscoverCopy.ProvenanceVerifiedSuffix : "";
        return (p.IsOfficial, p.IsSmithery) switch
        {
            (true, true) => DiscoverCopy.ProvenanceBoth + verified,
            (true, false) => DiscoverCopy.ProvenanceOfficial,
            (false, true) => DiscoverCopy.ProvenanceSmithery + verified,
            (false, false) => null,
        };
    }

    // ----------------------------------------------------------------- warnings

    public enum WarningClass
    {
        OfficialDown,
        SmitheryDown,
        GitHubLimited,
    }

    /// <summary>The one place a router warning becomes board copy. Classification is by prefix on
    /// free text and that is fragile — the four producing strings live in <c>src/registry.ts</c>,
    /// and a reword there silently reclassifies here, which is why the unrecognised case carries
    /// the text verbatim and renders it rather than dropping it.</summary>
    public static (string Headline, string Body) Expand(string warning)
    {
        if (warning.StartsWith("official registry unreachable", StringComparison.OrdinalIgnoreCase))
        {
            return (DiscoverCopy.PartialOfficialDownHeadline, DiscoverCopy.PartialOfficialDownBody);
        }

        if (warning.StartsWith("Smithery unreachable", StringComparison.OrdinalIgnoreCase))
        {
            return (DiscoverCopy.PartialSmitheryDownHeadline, DiscoverCopy.PartialSmitheryDownBody);
        }

        if (warning.StartsWith("GitHub rate limit", StringComparison.OrdinalIgnoreCase)
            || warning.StartsWith("GitHub allows", StringComparison.OrdinalIgnoreCase))
        {
            return (DiscoverCopy.PartialGitHubLimitedHeadline, DiscoverCopy.PartialGitHubLimitedBody);
        }

        return (
            DiscoverCopy.PartialUnrecognisedHeadline,
            DiscoverCopy.PartialUnrecognisedBody.Replace("{warning}", warning, StringComparison.Ordinal));
    }

    // ----------------------------------------------------------------- the board's notes

    /// <summary>Everything the board admits about the result it is drawing. Each sentence appears
    /// only when its condition holds, except the trending refusal, which is always true, and the
    /// ranking disclosure, which is always true of the merged order the rows arrive in. An
    /// unrecognised warning is passed through <see cref="Expand" />, which renders it verbatim
    /// rather than dropping it.</summary>
    public static IReadOnlyList<string> FooterNotes(RegistrySearchResponse response)
    {
        var notes = new List<string>();

        var shown = response.Results.Count;
        if (response.Sources.Merged > shown)
        {
            notes.Add(DiscoverCopy.NoteShowingFirst.Replace("{count}", shown.ToString(CultureInfo.InvariantCulture), StringComparison.Ordinal));
        }

        notes.Add(DiscoverCopy.RankingNote);

        foreach (var warning in response.Warnings)
        {
            var (_, body) = Expand(warning);
            notes.Add(body);
        }

        notes.Add(DiscoverCopy.TrendingNote);
        return notes;
    }

    // ----------------------------------------------------------------- empties

    public sealed record EmptyMessage(string Headline, string Body, string? Action, bool ClearsSearch);

    public enum BandEmptyKind
    {
        None,
        MostUsed,
        RecentlyChangedWindowed,
        RecentlyChangedAnyTime,
    }

    /// <summary>Keyed on the query and the band state, because this board has three distinct
    /// empties and keying on either alone renders the wrong one — or none, leaving band headers
    /// over blank space.</summary>
    public static EmptyMessage? EmptyMessageFor(RegistrySearchResponse response, string query)
    {
        if (response.Results.Count > 0) return null;
        if (response.Warnings.Count > 0) return null; // partial draws instead — never "nothing found" for a degraded search

        var trimmed = query.Trim();
        if (trimmed.Length > 0)
        {
            return new EmptyMessage(
                DiscoverCopy.EmptyQueryHeadline.Replace("{query}", RegistryText.Sanitize(trimmed, cap: 60), StringComparison.Ordinal),
                DiscoverCopy.EmptyQueryBody,
                DiscoverCopy.ClearSearchAction,
                ClearsSearch: true);
        }

        return new EmptyMessage(
            DiscoverCopy.EmptyNoQueryHeadline,
            DiscoverCopy.EmptyNoQueryBody,
            DiscoverCopy.RetryAction,
            ClearsSearch: false);
    }

    /// <summary>The sentence for a band that is empty while the list as a whole is not — the
    /// common case, not an edge case.</summary>
    public static EmptyMessage? BandEmptyMessage(BandEmptyKind kind, int windowDays)
    {
        return kind switch
        {
            BandEmptyKind.MostUsed => new EmptyMessage(
                DiscoverCopy.BandEmptyMostUsedHeadline,
                DiscoverCopy.BandEmptyMostUsedBody,
                Action: null,
                ClearsSearch: false),
            BandEmptyKind.RecentlyChangedWindowed => new EmptyMessage(
                DiscoverCopy.BandEmptyRecentlyChangedWindowedHeadline
                    .Replace("{window}", windowDays.ToString(CultureInfo.InvariantCulture), StringComparison.Ordinal),
                DiscoverCopy.BandEmptyRecentlyChangedWindowedBody,
                DiscoverCopy.ShowAnyTimeAction,
                ClearsSearch: false),
            BandEmptyKind.RecentlyChangedAnyTime => new EmptyMessage(
                DiscoverCopy.BandEmptyRecentlyChangedAnyTimeHeadline,
                DiscoverCopy.BandEmptyRecentlyChangedAnyTimeBody,
                Action: null,
                ClearsSearch: false),
            _ => null,
        };
    }

    // ----------------------------------------------------------------- the state

    /// <summary>The list's states, as values a test can enumerate. Success is absent by
    /// construction: the list has no commit, so it has nothing to succeed at. Disabled and
    /// overflow are conditions of individual controls and rows, not of the pane.</summary>
    public enum ListStateKind
    {
        /// <summary>Both bands, populated.</summary>
        Populated,
        /// <summary>The search is in flight.</summary>
        Loading,
        /// <summary>Both indexes answered and neither listed anything, with no query narrowing it.</summary>
        EmptyNoQuery,
        /// <summary>A query matched nothing.</summary>
        EmptyQuery,
        /// <summary>Results arrived, or a degraded search returned nothing — something about the search was degraded.</summary>
        Partial,
        /// <summary>The search failed outright.</summary>
        Failed,
        /// <summary>The router is not running. Its own state, never a generic error.</summary>
        Offline,
    }

    /// <summary>The one place a load outcome becomes a surface state. Pure, so the mapping is
    /// testable without a client or a UI thread.</summary>
    public static ListStateKind Resolve(RegistrySearchResponse? response, string query, bool offline, bool failed)
    {
        if (offline) return ListStateKind.Offline;
        if (failed) return ListStateKind.Failed;
        if (response is null) return ListStateKind.Loading;
        if (response.Warnings.Count > 0) return ListStateKind.Partial;
        if (response.Results.Count == 0)
        {
            return query.Trim().Length == 0 ? ListStateKind.EmptyNoQuery : ListStateKind.EmptyQuery;
        }

        return ListStateKind.Populated;
    }
}
