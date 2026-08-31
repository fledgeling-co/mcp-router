using System;
using MCPRouter.Shell.Model.Ambient;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

public sealed partial class AmbientFlyoutView : UserControl
{
    private readonly AmbientSurfaceModel _model = new();
    private readonly Action<string>? _navigate;

    public AmbientFlyoutView(Action<string>? navigate = null)
    {
        InitializeComponent();
        _navigate = navigate;
        UpdateUI();
    }

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
