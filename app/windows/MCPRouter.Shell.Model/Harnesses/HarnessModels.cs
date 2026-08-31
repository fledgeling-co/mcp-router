using System;
using System.Collections.Generic;

namespace MCPRouter.Shell.Model.Harnesses;

public enum HarnessReading
{
    NotRouted,
    RoutedOverHTTP,
    RoutedViaShim,
    RoutedWithDirectServers
}

public enum HarnessTransport
{
    None,
    Http,
    StdioShim
}

public sealed record HarnessDuplicate(
    string HarnessName,
    string RouterName,
    string Basis
);

public sealed record DetectedHarness(
    string Harness,
    string DisplayName,
    string Path,
    bool Exists,
    HarnessReading State,
    HarnessTransport Route,
    int Entries,
    int DuplicateCount,
    IReadOnlyList<HarnessDuplicate> Duplicates,
    string HttpCapability,
    string? Unreadable = null,
    string? Bridge = null
);
