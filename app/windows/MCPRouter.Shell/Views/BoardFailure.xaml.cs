using MCPRouter.Shell.Model;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

/// <summary>
/// What a destination draws when constructing its board threw.
///
/// DEF-078 is why this type exists. `ShowDestination` mounted a board with a single statement -
/// <c>BoardHost.Content = destinationId switch { ... }</c> - and an exception thrown while
/// building the board abandoned that statement, so the window title and caption band two lines
/// below it never ran either. The shell went on showing the previous board under the previous
/// title while the pane item the user had clicked sat highlighted. Three of nine boards did this,
/// in both sweep directions, and every check the project had still passed: the boards compiled,
/// the pane drew all ten names, and the navigation switch really did map ten distinct types.
///
/// A silent failure that leaves a working-looking application on screen is worse than a crash,
/// because a crash gets investigated. So this control is loud, and three properties of it are
/// deliberate:
///
///   · It is NOT <see cref="BoardPlaceholder"/>. That says "this board is not built yet", which
///     over a board that was built and then failed is the most misleading sentence available.
///   · It carries the exception's type and message in the visual tree rather than only in a log,
///     so the automation plane can read the failure out of process. The lane grades boards by
///     what the tree contains, and a board that fails now announces the fact in the tree.
///   · It names where the full detail was written, because the message alone rarely names the
///     throwing line.
/// </summary>
public sealed partial class BoardFailure : UserControl
{
    public BoardFailure(Destination destination, Exception exception)
    {
        InitializeComponent();

        BoardName.Text = $"{destination.Label} could not be opened";
        Summary.Text =
            "This board exists and failed while it was being built, so it is not an unfinished "
            + "board and not an empty one. The shell is intact; nothing else has been affected.";
        Detail.Text = $"{exception.GetType().FullName}: {exception.Message}";
        Where.Text = "The full exception, with its stack, is in shell-startup.log beside the "
            + "executable.";

        // One stop rather than five. DESIGN.md §2's rule for the readout card: splitting a label
        // from the value it heads costs a screen-reader user a swipe to reach a label that
        // carries nothing on its own. The exception text is inside the announcement on purpose -
        // it is the part a reader actually needs.
        AutomationProperties.SetName(this,
            $"{BoardName.Text}. {Summary.Text} {Detail.Text}");
        AutomationProperties.SetAutomationId(this, $"board.failure.{destination.Id}");
    }
}
