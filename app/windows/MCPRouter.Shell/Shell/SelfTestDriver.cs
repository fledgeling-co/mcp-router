using System.Text.Json;
using MCPRouter.Shell.Model;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace MCPRouter.Shell.Shell;

/// <summary>
/// Drives the shell through every destination in-process and writes what it observed.
///
/// This exists because of a measurement. On the reference machine the session that runs the gates
/// is Session 0 on a non-interactive window station: a WinUI process started from there dies at
/// <c>0xC000027B</c> before <c>App</c>'s constructor, and an interactive scheduled task, which
/// does host the window, has a window station where <c>EnumWindows</c> returns nothing and
/// <c>CopyFromScreen</c> has nothing to copy. So no external capture channel reaches this app.
///
/// An in-process capture does, and it is honest about its own limits: <see
/// cref="RenderTargetBitmap"/> photographs the XAML tree. It does <b>not</b> hold the Mica
/// backdrop, which composites below XAML, and it does not hold the system caption buttons, which
/// are not XAML at all. Those two claims stay unphotographed, and the report says so rather than
/// letting a picture that cannot contain them stand as evidence that it did.
/// </summary>
internal sealed class SelfTestDriver
{
    private readonly ShellWindow _window;
    private readonly string _directory;
    private readonly List<object> _observations = new();
    private readonly List<string> _failures = new();

    internal SelfTestDriver(ShellWindow window, string directory)
    {
        _window = window;
        _directory = directory;
    }

    internal async Task<int> RunAsync()
    {
        Directory.CreateDirectory(_directory);

        var requested = Environment.GetEnvironmentVariable("MCPR_SELFTEST_DESTINATIONS")?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var destinations = requested is null ? DestinationCatalog.All.ToList()
            : DestinationCatalog.All.Where(destination => requested.Contains(destination.Id, StringComparer.Ordinal)).ToList();
        if (requested is not null && (destinations.Count == 0 || requested.Any(id => destinations.All(destination => destination.Id != id))))
            throw new ArgumentException("MCPR_SELFTEST_DESTINATIONS names an unknown destination");
        foreach (var destination in destinations)
        {
            _window.SelectDestination(destination.Id);
            await SettleAsync();

            var state = _window.State;
            var png = Path.Combine(_directory, $"destination-{destination.Id}.png");
            var capture = await CaptureAsync(png);

            // The two claims this item makes about every destination, checked here rather than
            // asserted in prose: the title is the board's name, and the board drew something.
            if (state.WindowTitle != destination.Label)
                _failures.Add($"{destination.Id}: window title is '{state.WindowTitle}', expected '{destination.Label}'");
            if (state.BandTitle != destination.Label)
                _failures.Add($"{destination.Id}: caption band reads '{state.BandTitle}', expected '{destination.Label}'");
            if (capture.Width < 200 || capture.Height < 200)
                _failures.Add($"{destination.Id}: capture is {capture.Width}x{capture.Height}, which is not a drawn window");

            _observations.Add(new
            {
                kind = "destination",
                id = destination.Id,
                label = destination.Label,
                windowTitle = state.WindowTitle,
                bandTitle = state.BandTitle,
                actualTheme = state.ActualTheme,
                rasterizationScale = state.RasterizationScale,
                hasMicaBackdrop = state.HasMica,
                destinationCount = state.DestinationCount,
                commandCount = state.CommandCount,
                capture = Path.GetFileName(png),
                captureWidth = capture.Width,
                captureHeight = capture.Height,
            });
        }

        // Both appearances. The system theme is whatever the machine is set to, so these two are
        // FORCED on the root element and are labelled as forced - a capture of the app under a
        // theme the user did not choose is evidence about the palette, not about the following.
        foreach (var theme in new[] { ElementTheme.Light, ElementTheme.Dark })
        {
            _window.RootElement.RequestedTheme = theme;
            _window.SelectDestination(requested is null ? DestinationCatalog.Default.Id : destinations[0].Id);
            await SettleAsync();

            var png = Path.Combine(_directory, $"appearance-{theme.ToString().ToLowerInvariant()}.png");
            var capture = await CaptureAsync(png);

            if (_window.State.ActualTheme != theme.ToString())
                _failures.Add($"forced {theme} did not take: ActualTheme is {_window.State.ActualTheme}");

            _observations.Add(new
            {
                kind = "appearance",
                forcedTheme = theme.ToString(),
                actualTheme = _window.State.ActualTheme,
                capture = Path.GetFileName(png),
                captureWidth = capture.Width,
                captureHeight = capture.Height,
            });
        }

        _window.RootElement.RequestedTheme = ElementTheme.Default;
        await SettleAsync();

        // Back on Default the theme must be the system's again. If it is not, the app has become
        // the authority on a setting Windows owns, which is the thing §3.2 removed the appearance
        // switch to avoid.
        if (_window.RootElement.RequestedTheme != ElementTheme.Default)
            _failures.Add("the root element did not return to ElementTheme.Default");

        var report = new
        {
            tool = "MCPRouter.Shell --selftest",
            takenAt = DateTimeOffset.Now.ToString("O"),
            whatThisHolds =
                "RenderTargetBitmap captures of the XAML tree. It does NOT contain the Mica " +
                "backdrop, which composites below XAML, and it does NOT contain the system " +
                "caption buttons, which are not XAML. Neither claim is evidenced by these files.",
            systemTheme = _window.State.ActualTheme,
            rasterizationScale = _window.State.RasterizationScale,
            destinations = destinations.Count,
            commands = CommandCatalog.All.Count,
            observations = _observations,
            failures = _failures,
        };

        await File.WriteAllTextAsync(
            Path.Combine(_directory, "selftest.json"),
            JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));

        return _failures.Count == 0 ? 0 : 1;
    }

    /// <summary>
    /// Lets the layout and render passes finish before the next capture.
    ///
    /// Two frames rather than one: the first settles the layout the selection change requested,
    /// the second lets the composition of it reach the tree RenderTargetBitmap reads.
    /// </summary>
    private async Task SettleAsync()
    {
        _window.RootElement.UpdateLayout();
        await Task.Delay(120);
        _window.RootElement.UpdateLayout();
        await Task.Delay(120);
    }

    private async Task<(int Width, int Height)> CaptureAsync(string path)
    {
        // Render over an opaque ground rather than over nothing.
        //
        // The shell's own content is deliberately transparent so Mica shows through, and
        // RenderTargetBitmap does not composite Mica - it is below XAML. A capture taken as-is
        // therefore comes back with the navigation pane transparent, and white dark-theme labels
        // over transparent are unreadable in the PNG: the first run of this self-test produced
        // twelve captures in which the selected destination's own label was invisible, which
        // reads as a missing label rather than as a missing backdrop.
        //
        // The ground used is SolidBackgroundFillColorBase, which is not an invented backdrop: it
        // is Mica's own fallback, what Windows draws when transparency is off or the machine is
        // on battery saver, and the ground DESIGN.md §12 states every Windows ratio against.
        _window.SetCaptureGround(true);
        try
        {
            var bitmap = new RenderTargetBitmap();
            await bitmap.RenderAsync(_window.RootElement);

            var pixels = await bitmap.GetPixelsAsync();
            var bytes = new byte[pixels.Length];
            using (var reader = DataReader.FromBuffer(pixels)) reader.ReadBytes(bytes);

            // StorageFile.GetFileFromPathAsync needs the file to exist, so it is created empty
            // first. An unpackaged app reaches an arbitrary path this way without a broker.
            await File.WriteAllBytesAsync(path, Array.Empty<byte>());
            var file = await StorageFile.GetFileFromPathAsync(path);

            using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
            encoder.SetPixelData(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Ignore,
                (uint)bitmap.PixelWidth,
                (uint)bitmap.PixelHeight,
                96, 96,
                bytes);
            await encoder.FlushAsync();

            return (bitmap.PixelWidth, bitmap.PixelHeight);
        }
        finally
        {
            _window.SetCaptureGround(false);
        }
    }
}
