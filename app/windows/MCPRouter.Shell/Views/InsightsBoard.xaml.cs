using System;
using MCPRouter.Shell.Model.Insights;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace MCPRouter.Shell.Views;

public sealed partial class InsightsBoard : UserControl
{
    private readonly InsightsBoardModel _model = new();

    public InsightsBoard()
    {
        InitializeComponent();
        RenderBreakdown();
    }

    private void RenderBreakdown()
    {
        HarnessBreakdownContainer.Children.Clear();
        var summary = _model.GetSummary();

        foreach (var harness in summary.HarnessBreakdown)
        {
            var grid = new Grid { Padding = new Thickness(16, 12, 16, 12) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var nameText = new TextBlock { Text = harness.HarnessName, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(nameText, 0);
            grid.Children.Add(nameText);

            var countText = new TextBlock { Text = harness.CallCount.ToString("N0"), FontFamily = new FontFamily("Consolas"), VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(countText, 1);
            grid.Children.Add(countText);

            var pctText = new TextBlock { Text = $"{harness.Percentage:F1}%", FontFamily = new FontFamily("Consolas"), Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"], VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(pctText, 2);
            grid.Children.Add(pctText);

            if (!string.IsNullOrWhiteSpace(harness.Explanation))
            {
                var explText = new TextBlock { Text = harness.Explanation, Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"], VerticalAlignment = VerticalAlignment.Center };
                Grid.SetColumn(explText, 3);
                grid.Children.Add(explText);
            }

            HarnessBreakdownContainer.Children.Add(grid);
        }
    }
}
