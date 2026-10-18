using System;
using System.Linq;
using MCPRouter.Shell.Model.Inbox;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace MCPRouter.Shell.Views;

public sealed partial class InboxBoard : UserControl
{
    private readonly InboxBoardModel _model = new();

    public InboxBoard()
    {
        InitializeComponent();
        _model.PopulateSampleData();
        RenderCards();
    }

    private void RenderCards()
    {
        CardsContainer.Children.Clear();
        UpdateTabs();

        var items = _model.FilteredItems;
        if (items.Count == 0)
        {
            CardsContainer.Children.Add(new TextBlock
            {
                Text = "Nothing in this view.",
                Style = (Style)Application.Current.Resources["BodyTextBlockStyle"],
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
                Margin = new Thickness(0, 24, 0, 0)
            });
            return;
        }

        foreach (var item in items)
        {
            CardsContainer.Children.Add(CreateCardElement(item));
        }
    }

    private UIElement CreateCardElement(InboxItem item)
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
            Text = item.Name,
            Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"],
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        };
        Grid.SetColumn(titleBlock, 0);
        topRow.Children.Add(titleBlock);

        var pillBorder = new Border
        {
            Background = (Brush)Application.Current.Resources["SubtleFillColorSecondaryBrush"],
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(6, 2, 6, 2),
            Margin = new Thickness(8, 0, 0, 0),
            Child = new TextBlock
            {
                Text = item.OriginLabel,
                Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
            }
        };
        Grid.SetColumn(pillBorder, 1);
        topRow.Children.Add(pillBorder);

        var timeBlock = new TextBlock
        {
            Text = item.ArrivedAgo,
            Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
            Foreground = (Brush)Application.Current.Resources["TextFillColorTertiaryBrush"],
            HorizontalAlignment = HorizontalAlignment.Right
        };
        Grid.SetColumn(timeBlock, 2);
        topRow.Children.Add(timeBlock);

        stack.Children.Add(topRow);

        var ledeText = new TextBlock
        {
            Text = item.Lede,
            Style = (Style)Application.Current.Resources["BodyTextBlockStyle"],
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            TextWrapping = TextWrapping.Wrap
        };
        stack.Children.Add(ledeText);

        if (item.CapabilityLines.Count > 0)
        {
            stack.Children.Add(new TextBlock
            {
                Text = InboxPresentation.ReviewSectionTitle,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Margin = new Thickness(0, 8, 0, 4)
            });

            var capStack = new StackPanel { Spacing = 4 };
            foreach (var cap in item.CapabilityLines)
            {
                var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                var dot = new Ellipse
                {
                    Width = 8,
                    Height = 8,
                    Fill = cap.IsWarning
                        ? (Brush)Application.Current.Resources["SystemFillColorCautionBrush"]
                        : (Brush)Application.Current.Resources["TextFillColorTertiaryBrush"],
                    VerticalAlignment = VerticalAlignment.Center
                };
                row.Children.Add(dot);
                row.Children.Add(new TextBlock
                {
                    Text = cap.Text,
                    Style = (Style)Application.Current.Resources["BodyTextBlockStyle"],
                    Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
                });
                capStack.Children.Add(row);
            }
            stack.Children.Add(capStack);
        }

        if (item.State == DecisionState.Undecided)
        {
            var btnRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 12, 0, 0) };

            var approveBtn = new Button
            {
                Content = InboxPresentation.ApproveAndInstall,
                Background = (Brush)Application.Current.Resources["AccentFillColorDefaultBrush"],
                Foreground = (Brush)Application.Current.Resources["TextOnAccentFillColorPrimaryBrush"]
            };
            approveBtn.Click += (_, _) =>
            {
                _model.Approve(item.Id);
                RenderCards();
            };
            btnRow.Children.Add(approveBtn);

            var declineBtn = new Button
            {
                Content = InboxPresentation.NotForMe,
                Style = (Style)Application.Current.Resources["SubtleButtonStyle"]
            };
            declineBtn.Click += (_, _) =>
            {
                _model.Decline(item.Id);
                RenderCards();
            };
            btnRow.Children.Add(declineBtn);

            stack.Children.Add(btnRow);
        }

        border.Child = stack;
        return border;
    }

    private void UpdateTabs()
    {
        TabUndecided.Content = InboxPresentation.TabLabel(DecisionState.Undecided, _model.UndecidedCount);
        TabApproved.Content = InboxPresentation.TabLabel(DecisionState.Approved, _model.ApprovedCount);
        TabNotForMe.Content = InboxPresentation.TabLabel(DecisionState.NotForMe, _model.NotForMeCount);
    }

    private void OnTabUndecidedClicked(object sender, RoutedEventArgs e)
    {
        _model.SelectedFilter = DecisionState.Undecided;
        RenderCards();
    }

    private void OnTabApprovedClicked(object sender, RoutedEventArgs e)
    {
        _model.SelectedFilter = DecisionState.Approved;
        RenderCards();
    }

    private void OnTabNotForMeClicked(object sender, RoutedEventArgs e)
    {
        _model.SelectedFilter = DecisionState.NotForMe;
        RenderCards();
    }
}
