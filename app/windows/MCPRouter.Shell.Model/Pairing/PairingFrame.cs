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

    /// <summary>
    /// Reason names as §2.4's table spells them. Reads and writes share this one table, so a name cannot be
    /// spelt one way on the way out and another on the way in.
    /// </summary>
    private static readonly IReadOnlyDictionary<PairingWireReason, string> ReasonNames =
        new Dictionary<PairingWireReason, string>
        {
            [PairingWireReason.NotRecognised] = "notRecognised",
            [PairingWireReason.Expired] = "expired",
            [PairingWireReason.AlreadyUsed] = "alreadyUsed",
            [PairingWireReason.Declined] = "declined",
            [PairingWireReason.UnsupportedVersion] = "unsupportedVersion",
            [PairingWireReason.BadRequest] = "badRequest",
            [PairingWireReason.FrameTooLarge] = "frameTooLarge",
            [PairingWireReason.TypedEntryUnavailable] = "typedEntryUnavailable",
        };

    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        // A field a message does not carry is absent from the frame, not written as null: the peer reads
        // "present" as "the sender meant it", and §2.4 lists only the keys each message uses.
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    /// <summary>The frame bytes for a message: the length prefix, then the body.</summary>
    public static byte[] Encode(PairingMessage message)
    {
        var body = JsonSerializer.SerializeToUtf8Bytes(ToWire(message), WriteOptions);
        if (body.Length > MaxBodyLength) throw Fail(new PairingFrameError.Oversized(body.Length));

        var frame = new byte[4 + body.Length];
        BinaryPrimitives.WriteUInt32BigEndian(frame, (uint)body.Length);
        body.CopyTo(frame, 4);
        return frame;
    }

    /// <summary>Reads one whole frame. Throws <see cref="PairingFrameException"/> with the failure named.</summary>
    public static PairingMessage Decode(byte[] frame)
    {
        var length = BodyLength(frame);
        var body = frame.AsSpan(4);
        if (body.Length < length) throw Fail(new PairingFrameError.Truncated());
        if (body.Length != length) throw Fail(new PairingFrameError.Malformed("bytes after the frame"));

        Wire? wire;
        try
        {
            wire = JsonSerializer.Deserialize<Wire>(body);
        }
        catch (JsonException)
        {
            throw Fail(new PairingFrameError.Malformed("body is not a pairing message"));
        }
        if (wire is null) throw Fail(new PairingFrameError.Malformed("body is not a pairing message"));

        // The version is checked before the message, so a frame from a newer peer is named as one,
        // whatever else it carries. A missing type or version is malformed, not a version refusal.
        if (wire.Type is null || wire.V is null) throw Fail(new PairingFrameError.Malformed("missing type or v"));
        if (!SupportedVersions.Contains(wire.V.Value)) throw Fail(new PairingFrameError.UnsupportedVersion(wire.V.Value));

        return FromWire(wire.Type, wire);
    }

    /// <summary>The wire string for a refusal reason, as §2.4's table spells it.</summary>
    public static string ReasonName(PairingWireReason reason) => ReasonNames[reason];

    // ------------------------------------------------------------------ the length prefix

    /// <summary>
    /// The body length the four-byte prefix announces. Read as unsigned, so a prefix with its top bit set is
    /// oversized rather than a negative length that passes the limit.
    /// </summary>
    private static int BodyLength(byte[] frame)
    {
        if (frame.Length < 4) throw Fail(new PairingFrameError.Truncated());
        var length = BinaryPrimitives.ReadUInt32BigEndian(frame);
        if (length > MaxBodyLength) throw Fail(new PairingFrameError.Oversized(length));
        return (int)length;
    }

    private static PairingFrameException Fail(PairingFrameError error) => new(error);

    // ------------------------------------------------------------------ messages to and from the wire

    /// <summary>
    /// Every field the four messages use, each optional where a message does not carry it. A missing required
    /// field is a named failure in <see cref="FromWire"/>, not a decoding default.
    /// </summary>
    internal sealed class Wire
    {
        [JsonPropertyName("type")] public string? Type { get; set; }
        [JsonPropertyName("v")] public int? V { get; set; }
        [JsonPropertyName("code")] public string? Code { get; set; }
        [JsonPropertyName("phoneName")] public string? PhoneName { get; set; }
        [JsonPropertyName("phoneKey")] public string? PhoneKey { get; set; }
        [JsonPropertyName("entry")] public string? Entry { get; set; }
        [JsonPropertyName("macName")] public string? MacName { get; set; }
        [JsonPropertyName("phoneId")] public string? PhoneId { get; set; }
        [JsonPropertyName("reason")] public string? Reason { get; set; }
        [JsonPropertyName("found")] public int? Found { get; set; }
    }

    private static Wire ToWire(PairingMessage message) => message switch
    {
        PairingRequest request => new Wire
        {
            Type = "pair.request",
            V = Version,
            Code = RequireCode(request.Code),
            PhoneName = request.PhoneName,
            PhoneKey = Convert.ToBase64String(request.PhoneKey),
            Entry = "scan",
        },
        PairingOk ok => new Wire { Type = "pair.ok", V = Version, MacName = ok.MacName, PhoneId = ok.PhoneId },
        PairingRefused refused => new Wire
        {
            Type = "pair.refused",
            V = Version,
            Reason = ReasonName(refused.Reason),
            Found = refused.Reason == PairingWireReason.UnsupportedVersion ? refused.Found : null,
        },
        PairingAck ack => new Wire { Type = "pair.ack", V = Version, PhoneId = ack.PhoneId },
        _ => throw new ArgumentOutOfRangeException(nameof(message), message, "not a pairing message"),
    };

    private static PairingMessage FromWire(string type, Wire wire) => type switch
    {
        "pair.request" => Request(wire),
        "pair.ok" => new PairingOk(Required(wire.MacName, "macName"), Required(wire.PhoneId, "phoneId")),
        "pair.refused" => Refused(wire),
        "pair.ack" => new PairingAck(Required(wire.PhoneId, "phoneId")),
        _ => throw Fail(new PairingFrameError.UnknownType(type)),
    };

    private static PairingRequest Request(Wire wire)
    {
        var code = RequireCode(wire.Code);
        var key = RequireKey(wire.PhoneKey);
        RequireEntry(wire.Entry);
        return new PairingRequest(code, Required(wire.PhoneName, "phoneName"), key);
    }

    private static PairingRefused Refused(Wire wire)
    {
        var reason = ReasonFrom(Required(wire.Reason, "reason"));
        if (reason != PairingWireReason.UnsupportedVersion) return new PairingRefused(reason);

        var found = wire.Found ?? throw Fail(new PairingFrameError.Malformed("missing found"));
        return new PairingRefused(reason, found);
    }

    private static PairingWireReason ReasonFrom(string text) =>
        ReasonNames.Where(pair => pair.Value == text).Select(pair => (PairingWireReason?)pair.Key).FirstOrDefault()
        ?? throw Fail(new PairingFrameError.Malformed("unknown refusal reason"));

    /// <summary>The code in wire form. Uppercase Crockford with no separator, compared exactly, so a lower-case or
    /// hyphenated code is malformed rather than normalised.</summary>
    private static string RequireCode(string? text) =>
        text is not null && PairingCodeFormat.IsWellFormed(text)
            ? text
            : throw Fail(new PairingFrameError.Malformed("code is not eight Crockford characters"));

    private static byte[] RequireKey(string? text)
    {
        var encoded = Required(text, "phoneKey");
        try
        {
            return Convert.FromBase64String(encoded);
        }
        catch (FormatException)
        {
            throw Fail(new PairingFrameError.Malformed("phoneKey is not base64"));
        }
    }

    /// <summary><c>entry</c> says how the code was typed in. The phone sends <c>scan</c>; the router refuses <c>typed</c> by name.</summary>
    private static void RequireEntry(string? text)
    {
        if (Required(text, "entry") is not ("scan" or "typed"))
        {
            throw Fail(new PairingFrameError.Malformed("entry is not scan or typed"));
        }
    }

    private static string Required(string? value, string field) =>
        value ?? throw Fail(new PairingFrameError.Malformed($"missing {field}"));
}
