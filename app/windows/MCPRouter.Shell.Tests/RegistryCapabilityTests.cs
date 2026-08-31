using MCPRouter.Shell.Model.Registry;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The install boundary's decisions: what the statement reads, that what is shown is what is
/// sent, that the display name never becomes the declared name, and that no force exists.
/// </summary>
public sealed class RegistryCapabilityTests
{
    private static RegistryEntry Entry(
        RegistryInstall? install = null,
        bool? installed = false,
        string name = "io.github/owner/thing",
        string displayName = "thing") => new()
    {
        Id = "row-1",
        Name = name,
        DisplayName = displayName,
        Description = "",
        Source = "official",
        Install = install,
        Installed = installed,
    };

    private static readonly RegistryInstall Stdio = new()
    {
        Type = "stdio",
        Command = "npx",
        Args = ["-y", "@owner/thing"],
    };

    private static readonly RegistryInstall Remote = new()
    {
        Type = "http",
        Url = "https://server.smithery.ai/@owner/thing/mcp",
        Requires = [new RegistryRequirement { Name = "Authorization", IsSecret = true }],
    };

    // ----------------------------------------------------------------- the statement

    [Fact]
    public void StdioStatementShowsTheArgvTokenByToken()
    {
        var statement = RegistryCapability.StatementFor(Entry(Stdio));
        Assert.False(statement.IsRemote);
        Assert.Equal(["npx", "-y", "@owner/thing"], statement.Argv);
        Assert.Contains("runs a program", statement.Headline, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void RemoteStatementNamesTheHostAndNeverThePath()
    {
        var statement = RegistryCapability.StatementFor(Entry(Remote));
        Assert.True(statement.IsRemote);
        Assert.Equal("server.smithery.ai", statement.Host);
        Assert.DoesNotContain("/mcp", statement.Headline);
    }

    [Fact]
    public void NoInstallBlockSaysSoRatherThanGuessing()
    {
        var statement = RegistryCapability.StatementFor(Entry(install: null));
        Assert.Equal(DiscoverCopy.StatementNoInstallHeadline, statement.Headline);
        Assert.Empty(statement.Argv);
    }

    [Fact]
    public void TheStatementIsDerivedNotDeclared()
    {
        // The derivation note must say so, or the statement reads as something the entry's author
        // declared and stands behind.
        Assert.Contains("install instructions", DiscoverCopy.StatementDerivationNote);
    }

    // ----------------------------------------------------------------- the action

    [Fact]
    public void AddedEntryDisablesTheActionWithItsDeclaredName()
    {
        var action = RegistryCapability.ActionFor(Entry(Stdio, installed: true, name: "io.github/owner/thing"));
        Assert.False(action.IsEnabled);
        Assert.Equal(RegistryCapability.ActionKind.Added, action.Kind);
        Assert.Contains("io.github/owner/thing", action.DisabledReason);
    }

    [Fact]
    public void NoInstallBlockDisablesWithTheReason()
    {
        var action = RegistryCapability.ActionFor(Entry(install: null));
        Assert.False(action.IsEnabled);
        Assert.Equal(DiscoverCopy.NoInstallDisabledReason, action.DisabledReason);
    }

    [Fact]
    public void InFlightActionDisablesSoASecondPressSendsNothing()
    {
        var action = RegistryCapability.ActionFor(Entry(Stdio), isInstalling: true);
        Assert.False(action.IsEnabled);
        Assert.Equal(RegistryCapability.ActionKind.Installing, action.Kind);
    }

    [Fact]
    public void RequirementsRevealThroughTheEllipsisThenCommit()
    {
        var before = RegistryCapability.ActionFor(Entry(Remote), requirementsRevealed: false);
        Assert.True(before.RevealsRequirements);
        Assert.EndsWith("…", before.Label);

        var after = RegistryCapability.ActionFor(Entry(Remote), requirementsRevealed: true, values: new Dictionary<string, string> { ["Authorization"] = "sk" });
        Assert.False(after.RevealsRequirements);
        Assert.True(after.IsEnabled);
        Assert.False(after.Label.EndsWith("…", StringComparison.Ordinal), "the committed label keeps the ellipsis");
    }

    [Fact]
    public void BlankRequiredValuesGateTheCommitAndNameTheField()
    {
        var action = RegistryCapability.ActionFor(
            Entry(Remote),
            requirementsRevealed: true,
            values: new Dictionary<string, string> { ["Authorization"] = "   " });
        Assert.False(action.IsEnabled);
        Assert.Equal(RegistryCapability.ActionKind.MissingRequirements, action.Kind);
        Assert.Contains("Authorization", action.DisabledReason);
        Assert.Contains("blank credential", action.DisabledReason);
    }

    // ----------------------------------------------------------------- the declaration

    [Fact]
    public void DeclarationSendsExactlyWhatWasShown()
    {
        // The invariant the whole board exists to uphold: the argv the statement draws is the
        // argv the declaration carries. A line separator in an arg drew as one thing and was
        // once sent as another; the same sanitiser on both sides closes it by construction.
        var hostile = new RegistryInstall
        {
            Type = "stdio",
            Command = "npx",
            Args = ["-y", "@owner/thing\u2028--allow-write"],
        };
        var statement = RegistryCapability.StatementFor(Entry(hostile));
        var declaration = RegistryCapability.DeclarationFor(Entry(hostile), new Dictionary<string, string>())!;

        Assert.Equal(statement.Argv, new[] { declaration.Command }.Concat(declaration.Args ?? new List<string>()));
        Assert.DoesNotContain("\u2028", declaration.Args![1]);
    }

    [Fact]
    public void DeclarationNamesWithTheEntryNameNotTheDisplayName()
    {
        // displayName is the field an index lets an author choose freely; name is the identity.
        var declaration = RegistryCapability.DeclarationFor(
            Entry(Stdio, name: "io.github/owner/thing", displayName: "Totally Trustworthy Tool"),
            new Dictionary<string, string>())!;
        Assert.Equal("io.github/owner/thing", declaration.Name);
    }

    [Fact]
    public void DeclarationCarriesOnlyValuesTheEntryAskedFor()
    {
        var declaration = RegistryCapability.DeclarationFor(
            Entry(Remote),
            new Dictionary<string, string>
            {
                ["Authorization"] = "bearer sk-123",
                ["Leftover"] = "from an earlier dialog",
            })!;
        Assert.NotNull(declaration.Headers);
        Assert.Equal("bearer sk-123", declaration.Headers["Authorization"]);
        Assert.False(declaration.Headers.ContainsKey("Leftover"));
    }

    [Fact]
    public void RemoteDeclarationSendsUrlAndType()
    {
        var declaration = RegistryCapability.DeclarationFor(Entry(Remote), new Dictionary<string, string>())!;
        Assert.Equal("https://server.smithery.ai/@owner/thing/mcp", declaration.Url);
        Assert.Equal("http", declaration.Type);
        Assert.Null(declaration.Command);
    }

    [Fact]
    public void NoInstallBlockBuildsNoDeclaration()
    {
        Assert.Null(RegistryCapability.DeclarationFor(Entry(install: null), new Dictionary<string, string>()));
    }

    [Fact]
    public void NewServerCarriesNoForce()
    {
        // force: true adopts an existing declaration — on this surface that means a registry row
        // could replace the command line of a server the user already trusts. The refusal is the
        // type's shape, not a convention at a call site.
        Assert.DoesNotContain(typeof(NewServer).GetProperties(), p => p.Name.Equals("Force", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void RequirementSummaryCountsAndSaysWhichAreSecret()
    {
        var allSecret = RegistryCapability.RequirementSummaryFor(Entry(Remote))!;
        Assert.Contains("1 value", allSecret);
        Assert.Contains("all of them secret", allSecret);

        var mixed = RegistryCapability.RequirementSummaryFor(Entry(new RegistryInstall
        {
            Type = "http",
            Url = "https://x.example",
            Requires =
            [
                new RegistryRequirement { Name = "Authorization", IsSecret = true },
                new RegistryRequirement { Name = "Profile" },
            ],
        }))!;
        Assert.Contains("2 values", mixed);
        Assert.Contains("1 of them secret", mixed);

        var none = RegistryCapability.RequirementSummaryFor(Entry(Stdio));
        Assert.Null(none);
    }
}
