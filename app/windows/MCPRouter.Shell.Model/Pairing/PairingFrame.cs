using System.Buffers.Binary;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MCPRouter.Shell.Model.Pairing;

/// <summary>The messages on the pairing listener. Nothing else is accepted on it (plan §2.4).</summary>
public abstract record PairingMessage;

/// <summary>Phone to router. <see cref="PhoneKey"/> is the SubjectPublicKeyInfo DER of the phone's P-256 key.</summary>
public sealed record PairingRequest(string Code, string PhoneName, byte[] PhoneKey) : PairingMessage
{
    /// <summary>Never the code itself. A code is a credential for the window it is alive, and a description
    /// that printed it would put it in every log line that interpolated the value.</summary>
    public override string ToString() => "PairingRequest(<redacted>)";
}

/// <summary>Router to phone, once the code is accepted and the pending record is written.</summary>
public sealed record PairingOk(string MacName, string PhoneId) : PairingMessage;

/// <summary>Router to phone, when the request is refused. <see cref="Found"/> is set only with
/// <see cref="PairingWireReason.UnsupportedVersion"/>: the <c>v</c> the router was sent.</summary>
public sealed record PairingRefused(PairingWireReason Reason, int? Found = null) : PairingMessage;

/// <summary>Phone to router, once the phone has stored its record. Confirms the router's pending record.</summary>
public sealed record PairingAck(string PhoneId) : PairingMessage;

/// <summary>The <c>reason</c> a <c>pair.refused</c> frame carries (plan §2.4). The router's own vocabulary.</summary>
public enum PairingWireReason
{
    NotRecognised,
    Expired,
    AlreadyUsed,
    /// <summary>Reserved: the router never sends it, because only the Mac's user declines.</summary>
    Declined,
    UnsupportedVersion,
    BadRequest,
    FrameTooLarge,
    TypedEntryUnavailable
}

/// <summary>What a frame failed on. Kept apart so a size limit is never reported as a parse error.</summary>
public abstract record PairingFrameError
{
    public sealed record Oversized(long Length) : PairingFrameError;

    public sealed record Truncated : PairingFrameError;

    public sealed record Malformed(string Detail) : PairingFrameError;

    public sealed record UnknownType(string Type) : PairingFrameError;

    public sealed record UnsupportedVersion(int Found) : PairingFrameError;
}

/// <summary>A frame that could not be read or written. The <see cref="Error"/> names what it failed on.</summary>
public sealed class PairingFrameException(PairingFrameError error) : Exception(error.ToString())
{
    public PairingFrameError Error { get; } = error;
}

/// <summary>Four-byte big-endian length, then UTF-8 JSON (plan §2.4).</summary>
public static class PairingFrame
{
    /// <summary>The largest body accepted in either direction.</summary>
    public const int MaxBodyLength = 4096;

    /// <summary>The version this build writes.</summary>
    public const int Version = 1;

    /// <summary>The versions this build reads. The phone's <c>PairingPayload.supportedVersions</c> is the same set.</summary>
    public static IReadOnlySet<int> SupportedVersions { get; } = new HashSet<int> { Version };

    /// <summary>The frame bytes for a message: the length prefix, then the body.</summary>
    public static byte[] Encode(PairingMessage message) => throw new NotImplementedException("B9: the frame encoder");

    /// <summary>Reads one whole frame. Throws <see cref="PairingFrameException"/> with the failure named.</summary>
    public static PairingMessage Decode(byte[] frame) => throw new NotImplementedException("B9: the frame decoder");

    /// <summary>The wire string for a refusal reason, as §2.4's table spells it.</summary>
    public static string ReasonName(PairingWireReason reason) => throw new NotImplementedException("B9: reason names");
}
