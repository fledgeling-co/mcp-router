namespace MCPRouter.Shell.Model.Harnesses;

/// <summary>
/// How a harness reaches this router: one of four readings, never a boolean. The router's
/// <c>state</c> word for each is mapped in <see cref="HarnessPresentation.ReadingOf"/>, and the
/// mapping is total over the words the wire admits.
/// </summary>
public enum HarnessReading
{
    NotRouted,
    RoutedOverHTTP,
    RoutedViaShim,
    RoutedWithDirectServers
}
