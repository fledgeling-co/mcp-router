using System;

namespace MCPRouter.Shell.Model.Packaging;

public enum DistributionChannel
{
    Winget,
    DirectMsix,
    ZipPortable
}

public sealed record PackagingContract(
    string PackageName,
    string Publisher,
    string Version,
    DistributionChannel Channel,
    bool IsSmartScreenCompliant,
    string UninstallBehaviorDescription
);
