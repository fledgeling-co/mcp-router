using System;

namespace MCPRouter.Shell.Model.Packaging;

public static class PackagingPresentation
{
    public const string PackageIdentity = "Fledgeling.MCPRouter";
    public const string PublisherIdentity = "CN=Fledgeling";

    public const string SmartScreenNotice = "Unsigned developer builds trigger Windows SmartScreen warnings on first launch. Official releases are code-signed and distributed via winget.";

    public const string UninstallGuidance = @"Uninstalling removes the client binaries while preserving %USERPROFILE%\.claude\mcp-router configuration and credentials unless explicitly purged.";

    public static string ChannelLabel(DistributionChannel channel)
    {
        return channel switch
        {
            DistributionChannel.Winget => "Windows Package Manager (winget)",
            DistributionChannel.DirectMsix => "MSIX Bundle",
            DistributionChannel.ZipPortable => "Portable ZIP Archive",
            _ => channel.ToString()
        };
    }
}
