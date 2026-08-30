using MCPRouter.Shell.Model;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

/// <summary>
/// What a destination draws before the item that owns it has been built.
///
/// The brief's requirement, in its own words: "a board with nothing behind it yet says so rather
/// than rendering blank". Two sentences do that - one describing the board, one describing this
/// build - because a reader who gets only the first cannot tell an unbuilt board from a broken
/// one.
/// </summary>
public sealed partial class BoardPlaceholder : UserControl
{
    public BoardPlaceholder(Destination destination)
    {
        InitializeComponent();

        Glyph.Glyph = SymbolGlyph(destination.Symbol);
        BoardName.Text = destination.Label;
        WillShow.Text = destination.WillShow;
        NotBuiltYet.Text = destination.NotBuiltYet;

        // The card announces as one stop rather than four, for the reason DESIGN.md §2 gives the
        // sidebar's readout card: splitting a label from the value it heads costs a screen-reader
        // user a swipe to reach a label that carries nothing on its own.
        AutomationProperties.SetName(this,
            $"{destination.Label}. {destination.WillShow} {destination.NotBuiltYet}");
    }

    /// <summary>
    /// The Segoe Fluent codepoint behind a <see cref="Symbol"/> value.
    ///
    /// The pane uses <c>SymbolIcon</c>, which takes the enum and cannot carry an invalid
    /// codepoint. This control needs the same mark at a larger size in a <c>FontIcon</c>, so the
    /// enum is converted rather than a second literal being typed beside it - the two marks are
    /// then one value, and cannot drift apart.
    /// </summary>
    private static string SymbolGlyph(string symbolName) =>
        char.ConvertFromUtf32((int)Enum.Parse<Symbol>(symbolName));
}
