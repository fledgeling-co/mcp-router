namespace MCPRouter.Shell.Model;

/// <summary>
/// One of the ten places the window can be. Nine boards and Settings.
///
/// The nine boards, their labels and their four group headers are the design of record's
/// (<c>design/mcp-router-console.html</c>, the sidebar). <c>DestinationCatalogTests</c> parses
/// that file and holds this list to it, so the information architecture is inherited rather than
/// retyped - which is the point of the directive: parity of feature, Windows in look.
/// </summary>
/// <param name="Id">Stable id. Matches the mock's <c>data-board</c> value for the nine boards.</param>
/// <param name="Label">What the pane and the window title say. Sentence case, §11 rule 2.</param>
/// <param name="Group">The pane header this sits under, or null for the pane-footer settings item.</param>
/// <param name="Symbol">A <c>Microsoft.UI.Xaml.Controls.Symbol</c> name, resolved in the view.</param>
/// <param name="Accelerator">Its chord, where DESIGN.md §13 grants one.</param>
/// <param name="AccessKey">Its access key inside the View menu. §11 rule 9.</param>
/// <param name="WillShow">One sentence: what this board will show once it is built.</param>
/// <param name="BuiltBy">The pipeline id that builds it.</param>
public sealed record Destination(
    string Id,
    string Label,
    string? Group,
    string Symbol,
    Accelerator? Accelerator,
    string AccessKey,
    string WillShow,
    string BuiltBy)
{
    /// <summary>
    /// The window title for this destination. DESIGN.md §11 rule 7 and §3 rule 7 before it: the
    /// title says what you are looking at, not the app's name.
    /// </summary>
    public string WindowTitle => Label;

    /// <summary>
    /// The second sentence the placeholder draws. Separate from <see cref="WillShow"/> because
    /// one describes the board and the other describes this build - and a reader is owed both,
    /// rather than a blank pane that could equally be a bug.
    /// </summary>
    public string NotBuiltYet =>
        $"This board is not built yet. {BuiltBy} builds it; the shell it will be drawn inside is here now.";
}
