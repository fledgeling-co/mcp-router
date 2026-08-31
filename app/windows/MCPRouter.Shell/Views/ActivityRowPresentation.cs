using MCPRouter.Shell.Live;
using Microsoft.UI.Xaml;

namespace MCPRouter.Shell.Views;

/// <summary>
/// One row of the log as the row template binds it.
///
/// The view model (<see cref="ActivityRowVm"/>) stays plain data in the wire library, headless
/// and free of UI types. This wrapper adds the one thing the template needs that the view model
/// cannot give it: <see cref="Visibility"/> for each of the three result marks. x:Bind binds
/// instance properties (WinUI has no x:Static), and computing visibility in XAML from an enum is
/// exactly the static-function shape x:Bind does not carry, so the three properties live here.
///
/// The marks are three elements with <c>ThemeResource</c> fills, shown and collapsed - not one
/// element whose brush is set in code. A brush set in code resolves under the app's theme rather
/// than the element's, and this shell learned that lesson once already (spec-WIN3, the capture
/// that came back dark-on-dark): every colour stays a theme resource in the template, which
/// resolves under the element that draws it and follows <c>ActualTheme</c> on its own.
/// </summary>
internal sealed record ActivityRowPresentation(ActivityRowVm Row)
{
    /// <summary>§3.2's table: ok takes the success mark.</summary>
    public Visibility SuccessMarkVisibility =>
        Row.ResultKind == CallResultKind.Ok ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>held takes the caution mark - and nothing on this wire produces held today.</summary>
    public Visibility CautionMarkVisibility =>
        Row.ResultKind == CallResultKind.Held ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>timeout and failed both take the critical mark; the word beside it is what
    /// separates them, which is §12's rule doing its work on the one cell that carries colour.</summary>
    public Visibility CriticalMarkVisibility =>
        Row.ResultKind is CallResultKind.Failed or CallResultKind.Timeout
            ? Visibility.Visible
            : Visibility.Collapsed;

    // Pass-throughs: the template binds these directly, and keeping them one hop deep means the
    // template reads {x:Bind TimeText} rather than {x:Bind Row.TimeText} - a rename of the view
    // model then touches one file rather than a DataTemplate.
    public string TimeText => Row.TimeText;
    public string HarnessText => Row.HarnessText;
    public string ToolText => Row.ToolText;
    public string DurationText => Row.DurationText;
    public string ResultWord => Row.ResultWord;
    public string ToolTipText => Row.ToolTipText;
    public string AutomationName => Row.AutomationName;
}
