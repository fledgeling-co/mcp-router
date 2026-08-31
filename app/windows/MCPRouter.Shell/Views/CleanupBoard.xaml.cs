using System;
using System.Linq;
using MCPRouter.Shell.Model.Cleanup;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

public sealed partial class CleanupBoard : UserControl
{
    private readonly CleanupBoardModel _model = new();

    public CleanupBoard()
    {
        InitializeComponent();
        _model.PopulateSampleData();
        RenderRows();
    }

    private void RenderRows()
    {
        NeverCalledContainer.Children.Clear();
        QuietContainer.Children.Clear();

        if (_model.TotalCandidates == 0)
        {
            IdealView.Visibility = Visibility.Collapsed;
            EmptyView.Visibility = Visibility.Visible;
            return;
        }

        IdealView.Visibility = Visibility.Visible;
        EmptyView.Visibility = Visibility.Collapsed;

        // Render Never Called rows
        foreach (var row in _model.NeverCalledRows)
        {
            NeverCalledContainer.Children.Add(CreateRowElement(row));
        }

        // Render Quiet rows
        foreach (var row in _model.QuietRows)
        {
            QuietContainer.Children.Add(CreateRowElement(row));
        }

        UpdateSelectionUI();
    }

    private UIElement CreateRowElement(CleanupRow row)
    {
        var grid = new Grid { Padding = new Thickness(16, 12, 16, 12) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) }); // Name + Checkbox
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100) }); // Kind
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });  // Tools
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) }); // Installed
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); // Why it might matter
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) }); // Action

        var checkStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var checkBox = new CheckBox
        {
            IsChecked = row.IsSelected,
            VerticalAlignment = VerticalAlignment.Center
        };
        AutomationProperties.SetName(checkBox, $"Select {row.Name}");
        checkBox.Checked += (_, _) => { _model.SetSelection(row.Id, true); UpdateSelectionUI(); };
        checkBox.Unchecked += (_, _) => { _model.SetSelection(row.Id, false); UpdateSelectionUI(); };

        checkStack.Children.Add(checkBox);
        checkStack.Children.Add(new TextBlock
        {
            Text = row.Name,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center
        });
        Grid.SetColumn(checkStack, 0);
        grid.Children.Add(checkStack);

        var kindText = new TextBlock
        {
            Text = row.Kind == CleanupKind.Server ? "MCP server" : "Skill",
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(kindText, 1);
        grid.Children.Add(kindText);

        var toolsText = new TextBlock
        {
            Text = row.ToolCount.HasValue ? row.ToolCount.Value.ToString() : "—",
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(toolsText, 2);
        grid.Children.Add(toolsText);

        var installedText = new TextBlock
        {
            Text = row.InstalledDate,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(installedText, 3);
        grid.Children.Add(installedText);

        var reasonText = new TextBlock
        {
            Text = row.WhyItMightStillMatter,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(reasonText, 4);
        grid.Children.Add(reasonText);

        var actionButton = new Button
        {
            Content = row.SecondaryActionLabel,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(actionButton, 5);
        grid.Children.Add(actionButton);

        return grid;
    }

    private void UpdateSelectionUI()
    {
        int count = _model.SelectedCount;
        SelectedCountText.Text = $"{count} selected";
        RemoveSelectedButton.IsEnabled = count > 0;
    }

    private void OnRemoveSelectedClicked(object sender, RoutedEventArgs e)
    {
        var selected = _model.GetSelectedRows();
        if (selected.Count == 0) return;
        // Removal dialog logic
    }

    private void OnKeepAllClicked(object sender, RoutedEventArgs e)
    {
        _model.MarkAllAsKeep();
        RenderRows();
    }
}
