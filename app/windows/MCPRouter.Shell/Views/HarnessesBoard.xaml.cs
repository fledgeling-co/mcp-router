using System;
using MCPRouter.Shell.Model.Harnesses;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace MCPRouter.Shell.Views;

public sealed partial class HarnessesBoard : UserControl
{
    private readonly HarnessesBoardModel _model = new();

    public HarnessesBoard()
    {
        InitializeComponent();
        _model.PopulateSampleData();
        RenderCards();
    }

    private void RenderCards()
    {
        HarnessContainer.Children.Clear();

        foreach (var harness in _model.Harnesses)
        {
            HarnessContainer.Children.Add(CreateHarnessCard(harness));
        }
    }

    private UIElement CreateHarnessCard(DetectedHarness harness)
    {
        var border = new Border
        {
            Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = (CornerRadius)Application.Current.Resources["ControlCornerRadius"],
            Padding = new Thickness(16)
        };

        var stack = new StackPanel { Spacing = 8 };

        var topRow = new Grid();
        topRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        topRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        topRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var titleBlock = new TextBlock
        {
            Text = harness.DisplayName,
            Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"],
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        };
        Grid.SetColumn(titleBlock, 0);
        topRow.Children.Add(titleBlock);

        var pillBorder = new Border
        {
            Background = harness.State == HarnessReading.RoutedWithDirectServers
                ? (Brush)Application.Current.Resources["SystemFillColorCautionBackgroundBrush"]
                : (Brush)Application.Current.Resources["SubtleFillColorSecondaryBrush"],
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(6, 2, 6, 2),
            Margin = new Thickness(8, 0, 0, 0),
            Child = new TextBlock
            {
                Text = HarnessPresentation.StateLabel(harness.State),
                Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
                Foreground = harness.State == HarnessReading.RoutedWithDirectServers
                    ? (Brush)Application.Current.Resources["SystemFillColorCautionBrush"]
                    : (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
            }
        };
        Grid.SetColumn(pillBorder, 1);
        topRow.Children.Add(pillBorder);

        stack.Children.Add(topRow);

        var pathText = new TextBlock
        {
            Text = harness.Path,
            FontFamily = new FontFamily("Consolas"),
            Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
            Foreground = (Brush)Application.Current.Resources["TextFillColorTertiaryBrush"]
        };
        stack.Children.Add(pathText);

        if (harness.DuplicateCount > 0)
        {
            var warnText = new TextBlock
            {
                Text = HarnessPresentation.DoubleRunningWarning(harness.DuplicateCount),
                Style = (Style)Application.Current.Resources["BodyTextBlockStyle"],
                Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"],
                Margin = new Thickness(0, 4, 0, 4)
            };
            stack.Children.Add(warnText);
        }

        var btnRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 8, 0, 0) };
        btnRow.Children.Add(new Button { Content = "Open config", Style = (Style)Application.Current.Resources["SubtleButtonStyle"] });
        btnRow.Children.Add(new Button { Content = "Verify now", Style = (Style)Application.Current.Resources["SubtleButtonStyle"] });

        stack.Children.Add(btnRow);
        border.Child = stack;
        return border;
    }
}
