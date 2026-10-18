namespace MCPRouter.Shell.Tests;

/// <summary>
/// Finds the repository root by walking up from the test assembly until DESIGN.md is beside a
/// planning directory.
///
/// This matters more than it looks: these tests read the design authority and the design of
/// record as their oracle, and a test that silently cannot find them would pass by measuring an
/// empty file. Every reader here throws rather than returning nothing.
/// </summary>
public static class RepoRoot
{
    public static string Path { get; } = Find();

    private static string Find()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (File.Exists(System.IO.Path.Combine(dir.FullName, "DESIGN.md")) &&
                Directory.Exists(System.IO.Path.Combine(dir.FullName, "planning")))
            {
                return dir.FullName;
            }
            dir = dir.Parent;
        }

        throw new InvalidOperationException(
            $"could not find the repository root above {AppContext.BaseDirectory}");
    }

    public static string Read(string relative)
    {
        var full = System.IO.Path.Combine(Path, relative.Replace('/', System.IO.Path.DirectorySeparatorChar));
        if (!File.Exists(full)) throw new FileNotFoundException($"the oracle is missing: {relative}", full);
        var text = File.ReadAllText(full);
        if (text.Length == 0) throw new InvalidOperationException($"the oracle is empty: {relative}");
        return text;
    }
}
