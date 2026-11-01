using System;
using System.Linq;
using System.Threading.Tasks;
using MCPRouter.Shell.Model.Servers;
using MCPRouter.Shell.Model.Inbox;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace MCPRouter.Shell.Views;

public sealed partial class InboxBoard : UserControl
{
    private readonly ControlApiClient _client = new();
    private readonly InboxBoardModel _model;
    private readonly DispatcherTimer _poll = new() { Interval = TimeSpan.FromSeconds(3) };
    private bool _fixture;


    public InboxBoard()
    {
        InitializeComponent();
        _model = new InboxBoardModel(new RouterInboxService(_client));
#if DEBUG
        _fixture = Environment.GetCommandLineArgs().Contains("--fixture-inbox");
        if (_fixture) _model.PopulateSampleData();
#endif
        _poll.Tick += async (_, _) => await ReloadAsync();
        Loaded += async (_, _) => { await ReloadAsync(); _poll.Start(); };
        Unloaded += (_, _) => _poll.Stop();
        RenderCards();
    }

    private async Task ReloadAsync()
    {
        if (!_fixture) await _model.LoadAsync();
        RenderCards();
    }

    private async Task DecideAsync(InboxItem item, string action)
    {
        if (_fixture)
        {
            if (action == "accept") _model.Approve(item.Id);
            else _model.Decline(item.Id);
        }
        else await _model.DecideAsync(item.Id, action);
        RenderCards();
    }

    private void RenderCards()
    {
        CardsContainer.Children.Clear();
        UpdateTabs();
        if (_model.Error is {} error)
            CardsContainer.Children.Add(new TextBlock { Text = error, TextWrapping = TextWrapping.Wrap });
        if (!_fixture && !_model.HasLoaded)
        {
            if (_model.Error is null) CardsContainer.Children.Add(new TextBlock { Text = "Reading your inbox…" });
            return;
        }

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
            approveBtn.IsEnabled = item.CanApprove && !_model.Writing;
            approveBtn.Click += async (_, _) => await DecideAsync(item, "accept");
            btnRow.Children.Add(approveBtn);

            var declineBtn = new Button
            {
                Content = InboxPresentation.NotForMe,
                Style = (Style)Application.Current.Resources["SubtleButtonStyle"]
            };
            declineBtn.IsEnabled = !_model.Writing;
            declineBtn.Click += async (_, _) => await DecideAsync(item, "decline");
            btnRow.Children.Add(declineBtn);

            stack.Children.Add(btnRow);
        }

        if (!_fixture && item.State == DecisionState.NotForMe)
        {
            var restore = new Button { Content = "Restore to waiting", IsEnabled = !_model.Writing };
            restore.Click += async (_, _) => await DecideAsync(item, "restore");
            stack.Children.Add(restore);
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
