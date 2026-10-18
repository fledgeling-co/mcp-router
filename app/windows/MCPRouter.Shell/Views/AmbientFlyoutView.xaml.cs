using System;
using MCPRouter.Shell.Model.Ambient;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

public sealed partial class AmbientFlyoutView : UserControl
{
    private readonly AmbientSurfaceModel _model;
    private readonly Action<string>? _navigate;

    /// <param name="navigate">Where a button on this card sends the operator.</param>
    /// <param name="model">
    /// The ambient state to render - <c>App.Ambient</c>, the one the pane's reader writes.
    /// Null builds a private one, which renders as "Reading the router" until something reads it.
    /// </param>
    /// <remarks>
    /// DEF-301: this view used to build its own model, which no code in the build ever updated,
    /// and its XAML carried "Router ready" and "All systems quiet" as literal text - so the card
    /// said the router was fine before a line of code had run. Both defaults are gone: the text
    /// comes from the model, and the model starts at <c>Unknown</c>.
    ///
    /// WHAT IS STILL OPEN, and it is filed rather than folded in: nothing in this build mounts
    /// this view, so no operator can open it and no arm reads it. DEF-380.
    /// </remarks>
    public AmbientFlyoutView(Action<string>? navigate = null, AmbientSurfaceModel? model = null)
    {
        InitializeComponent();
        _model = model ?? new AmbientSurfaceModel();
        _navigate = navigate;
        UpdateUI();
    }

    /// <summary>Re-render from the model, for a caller that has just taken a reading.</summary>
    public void Refresh() => UpdateUI();

    public void SetState(AmbientRouterState state, int waitingCount = 0, int activeCalls = 0)
    {
        _model.UpdateState(state, waitingCount, activeCalls);
        UpdateUI();
    }

    private void UpdateUI()
    {
        var info = _model.GetStatusInfo();
        StatusTitleText.Text = info.StatusText;
        StatusDetailText.Text = info.Subtitle;
        ViewInboxButton.Content = $"Review Inbox ({info.WaitingCount})";
        ViewInboxButton.IsEnabled = info.WaitingCount > 0;
    }

    private void OnOpenAppClicked(object sender, RoutedEventArgs e)
    {
        _navigate?.Invoke("servers");
    }

    private void OnViewInboxClicked(object sender, RoutedEventArgs e)
    {
        _navigate?.Invoke("inbox");
    }

    private void OnViewServersClicked(object sender, RoutedEventArgs e)
    {
        _navigate?.Invoke("servers");
    }
}
