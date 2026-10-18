using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;

namespace MCPRouter.AutomationProbe;

/// <summary>
/// The probe window. Its size is pinned so a geometry reading off the automation plane is
/// reproducible between runs, and it selects the "Servers" destination at load so the selected
/// state exists before the harness ever looks.
/// </summary>
public sealed partial class MainWindow : Window
{
    // 1024x768 is the campaign's Mac acceptance viewport (coverage-model.md). Reusing it here
    // means a Windows cell and a Mac cell name the same viewport rather than two arbitrary ones.
    private const int WidthPx = 1024;
    private const int HeightPx = 768;

    public MainWindow()
    {
        App.Trace("MainWindow: before InitializeComponent");
        InitializeComponent();
        App.Trace("MainWindow: after InitializeComponent");

        AppWindow.Resize(new Windows.Graphics.SizeInt32(WidthPx, HeightPx));

        // Off the top-left corner rather than centred: the harness reads bounding rectangles, and
        // a window at a known origin makes a wrong rectangle obvious instead of plausible.
        AppWindow.Move(new Windows.Graphics.PointInt32(80, 80));
        App.Trace("MainWindow: resized and moved");

        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
        }

        Shell.SelectedItem = ServersItem;
        App.Trace("MainWindow: Servers selected");
    }
}
