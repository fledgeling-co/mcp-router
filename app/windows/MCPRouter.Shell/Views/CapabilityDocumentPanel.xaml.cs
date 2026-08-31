using System;
using MCPRouter.Shell.Model.CapabilityDocument;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace MCPRouter.Shell.Views;

public sealed partial class CapabilityDocumentPanel : UserControl
{
    private readonly CapabilityDocumentViewModel _vm = new();

    public CapabilityDocumentPanel(string capabilityId = "postgres-mcp")
    {
        InitializeComponent();
        _vm.LoadDocument(capabilityId);
        RenderDocument();
    }

    private void RenderDocument()
    {
        if (_vm.Document == null) return;
        PackageTitle.Text = $"{_vm.Document.DisplayName} {_vm.Document.CandidateVersion}";

        DeltasContainer.Children.Clear();
        foreach (var delta in _vm.Document.CapabilityDeltas)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            row.Children.Add(new TextBlock
            {
                Text = $"+ {delta.Name}",
                FontFamily = new FontFamily("Consolas"),
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            row.Children.Add(new TextBlock
            {
                Text = delta.Description,
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
            });
            DeltasContainer.Children.Add(row);
        }

        ChangelogBlock.Text = _vm.Document.ChangelogText;
    }
}
