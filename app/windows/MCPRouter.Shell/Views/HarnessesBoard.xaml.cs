using MCPRouter.Shell.Model.Harnesses;
using MCPRouter.Shell.Model.Registry;
using MCPRouter.Shell.Model.Servers;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The Harnesses board: which AI tools on this PC route through the router, and how.
///
/// <para>Everything drawn here is a reading of <c>GET /harnesses</c> through <see cref="ControlApiClient"/>.
/// The states, the row labels and the copy are decided in <c>MCPRouter.Shell.Model/Harnesses/</c>,
/// where they are tested; this class renders the snapshot it is handed and runs the Rescan read.</para>
/// </summary>
public sealed partial class HarnessesBoard : UserControl
{
    private readonly ControlApiClient _client = new(new Uri(ControlEndpoint.BaseUrl() + "/"));

    /// <summary>The last reading that answered. Kept across a failed read, so the board can say what it still shows.</summary>
    private HarnessesEnvelope? _lastAnswered;

    /// <summary>The latest read's failure, or null when the latest read answered.</summary>
    private ControlApiException? _latestError;

    private bool _readInFlight;

    public HarnessesBoard()
    {
        InitializeComponent();
        Render();
        _ = ReadAsync();
    }

    private void RescanButton_Click(object sender, RoutedEventArgs e) => _ = ReadAsync();

    private async Task ReadAsync()
    {
        if (_readInFlight) return;

        _readInFlight = true;
        Render();
        try
        {
            _lastAnswered = await _client.GetHarnessesAsync();
            _latestError = null;
        }
        catch (ControlApiException failure)
        {
            _latestError = failure;
        }
        finally
        {
            _readInFlight = false;
        }
        Render();
    }

    private void Render()
    {
        var snapshot = HarnessesBoardModel.Snapshot(_lastAnswered, _latestError);
        NoticeContainer.Children.Clear();
        HarnessContainer.Children.Clear();
        RescanButton.IsEnabled = !_readInFlight;

        switch (snapshot.State)
        {
            case HarnessesBoardState.Loading:
                AddNotice(null, "Reading the harness configurations…");
                break;

            case HarnessesBoardState.Populated:
                AddReadingNotes(snapshot.ReadAt);
                AddCards(snapshot.Harnesses);
                break;

            case HarnessesBoardState.Empty:
                AddReadingNotes(snapshot.ReadAt);
                AddNotice(HarnessPresentation.EmptyTitle, HarnessPresentation.EmptyBody);
                break;

            case HarnessesBoardState.Stale:
                if (snapshot.Error is { } stale && snapshot.ReadAt is { } readAt)
                {
                    AddNotice(null, HarnessPresentation.StaleNote(readAt, stale.Headline));
                }
                AddNotice(null, HarnessPresentation.ScopeNote);
                AddCards(snapshot.Harnesses);
                break;

            case HarnessesBoardState.Unreachable:
            case HarnessesBoardState.Refused:
                if (snapshot.Error is { } failure)
                {
                    AddNotice(failure.Headline, failure.Advice);
                }
                break;
        }
    }

    private void AddReadingNotes(string? readAt)
    {
        if (readAt is not null)
        {
            AddNotice(null, HarnessPresentation.ReadAtNote(readAt));
        }
        AddNotice(null, HarnessPresentation.ScopeNote);
    }

    private void AddNotice(string? title, string body)
    {
        if (title is not null)
        {
            NoticeContainer.Children.Add(new TextBlock
            {
                Text = title,
                Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
                TextWrapping = TextWrapping.Wrap
            });
        }

        NoticeContainer.Children.Add(new TextBlock
        {
            Text = body,
            Style = (Style)Application.Current.Resources["BodyTextBlockStyle"],
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            TextWrapping = TextWrapping.Wrap
        });
    }

    private void AddCards(IReadOnlyList<HarnessRow> harnesses)
    {
        foreach (var harness in harnesses)
        {
            HarnessContainer.Children.Add(CreateHarnessCard(harness));
        }
    }

    private UIElement CreateHarnessCard(HarnessRow harness)
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

        // An unreadable file is flagged the same way a duplicating harness is: both are a row a person should look at.
        var flagged = HarnessesBoardModel.IsCaution(harness) || harness.Unreadable is not null;
        var pillBorder = new Border
        {
            Background = flagged
                ? (Brush)Application.Current.Resources["SystemFillColorCautionBackgroundBrush"]
                : (Brush)Application.Current.Resources["SubtleFillColorSecondaryBrush"],
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(6, 2, 6, 2),
            Margin = new Thickness(8, 0, 0, 0),
            Child = new TextBlock
            {
                Text = HarnessesBoardModel.RowLabel(harness),
                Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
                Foreground = flagged
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

        if (!harness.Exists)
        {
            stack.Children.Add(new TextBlock
            {
                Text = HarnessPresentation.NoConfigNote,
                Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
            });
        }

        if (harness.Unreadable is { } reason)
        {
            stack.Children.Add(new TextBlock
            {
                Text = HarnessPresentation.UnreadableNote(reason),
                Style = (Style)Application.Current.Resources["BodyTextBlockStyle"],
                Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"],
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 4, 0, 4)
            });
        }

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

        stack.Children.Add(new TextBlock
        {
            Text = harness.HttpCapability,
            Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            TextWrapping = TextWrapping.Wrap
        });

        var btnRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 8, 0, 0) };
        btnRow.Children.Add(new Button { Content = "Open config", Style = (Style)Application.Current.Resources["SubtleButtonStyle"] });
        btnRow.Children.Add(new Button { Content = "Verify now", Style = (Style)Application.Current.Resources["SubtleButtonStyle"] });

        stack.Children.Add(btnRow);
        border.Child = stack;
        return border;
    }
}
