using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using MCPRouter.Shell.Model.Insights;
using MCPRouter.Shell.Model.Registry;
using MCPRouter.Shell.Model.Servers;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The Insights board: what the agents on this PC used through the router, and what the session analyst found.
///
/// <para>Everything drawn here is a reading of <c>GET /insights</c> through <see cref="ControlApiClient"/>, and
/// the one action is <c>POST /insights/analyse</c>. The figures, states and copy are decided in
/// <c>MCPRouter.Shell.Model/Insights/</c>, where they are tested; this class renders the snapshot it is handed
/// and runs the reads.</para>
/// </summary>
public sealed partial class InsightsBoard : UserControl
{
    private readonly ControlApiClient _client = new(new Uri(ControlEndpoint.BaseUrl() + "/"));

    /// <summary>The last reading that answered. Kept across a failed read, so the board can say what it still shows.</summary>
    private InsightsEnvelope? _lastAnswered;

    /// <summary>The latest read's failure, or null when the latest read answered.</summary>
    private ControlApiException? _latestError;

    /// <summary>The last analyse's failure, or null. A failed analyse leaves the reading as it was.</summary>
    private ControlApiException? _analyseFailure;

    private bool _readInFlight;
    private bool _analyseInFlight;

    public InsightsBoard()
    {
        InitializeComponent();
        TitleText.Text = InsightsPresentation.Title;
        DescriptionText.Text = InsightsPresentation.BoardDescription;
        Render();
        _ = ReadAsync();
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e) => _ = ReadAsync();

    private void AnalyseNowButton_Click(object sender, RoutedEventArgs e) => _ = AnalyseAsync();

    private async Task ReadAsync()
    {
        if (_readInFlight) return;

        _readInFlight = true;
        Render();
        try
        {
            _lastAnswered = await _client.GetInsightsAsync();
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

    private async Task AnalyseAsync()
    {
        if (_analyseInFlight) return;

        _analyseInFlight = true;
        _analyseFailure = null;
        Render();
        try
        {
            await _client.AnalyseInsightsAsync();
            // The outcome is what the router reports afterwards, so the board reads it back rather than trusting the answer.
            await ReadAsync();
        }
        catch (ControlApiException failure)
        {
            _analyseFailure = failure;
        }
        finally
        {
            _analyseInFlight = false;
        }
        Render();
    }

    private void Render()
    {
        var snapshot = InsightsBoardModel.Snapshot(_lastAnswered, _latestError, _analyseFailure);

        NoticeContainer.Children.Clear();
        FigureContainer.Children.Clear();
        FigureContainer.ColumnDefinitions.Clear();
        HarnessBreakdownContainer.Children.Clear();
        AnalystContainer.Children.Clear();

        WindowText.Text = snapshot.WindowLabel ?? "";
        RefreshButton.IsEnabled = !_readInFlight;
        AnalyseNowButton.IsEnabled = snapshot.AnalyseNowEnabled && !_analyseInFlight;

        if (snapshot.State == InsightsBoardState.Loading)
        {
            NoticeContainer.Children.Add(Line("Reading the router's counts…", "BodyTextBlockStyle", Secondary));
        }

        foreach (var note in snapshot.Notes)
        {
            NoticeContainer.Children.Add(Line(note, "BodyTextBlockStyle", Secondary));
        }

        if (snapshot.Error is { } failure && snapshot.Figures.Count == 0)
        {
            NoticeContainer.Children.Add(Line(failure.Headline, "BodyStrongTextBlockStyle"));
            NoticeContainer.Children.Add(Line(failure.Advice, "BodyTextBlockStyle", Secondary));
        }

        AddFigures(snapshot.Figures);

        var answered = snapshot.ReadAt is not null;
        HarnessSection.Visibility = answered ? Visibility.Visible : Visibility.Collapsed;
        AnalystSection.Visibility = answered ? Visibility.Visible : Visibility.Collapsed;

        foreach (var line in snapshot.Harnesses)
        {
            HarnessBreakdownContainer.Children.Add(CreateHarnessRow(line));
        }

        if (snapshot.Analyst is { } card)
        {
            AddAnalystCard(card, snapshot.AnalyseFailure);
        }
    }

    private void AddFigures(IReadOnlyList<InsightsFigure> figures)
    {
        // Each tile takes an equal share, with a 16-pixel gutter between neighbours.
        for (var i = 0; i < figures.Count; i++)
        {
            FigureContainer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            if (i < figures.Count - 1)
            {
                FigureContainer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });
            }
        }

        for (var i = 0; i < figures.Count; i++)
        {
            var tile = CreateTile(figures[i]);
            Grid.SetColumn(tile, i * 2);
            FigureContainer.Children.Add(tile);
        }
    }

    private Border CreateTile(InsightsFigure figure)
    {
        var stack = new StackPanel { Spacing = 4 };
        stack.Children.Add(Line(figure.Value, "TitleTextBlockStyle", fontWeight: Microsoft.UI.Text.FontWeights.Bold));
        stack.Children.Add(Line(figure.Label, "BodyTextBlockStyle", fontWeight: Microsoft.UI.Text.FontWeights.SemiBold));
        stack.Children.Add(Line(figure.Provenance, "CaptionTextBlockStyle", Secondary));

        return new Border
        {
            Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = (CornerRadius)Application.Current.Resources["ControlCornerRadius"],
            Padding = new Thickness(16, 12, 16, 12),
            Child = stack,
        };
    }

    private UIElement CreateHarnessRow(InsightsHarnessLine line)
    {
        var grid = new Grid { Padding = new Thickness(16, 12, 16, 12) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var name = Line(line.Name, "BodyTextBlockStyle", fontWeight: Microsoft.UI.Text.FontWeights.SemiBold);
        name.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(name, 0);
        grid.Children.Add(name);

        var calls = Line(line.Calls, "BodyTextBlockStyle");
        calls.FontFamily = new FontFamily("Consolas");
        calls.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(calls, 1);
        grid.Children.Add(calls);

        var share = Line(line.Share ?? "", "BodyTextBlockStyle", Secondary);
        share.FontFamily = new FontFamily("Consolas");
        share.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(share, 2);
        grid.Children.Add(share);

        if (!string.IsNullOrWhiteSpace(line.Explanation))
        {
            var explanation = Line(line.Explanation, "BodyTextBlockStyle", Secondary);
            explanation.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(explanation, 3);
            grid.Children.Add(explanation);
        }

        return grid;
    }

    private void AddAnalystCard(InsightsAnalystCard card, ControlApiException? analyseFailure)
    {
        if (!card.Available)
        {
            AnalystContainer.Children.Add(Line(card.Notice ?? "", "BodyTextBlockStyle", Secondary));
        }
        else
        {
            AnalystContainer.Children.Add(Line(card.LastRun ?? "", "BodyTextBlockStyle"));
            foreach (var note in card.StoreNotes)
            {
                AnalystContainer.Children.Add(Line(note, "CaptionTextBlockStyle", Secondary));
            }
            if (card.ScheduleNote is { } schedule)
            {
                AnalystContainer.Children.Add(Line(schedule, "CaptionTextBlockStyle", Secondary));
            }
        }

        if (analyseFailure is not null)
        {
            AnalystContainer.Children.Add(Line(analyseFailure.UserFacingDescription, "BodyTextBlockStyle", Caution));
        }
    }

    private static TextBlock Line(
        string text,
        string styleKey,
        Brush? foreground = null,
        Windows.UI.Text.FontWeight? fontWeight = null)
    {
        var line = new TextBlock
        {
            Text = text,
            Style = (Style)Application.Current.Resources[styleKey],
            TextWrapping = TextWrapping.Wrap,
        };
        if (foreground is not null) line.Foreground = foreground;
        if (fontWeight is { } weight) line.FontWeight = weight;
        return line;
    }

    private static Brush Secondary => (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];

    private static Brush Caution => (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
}
