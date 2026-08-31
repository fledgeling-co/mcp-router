namespace MCPRouter.Shell.Model.Registry;

/// <summary>
/// What an entry will actually do, read off its install block — and the decision about whether it
/// may be added at all. The Windows port of the Mac's <c>RegistryCapability</c>, guarantees
/// included: the statement is a reading of the install block (no registry format carries a
/// capability manifest), the argv the user reads is the argv the declaration sends, the
/// declaration's name is the entry's <c>name</c> rather than the author-chosen display name, and
/// there is no <c>force</c> anywhere in the shape of <see cref="NewServer" />.
/// </summary>
public static class RegistryCapability
{
    public sealed record Statement(string Headline, string Body, IReadOnlyList<string> Argv, string? Host, bool IsRemote);

    public static Statement StatementFor(RegistryEntry entry)
    {
        var install = entry.Install;
        if (install is null)
        {
            return new Statement(
                DiscoverCopy.StatementNoInstallHeadline,
                DiscoverCopy.StatementNoInstallBody,
                Array.Empty<string>(),
                Host: null,
                IsRemote: false);
        }

        if (install.Type == "stdio")
        {
            return new Statement(
                DiscoverCopy.StatementStdioHeadline,
                DiscoverCopy.StatementStdioBody,
                ArgvTokens(install),
                Host: null,
                IsRemote: false);
        }

        // http and sse: the authority alone, never the path, which is where a misleading string
        // would hide.
        var host = RegistryText.HostOf(install.Url);
        var headline = host is null
            ? DiscoverCopy.StatementRemoteNoHostHeadline
            : DiscoverCopy.StatementRemoteHeadline.Replace("{host}", host, StringComparison.Ordinal);
        return new Statement(headline, DiscoverCopy.StatementRemoteBody, Array.Empty<string>(), host, IsRemote: true);
    }

    /// <summary><c>command</c> followed by each argument, each sanitised, empties dropped. Kept
    /// as a list rather than a joined line on purpose: a joined line reads as a shell command,
    /// and an entry whose args contain spaces or quotes would render as a different command from
    /// the one that will run.</summary>
    public static IReadOnlyList<string> ArgvTokens(RegistryInstall install)
    {
        var tokens = new List<string>();
        if (install.Command is { } command) tokens.Add(RegistryText.Sanitize(command));
        if (install.Args is { } args)
        {
            tokens.AddRange(args.Select(a => RegistryText.Sanitize(a)));
        }

        return tokens.Where(t => t.Length > 0).ToList();
    }

    // ----------------------------------------------------------------- the action

    public enum ActionKind
    {
        /// <summary>The commit is available, with no requirement fields to reveal.</summary>
        Add,
        /// <summary>Requirement fields must be shown first; the … promises a further view.</summary>
        AddRevealsRequirements,
        /// <summary>In flight; disabled so a second press cannot send a second declaration.</summary>
        Installing,
        /// <summary>Already declared on this router.</summary>
        Added,
        /// <summary>Neither index says how to run it.</summary>
        NoInstall,
        /// <summary>Fields are on screen and a required value is still blank.</summary>
        MissingRequirements,
    }

    public sealed record AddAction(ActionKind Kind, string Label, bool IsEnabled, string? DisabledReason, IReadOnlyList<string> MissingNames)
    {
        public bool RevealsRequirements => Kind == ActionKind.AddRevealsRequirements;
    }

    /// <summary>The one place the Add action's state is decided. The precedence order matters:
    /// Added and NoInstall refuse the commit outright; MissingRequirements gates it until every
    /// field the entry asked for has a value, because a secret with no value must not be sent as
    /// an empty string — the router would store a blank credential.</summary>
    public static AddAction ActionFor(
        RegistryEntry entry,
        bool isInstalling = false,
        bool requirementsRevealed = false,
        IReadOnlyDictionary<string, string>? values = null)
    {
        values ??= new Dictionary<string, string>();
        var name = RegistryText.Sanitize(entry.DisplayName, cap: 40);

        if (entry.Installed ?? false)
        {
            var declared = RegistryText.Sanitize(entry.Name, cap: 60);
            return new AddAction(
                ActionKind.Added,
                DiscoverCopy.AddActionAdded,
                IsEnabled: false,
                DiscoverCopy.AddedDisabledReasonFormat.Replace("{name}", declared, StringComparison.Ordinal),
                Array.Empty<string>());
        }

        if (entry.Install is null)
        {
            return new AddAction(
                ActionKind.NoInstall,
                DiscoverCopy.AddActionFormat.Replace("{name}", name, StringComparison.Ordinal),
                IsEnabled: false,
                DiscoverCopy.NoInstallDisabledReason,
                Array.Empty<string>());
        }

        if (isInstalling)
        {
            return new AddAction(
                ActionKind.Installing,
                DiscoverCopy.AddActionInstalling,
                IsEnabled: false,
                DisabledReason: null,
                Array.Empty<string>());
        }

        var requirements = entry.Install.Requires ?? new List<RegistryRequirement>();

        // Once the fields are on screen the button commits, so it loses its ellipsis — the
        // ellipsis promised a further view and the further view has arrived.
        var reveals = requirements.Count > 0 && !requirementsRevealed;
        if (!reveals && requirements.Count > 0)
        {
            var missing = MissingRequirementsFor(entry, values);
            if (missing.Count > 0)
            {
                var names = string.Join(", ", missing.Select(r => RegistryText.Sanitize(r.Name, cap: 40)));
                return new AddAction(
                    ActionKind.MissingRequirements,
                    DiscoverCopy.AddActionFormat.Replace("{name}", name, StringComparison.Ordinal),
                    IsEnabled: false,
                    missing.Count == 1
                        ? DiscoverCopy.MissingOneReasonFormat.Replace("{names}", names, StringComparison.Ordinal)
                        : DiscoverCopy.MissingManyReasonFormat.Replace("{names}", names, StringComparison.Ordinal),
                    missing.Select(r => r.Name).ToList());
            }
        }

        return new AddAction(
            reveals ? ActionKind.AddRevealsRequirements : ActionKind.Add,
            (reveals ? DiscoverCopy.AddActionRevealsFormat : DiscoverCopy.AddActionFormat)
                .Replace("{name}", name, StringComparison.Ordinal),
            IsEnabled: true,
            DisabledReason: null,
            Array.Empty<string>());
    }

    /// <summary>Every requirement the entry asked for that has no value yet, looked up under the
    /// sanitised name — the key the field was drawn with and the key the declaration reads with.</summary>
    public static IReadOnlyList<RegistryRequirement> MissingRequirementsFor(
        RegistryEntry entry,
        IReadOnlyDictionary<string, string> values)
    {
        if (entry.Install?.Requires is not { } requirements) return Array.Empty<RegistryRequirement>();
        return requirements
            .Where(r =>
            {
                var key = RegistryText.Sanitize(r.Name);
                return !values.TryGetValue(key, out var value)
                    || string.IsNullOrWhiteSpace(value);
            })
            .ToList();
    }

    // ----------------------------------------------------------------- the declaration

    /// <summary>The <see cref="NewServer" /> an entry becomes, with the values the user supplied.
    /// Returns null when there is no install block, so a caller cannot construct a declaration
    /// for an entry that never said how to run.
    ///
    /// What is sent is exactly what was shown: the same sanitiser runs on the argv the statement
    /// draws and on the command, args and url the declaration carries, so an entry cannot draw
    /// one command and send another. Only the values this entry actually asked for are carried —
    /// a leftover value from an earlier dialog must not reach the router.</summary>
    public static NewServer? DeclarationFor(RegistryEntry entry, IReadOnlyDictionary<string, string> values)
    {
        var install = entry.Install;
        if (install is null) return null;

        var name = RegistryText.Sanitize(entry.Name);
        if (name.Length == 0) return null;

        var asked = new HashSet<string>(
            (install.Requires ?? new List<RegistryRequirement>()).Select(r => RegistryText.Sanitize(r.Name)),
            StringComparer.Ordinal);
        var supplied = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, value) in values)
        {
            var clean = RegistryText.Sanitize(key);
            if (!asked.Contains(clean) || value.Length == 0) continue;
            supplied[clean] = value;
        }

        if (install.Type == "stdio")
        {
            var command = RegistryText.Sanitize(install.Command ?? "");
            if (command.Length == 0) return null;
            var args = install.Args is null ? null : install.Args.Select(a => RegistryText.Sanitize(a)).ToList();
            return new NewServer
            {
                Name = name,
                Command = command,
                Args = args,
                Env = supplied.Count == 0 ? null : supplied,
            };
        }

        var url = RegistryText.Sanitize(install.Url ?? "");
        if (url.Length == 0) return null;
        return new NewServer
        {
            Name = name,
            Type = install.Type,
            Url = url,
            Headers = supplied.Count == 0 ? null : supplied,
        };
    }

    /// <summary>The summary line above the requirement fields, or null when the entry asks for
    /// nothing.</summary>
    public static string? RequirementSummaryFor(RegistryEntry entry)
    {
        var requirements = entry.Install?.Requires;
        if (requirements is null || requirements.Count == 0) return null;

        var secretCount = requirements.Count(r => r.IsSecret ?? false);
        var noun = requirements.Count == 1 ? DiscoverCopy.RequirementValueSingular : DiscoverCopy.RequirementValuePlural;
        var count = requirements.Count.ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (secretCount == 0)
        {
            return DiscoverCopy.RequirementSummaryNoSecrets
                .Replace("{count}", count, StringComparison.Ordinal)
                .Replace("{noun}", noun, StringComparison.Ordinal);
        }

        return secretCount == requirements.Count
            ? DiscoverCopy.RequirementSummaryAllSecret
                .Replace("{count}", count, StringComparison.Ordinal)
                .Replace("{noun}", noun, StringComparison.Ordinal)
            : DiscoverCopy.RequirementSummarySomeSecret
                .Replace("{count}", count, StringComparison.Ordinal)
                .Replace("{noun}", noun, StringComparison.Ordinal)
                .Replace("{secrets}", secretCount.ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal);
    }
}
