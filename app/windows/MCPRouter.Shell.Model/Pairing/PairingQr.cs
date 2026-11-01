using System.Text.Json;
using QRCoder;

namespace MCPRouter.Shell.Model.Pairing;

public static class PairingQr
{
    public static bool HasEndpoint(PairingListenerState listener) => listener.Enabled
        && listener.Port is >= 1 and <= 65535
        && !string.IsNullOrWhiteSpace(listener.Host) && !listener.Host.Any(char.IsControl)
        && listener.Fingerprint is { Length: 64 } fp && fp.All(char.IsAsciiHexDigit);

    public static string Encode(IssuedPairingCode code, PairingListenerState listener, string computerName)
    {
        if (!HasEndpoint(listener)) throw new ArgumentException("The router did not report a usable listener endpoint.");
        return JsonSerializer.Serialize(new
        {
            t = "mcp-router-pair", v = 1, code = code.Code, mac = computerName,
            exp = code.ExpiresAt.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            host = listener.Host, port = listener.Port, fp = listener.Fingerprint,
        });
    }

    public static byte[] RenderPng(string payload)
    {
        using var data = QRCodeGenerator.GenerateQrCode(payload, QRCodeGenerator.ECCLevel.M);
        using var png = new PngByteQRCode(data);
        return png.GetGraphic(6);
    }
}
