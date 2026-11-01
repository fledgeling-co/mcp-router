using System;
using MCPRouter.Shell.Model.Pairing;
using MCPRouter.Shell.Model.Servers;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;

namespace MCPRouter.Shell.Views;

public sealed partial class PairingDialog : UserControl
{
    private readonly PairingSessionModel _model;

    /// <summary>Asks the model what time it is once a second. The expiry is the router's; this only ticks.</summary>
    private readonly DispatcherTimer _clock = new() { Interval = TimeSpan.FromSeconds(1) };

    public PairingDialog()
    {
        InitializeComponent();

        _model = new PairingSessionModel(new ControlApiClient(new Uri(MCPRouter.Shell.Model.Registry.ControlEndpoint.BaseUrl() + "/")));
        _model.StateChanged += (_, _) => UpdateUI();
        _clock.Tick += async (_, _) => { _model.Tick(); await _model.RefreshAsync(); };

        // The code is asked for when the sheet is shown and taken back when it goes away, so the router
        // never holds a live code nobody is looking at.
        Loaded += async (_, _) =>
        {
            _clock.Start();
            await _model.OpenAsync();
        };
        Unloaded += async (_, _) =>
        {
            _clock.Stop();
            await _model.CloseAsync();
        };
        ReissueButton.Click += async (_, _) => await _model.ReissueAsync();

        UpdateUI();
    }

    public Task CloseAsync() { _clock.Stop(); return _model.CloseAsync(); }

    private string? _renderedPayload;

    private async void UpdateUI()
    {
        var state = _model.CurrentState;
        var live = state.Phase == PairingPhase.AwaitingScanOrCode;
        var unavailable = state.Phase == PairingPhase.Unavailable;

        CodeCard.Visibility = live ? Visibility.Visible : Visibility.Collapsed;
        WarningText.Visibility = live ? Visibility.Visible : Visibility.Collapsed;
        PairingCodeText.Text = live && state.PairingCode is { } code ? PairingPresentation.Formatted(code) : "";
        ExpiresText.Text = state.Phase == PairingPhase.Paired
            ? $"Router confirmed {state.PairedDeviceName}. This phone can queue items for review."
            : PairingPresentation.StatusLine(state);
        QrImage.Visibility = live && state.QrPayload is not null ? Visibility.Visible : Visibility.Collapsed;
        EndpointText.Visibility = live ? Visibility.Visible : Visibility.Collapsed;
        EndpointText.Text = live ? "Scan this QR. Manual code entry is unavailable in this build." : "";
        if (live && state.QrPayload is { } payload && payload != _renderedPayload)
        {
            _renderedPayload = payload;
            try
            {
            using var stream = new InMemoryRandomAccessStream();
            using var writer = new DataWriter(stream.GetOutputStreamAt(0));
            writer.WriteBytes(PairingQr.RenderPng(payload));
            await writer.StoreAsync();
            var bitmap = new BitmapImage();
            await bitmap.SetSourceAsync(stream);
            if (_renderedPayload == payload && _model.CurrentState.QrPayload == payload) QrImage.Source = bitmap;
            }
            catch (Exception)
            {
                QrImage.Visibility = Visibility.Collapsed;
                EndpointText.Text = "The QR could not be rendered. Close this dialog and try again.";
            }
        }

        UnavailablePanel.Visibility = unavailable ? Visibility.Visible : Visibility.Collapsed;
        UnavailableHeadlineText.Text = unavailable ? PairingPresentation.UnavailableHeadline(state) : "";
        UnavailableAdviceText.Text = unavailable ? PairingPresentation.UnavailableAdvice(state) : "";

        // A new code helps an expired one and a router that refused. It cannot help a pairing that is
        // off, so that state offers no button rather than one that does nothing.
        var reissuable = state.Phase == PairingPhase.Expired || (unavailable && state.Failure is not null);
        ReissueButton.Content = state.Phase == PairingPhase.Expired
            ? PairingPresentation.NewCodeAction
            : PairingPresentation.RetryAction;
        ReissueButton.Visibility = reissuable ? Visibility.Visible : Visibility.Collapsed;
    }
}
