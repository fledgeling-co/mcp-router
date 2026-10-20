using MCPRouter.Shell.Model.Skills;

namespace MCPRouter.Shell.Model;

/// <summary>
/// Every decision the Skills board makes, with no UI framework in sight - the Windows port of the
/// Mac's <c>SkillPresentation.swift</c> and <c>SkillCopy.swift</c>, carrying the same decisions
/// rather than re-deriving them.
///
/// The rule this file exists to enforce is DESIGN.md §6's: the router does not observe a skill
/// run, so nothing here computes one; and §6's one-name-per-state rule means the sentences below
/// are the Mac's, verbatim, except where they name the machine - two recorded deviations, both
/// "this PC" for "this Mac" (spec-WIN6 §3.7).
/// </summary>
public static class SkillPresentation
{
    /// <summary>
    /// The Skills header action. What the design of record puts in that slot and what the menu
    /// has always said, stated once so the button and its menu twin cannot drift apart (the
    /// Mac's DEF-012).
    /// </summary>
    public const string MarketplacesAction = "Add marketplace…";

    /// <summary>
    /// Why every write control on this board is disabled. M4's sentence, carried across: these
    /// writes land in files the client applications hold open, and a read-modify-write against a
    /// shape this app did not recognise would rewrite the user's whole plugin list and look
    /// exactly like "nothing is installed". §5 asks a control that does not apply to dim in
    /// place with a discoverable reason rather than disappear.
    /// </summary>
    public const string WritesNotYetAvailable =
        "Changing what is installed arrives with the item that can do it safely - these files "
        + "are open in your other apps while this one is running.";

    public const string EmptyTitle = "No skills installed yet";

    public const string EmptyDetail =
        "A skill is a markdown file that teaches an agent how you want a job done. Follow a "
        + "marketplace and the skills it supplies appear here, across every client that supports "
        + "them.";

    /// <summary>The empty state's second action, reworded for the machine it draws on (spec-WIN6 §3.7).</summary>
    public const string ScanLocalAction = "Find skills already on this PC";

    /// <summary>
    /// Stated once on the populated board, as a property of the product rather than of any row.
    /// This sentence is why there is no runs column and no eval column.
    /// </summary>
    public const string ObservationFooter =
        "Run counts and evaluation results are not shown. A skill is loaded into an agent's "
        + "context by the client and never reaches the router, so the router does not see it "
        + "run. Checks reports what the router observed for itself, and no model-graded "
        + "evaluation exists in this product.";

    /// <summary>
    /// One quiet sentence naming how a held version's capability list was derived, so it is not
    /// mistaken for a manifest the plugin author wrote.
    /// </summary>
    public const string CapabilityDerivation =
        "As reported by the router, from the skill's own text rather than from anything its "
        + "author declared. No skill format carries a capability manifest, so this is a reading "
        + "and can be incomplete.";

    // ------------------------------------------------------------------ held-version writes (stub)

    public const string PromoteUnavailable = "";
    public const string UpdatesHeading = "";
    public const string UpdatesNone = "";

    public static string Kept(string version) => throw new NotImplementedException();

    public static string Promoted(string name, string version) => throw new NotImplementedException();

    public static string Undone(string name, string? version) => throw new NotImplementedException();

    public static string PromotionCanBeUndone(string plugin) => throw new NotImplementedException();

    public static string Offered(string available, string installed) => throw new NotImplementedException();

    public static IReadOnlyList<ExtensionUpdateEntry> UpdateOffers(
        IReadOnlyList<Skill> skills, IReadOnlyList<ExtensionUpdateEntry> stored) => throw new NotImplementedException();

    // ------------------------------------------------------------------ the header

    /// <summary>
    /// The subtitle under "Skills". Returns an empty string while loading: a count that is not
    /// yet known is not a count, and "Loading…" in the place a number belongs is a worse
    /// answer than nothing there.
    /// </summary>
    public static string Subtitle(IReadOnlyList<Skill> skills)
    {
        var marketplaces = skills
            .Select(s => s.Source.AsPlugin?.Marketplace)
            .Where(m => m is not null)
            .Distinct()
            .Count();
        var skillNoun = skills.Count == 1 ? "skill" : "skills";
        var marketNoun = marketplaces == 1 ? "marketplace" : "marketplaces";
        var parts = new List<string> { $"{skills.Count} {skillNoun} from {marketplaces} {marketNoun}" };

        // Omitted entirely at zero rather than rendered "0 held", which reads as a warning that
        // resolved rather than a condition that never applied.
        var held = skills.Count(s => s.Held?.WantsMore ?? false);
        if (held > 0) parts.Add($"{held} held for review");

        return string.Join(" · ", parts);
    }

    // ------------------------------------------------------------------ the version cell

    public sealed record VersionCell(string Text, bool IsInstrument, bool IsHeld);

    /// <summary>
    /// How a version reads, and which face it is set in. <see cref="VersionCell.IsInstrument"/>
    /// is part of the answer rather than a styling choice made at the call site, because it is
    /// the difference between a reading and a statement: "2.2.0" is a value the router read off a
    /// file; "unversioned" is the app saying there was no value to read.
    /// </summary>
    public static VersionCell Version(Skill skill)
    {
        if (skill.Source.AsPlugin is not { } origin)
        {
            // A hand-placed skill has no version anywhere on disk: SKILL.md frontmatter carries
            // name and description and nothing else. Printing "1.0.0" here would be invented.
            return new VersionCell("unversioned", IsInstrument: false, IsHeld: false);
        }

        if (skill.Held is { } held && held.WantsMore)
        {
            return new VersionCell(
                $"{origin.PluginVersion} → {held.PluginVersion}",
                IsInstrument: true,
                IsHeld: true);
        }

        return new VersionCell(origin.PluginVersion, IsInstrument: true, IsHeld: false);
    }

    /// <summary>
    /// The line under a skill's name. Names the plugin as well as the marketplace when the plugin
    /// supplies more than one skill, because the version on this row belongs to that plugin and
    /// is shared with its siblings.
    /// </summary>
    public static string SourceLine(Skill skill) =>
        skill.Source.AsPlugin switch
        {
            null => "local - not from a marketplace",
            { SiblingSkillCount: > 1 } origin => $"{origin.Plugin} · {origin.Marketplace}",
            { } origin => origin.Marketplace,
        };

    /// <summary>The provenance warning that replaces the source line when a marketplace has moved.</summary>
    public static string? ProvenanceLine(Skill skill) =>
        skill.Provenance is { } provenance
            ? $"Owner changed - was {provenance.FirstSeenSource}"
            : null;

    // ------------------------------------------------------------------ slots

    public enum SlotState
    {
        On,
        Off,
        /// <summary>That client's directory could not be read, so whether the skill is there is unknown.</summary>
        Unknown,
    }

    public static SlotState Slot(Skill skill, SkillClient client) =>
        skill.Presence.TryGetValue(client.Id, out var presence)
        ? presence switch
        {
            SkillPresence.Present => SlotState.On,
            SkillPresence.Unreadable => SlotState.Unknown,
            _ => SlotState.Off,
        }
        : SlotState.Off;

    /// <summary>
    /// The short label on a slot. Two letters, from the client the router named - never a
    /// hardcoded list, so a client the router stops reporting stops having a slot. The Mac's
    /// shipped mapping, which postdates the mock's legend (CR for Cursor, not CU).
    /// </summary>
    public static string SlotLabel(SkillClient client) =>
        client.Id switch
        {
            "claudeCode" => "CC",
            "codex" => "CX",
            "cursor" => "CR",
            "opencode" => "OC",
            _ => client.DisplayName.Length >= 2
                ? client.DisplayName[..2].ToUpperInvariant()
                : client.DisplayName.ToUpperInvariant(),
        };

    /// <summary>The automation name a slot chip carries, so the plane reads the state and not a letter.</summary>
    public static string SlotAutomationName(Skill skill, SkillClient client) =>
        Slot(skill, client) switch
        {
            SlotState.On => $"{client.DisplayName}: installed",
            SlotState.Off => $"{client.DisplayName}: not installed",
            SlotState.Unknown => $"{client.DisplayName}: could not be read, so this is unknown",
            _ => client.DisplayName,
        };

    // ------------------------------------------------------------------ the inspector's client sentences

    /// <summary>
    /// Which clients hold this skill, which supported ones do not, and which have no mechanism.
    /// All are accounted for: without the last sentence, the unsupported clients are missing from
    /// the board with no explanation anywhere.
    /// </summary>
    public static IReadOnlyList<string> ClientSentences(Skill skill, SkillsResponse response)
    {
        var lines = new List<string>();
        var supported = response.SlotClients;
        var present = supported.Where(c => skill.Presence.GetValueOrDefault(c.Id) == SkillPresence.Present).ToList();
        var unknown = supported.Where(c => skill.Presence.GetValueOrDefault(c.Id) == SkillPresence.Unreadable).ToList();
        var absent = supported.Where(c => skill.Presence.GetValueOrDefault(c.Id) == SkillPresence.Absent).ToList();

        lines.Add(present.Count == 0
            ? "Not in any client that supports skills"
            : string.Join(" · ", present.Select(c => c.DisplayName)));

        if (absent.Count > 0) lines.Add($"Not in {List(absent.Select(c => c.DisplayName).ToList())}");
        if (unknown.Count > 0)
        {
            lines.Add($"{List(unknown.Select(c => c.DisplayName).ToList())} could not be read, so this is unknown");
        }

        var unsupported = response.UnsupportedClients.Select(c => c.DisplayName).ToList();
        if (unsupported.Count > 0)
        {
            lines.Add($"{List(unsupported)} {(unsupported.Count == 1 ? "has" : "have")} no skills mechanism");
        }

        return lines;
    }

    /// <summary>"a", "a and b", "a, b and c" - the Mac's list form.</summary>
    public static string List(IReadOnlyList<string> items) =>
        items.Count switch
        {
            0 => "",
            1 => items[0],
            2 => $"{items[0]} and {items[1]}",
            _ => $"{string.Join(", ", items.Take(items.Count - 1))} and {items[^1]}",
        };

    // ------------------------------------------------------------------ partial

    /// <summary>
    /// What the partial banner says when a client's directory could not be read. Names the
    /// client, the consequence for what is on screen, the path, and the reason - DESIGN.md §5's
    /// "say what arrived and what did not, with the reason", in that order.
    /// </summary>
    public static string? PartialNote(SkillsResponse response)
    {
        var broken = response.ClientList.Where(c => c.Status == SkillClientStatus.Unreadable).ToList();
        if (broken.Count == 0) return null;

        var names = List(broken.Select(c => c.DisplayName).ToList());
        var detail = string.Join(
            "; ",
            broken.Select(c => $"{c.Root ?? c.DisplayName} - {c.Reason ?? "could not be read"}"));
        return $"{names} could not be read, so anything installed only there is missing from this "
               + $"list and the slot column understates for every row. {detail}.";
    }

    // ------------------------------------------------------------------ the held-version review

    /// <summary>
    /// The held banner's title - the design of record's own line ("design-review 2.4.0 is held
    /// for review"), which the brief quotes verbatim and which this banner must say.
    /// </summary>
    public static string HeldBannerTitle(Skill skill) =>
        skill.Held is not { } held || !held.WantsMore
            ? ""
            : $"{skill.Name} {held.PluginVersion} is held for review";

    /// <summary>
    /// The held banner's body: what the new version asks for, verbatim from the router's
    /// capability reading, and the guarantee spelled out - downloaded, not live. A held update
    /// never goes live until the user acts; this sentence is where the board says so.
    /// </summary>
    public static string HeldBannerBody(Skill skill) =>
        skill.Held is not { } held || !held.WantsMore
            ? ""
            : $"The new version asks for {List(held.AddedCapabilities)} the installed one never "
              + "had. It is downloaded, not live.";

    public static string HeldTitle(Skill skill)
    {
        if (skill.Held is not { } held || skill.Source.AsPlugin is not { } origin) return "";
        return $"{origin.Plugin} {held.PluginVersion} wants more than {origin.PluginVersion}";
    }

    public static string HeldBody(Skill skill)
    {
        if (skill.Held is not { } held) return "";
        var affected = held.AffectedSkillCount;
        var scope = affected > 1
            ? $" Promoting it moves all {affected} skills this plugin supplies."
            : "";
        return "It was fetched and is being kept aside rather than installed - every client is "
               + $"still running {skill.Source.AsPlugin?.PluginVersion ?? "the installed version"}.{scope}";
    }

    /// <summary>What the updates tab's "What changed" cell says, from the capability delta alone.</summary>
    public static string WhatChanged(Skill skill) =>
        skill.Held is not { } held
            ? ""
            : held.WantsMore
                ? $"Wants {List(held.AddedCapabilities)}"
                : "No capability change";

    /// <summary>
    /// The updates tab's disposition, which is the trust rule rendered: a version that asks for
    /// more waits for a human, and one that asks for the same promotes on its own.
    /// </summary>
    public static string Disposition(Skill skill)
    {
        if (skill.Held is not { } held) return "";
        return held.WantsMore ? "Held for review" : "Promotes on its own";
    }

    /// <summary>
    /// The set "Update all" acts on: rows where a newer version exists <b>and asks for nothing
    /// more</b>. A held-for-review row is never in this set - the brief's security clause, and
    /// the one place this board's arithmetic deliberately diverges from the mock's drawing
    /// (spec-WIN6 §3.1).
    /// </summary>
    public static IReadOnlyList<Skill> Updatable(IReadOnlyList<Skill> skills) =>
        skills.Where(s => s.Held is { } held && !held.WantsMore).ToList();

    /// <summary>The rows the Updates tab lists: every skill with a newer version fetched at all.</summary>
    public static IReadOnlyList<Skill> Updated(IReadOnlyList<Skill> skills) =>
        skills.Where(s => s.Held is not null).ToList();

    // ------------------------------------------------------------------ auto-update

    /// <summary>
    /// What inspector item 7 shows for one skill - the decision, not the drawing. Three outcomes,
    /// and the distinction between the last two is the whole reason this is a type: a skill whose
    /// marketplace record did not load is <b>not</b> a skill whose auto-update is off. Collapsing
    /// them would assert a setting nobody read.
    /// </summary>
    public abstract record AutoUpdateItem
    {
        public sealed record NotApplicable : AutoUpdateItem;

        /// <summary>There is a marketplace, but its record is not in hand.</summary>
        public sealed record Unread(string Line) : AutoUpdateItem;

        /// <summary>
        /// The setting, as read off the record, with the reason its control cannot be moved and
        /// the word its table cell shows. The cell is carried on the item because a local
        /// directory's setting is real in the inspector but <b>n/a</b> in the table - there is
        /// nothing to auto-update - and the distinction is a decision, not a re-derivation.
        /// </summary>
        public sealed record Setting(string Line, string Reason, bool IsOn, string Cell) : AutoUpdateItem;
    }

    public const string AutoUpdateUnread =
        "Not shown - the marketplace list didn't load, and the setting lives on the marketplace.";

    public static AutoUpdateItem AutoUpdate(Skill skill, IReadOnlyList<Marketplace> marketplaces)
    {
        if (skill.Source.AsPlugin is not { } origin) return new AutoUpdateItem.NotApplicable();
        var marketplace = marketplaces.FirstOrDefault(m => m.Name == origin.Marketplace);
        if (marketplace is null) return new AutoUpdateItem.Unread(AutoUpdateUnread);
        var cell = marketplace.Source.IsLocalDirectory
            ? "n/a"
            : marketplace.AutoUpdate ? "On" : "Off";
        return new AutoUpdateItem.Setting(
            AutoUpdateLine(marketplace),
            AutoUpdateReason(marketplace),
            marketplace.AutoUpdate,
            cell);
    }

    /// <summary>The table cell's short word for the same setting - with the same fourth answer.</summary>
    public static string AutoUpdateCell(Skill skill, IReadOnlyList<Marketplace> marketplaces) =>
        AutoUpdate(skill, marketplaces) switch
        {
            AutoUpdateItem.Setting setting => setting.Cell,
            AutoUpdateItem.NotApplicable => "n/a",
            AutoUpdateItem.Unread => "Not shown",
            _ => "",
        };

    public static string AutoUpdateReason(Marketplace marketplace) =>
        marketplace.Source.IsLocalDirectory
            ? "A marketplace on this machine updates when you change it - there is nothing to fetch."
            : WritesNotYetAvailable;

    public static string AutoUpdateLine(Marketplace marketplace) =>
        marketplace.Source.IsLocalDirectory
            ? "Local directory"
            : marketplace.AutoUpdate ? "Auto-update on" : "Auto-update off";

    public static string RemoveReason(Marketplace marketplace)
    {
        if (marketplace.SuppliedSkillCount > 0)
        {
            var n = marketplace.SuppliedSkillCount;
            var noun = n == 1 ? "skill comes" : "skills come";
            return $"{n} installed {noun} from this marketplace. Remove them first.";
        }
        return WritesNotYetAvailable;
    }

    /// <summary>What a marketplace row says it supplies.</summary>
    public static string SupplyLine(Marketplace marketplace)
    {
        if (marketplace.SuppliedSkillCount == 0) return "Supplies nothing";
        var skills = marketplace.SuppliedSkillCount;
        var plugins = marketplace.InstalledPluginCount;
        // A skill count with no plugin count behind it would read "22 skills from 0 plugins",
        // which is a sentence about the router's bookkeeping rather than about the marketplace.
        return plugins switch
        {
            0 => $"{skills} {(skills == 1 ? "skill" : "skills")}",
            _ => $"{skills} {(skills == 1 ? "skill" : "skills")} from {plugins} {(plugins == 1 ? "plugin" : "plugins")}",
        };
    }
}
