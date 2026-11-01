namespace MCPRouter.Shell.Tests;

/// <summary>
/// The held-version replies, as the router served them. <c>Fixtures/skill-writes.json</c> was captured by
/// running the router's own compiled handlers (<c>extensionRoute</c> and <c>skillsValue</c>) against a scratch
/// Claude home and router store, so every test that reads it decodes a body the router really sends. A
/// hand-written body would prove the decoder agrees with its author, which is the failure this file exists to
/// rule out.
/// </summary>
internal static class SkillWritesFixture
{
    private const string FixturePath = "app/windows/MCPRouter.Shell.Tests/Fixtures/skill-writes.json";

    /// <summary>The status and body one route answered with, by the case name the fixture gives it.</summary>
    public static (int Status, string Body) Captured(string name)
    {
        using var document = System.Text.Json.JsonDocument.Parse(RepoRoot.Read(FixturePath));
        var entry = document.RootElement.GetProperty("cases").GetProperty(name);
        return (entry.GetProperty("status").GetInt32(), entry.GetProperty("body").GetRawText());
    }

    public static string Body(string name) => Captured(name).Body;
}
