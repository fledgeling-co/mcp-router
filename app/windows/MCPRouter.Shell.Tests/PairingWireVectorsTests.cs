using System.Buffers.Binary;
using System.Text;
using System.Text.Json.Nodes;
using MCPRouter.Shell.Model.Pairing;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The Windows side of the shared pairing wire vectors (<c>planning/pairing/wire-vectors.json</c>, plan §2.4),
/// mirroring <c>app/Tests/MCPRouterKitTests/PairingWireVectorsTests.swift</c>. The router reads the same file in
/// <c>test/pairing-listener.test.ts</c>.
///
/// A vector is checked here only where it names a phone expectation: <c>decodes</c> or <c>error</c> for a frame a
/// client receives, <c>encodes</c> for a frame a client sends. A vector with no phone expectation is the router's
/// to refuse.
/// </summary>
public sealed class PairingWireVectorsTests
{
    private static readonly JsonObject Root =
        JsonNode.Parse(RepoRoot.Read("planning/pairing/wire-vectors.json"))!.AsObject();

    public static TheoryData<string> PhoneDecodeVectors() => Cases(PhoneDecodeNames());

    public static TheoryData<string> PhoneEncodeVectors() => Cases(PhoneEncodeNames());

    [Fact]
    public void TheVectorFileHasEveryPairingFrameAndTheSideEachNames()
    {
        var frames = Frames().ToList();
        Assert.Equal(27, frames.Count);
        foreach (var frame in frames)
        {
            Assert.True(Expect(frame, "router") is not null || Expect(frame, "phone") is not null, Name(frame));
        }
        Assert.Equal(20, PhoneDecodeNames().Count());
        Assert.Equal(2, PhoneEncodeNames().Count());
    }

    [Theory]
    [MemberData(nameof(PhoneDecodeVectors))]
    public void EveryFrameThePhoneReceivesDecodesOrIsRefusedAsItsVectorSays(string name)
    {
        var vector = Frame(name);
        var phone = Expect(vector, "phone")!;
        var bytes = WireBytes(vector);

        if (phone["error"] is { } error)
        {
            var refused = Assert.Throws<PairingFrameException>(() => PairingFrame.Decode(bytes));
            Assert.Equal(ExpectedError(error.GetValue<string>(), phone), ErrorLabel(refused.Error));
        }
        else
        {
            Assert.Equal(ExpectedLabel(phone), MessageLabel(PairingFrame.Decode(bytes)));
        }
    }

    [Theory]
    [MemberData(nameof(PhoneEncodeVectors))]
    public void EveryFrameThePhoneSendsIsTheFrameItsVectorGivesFieldForField(string name)
    {
        var vector = Frame(name);
        var expected = JsonNode.Parse(Substituted(vector));

        var frame = PairingFrame.Encode(Message(expected!.AsObject()));

        Assert.Equal((uint)(frame.Length - 4), BinaryPrimitives.ReadUInt32BigEndian(frame));
        var sent = JsonNode.Parse(Encoding.UTF8.GetString(frame, 4, frame.Length - 4));
        Assert.True(JsonNode.DeepEquals(expected, sent), $"{name} encoded {sent?.ToJsonString()}");
    }

    [Fact]
    public void TheCommittedCertificateRendersTheFingerprintTheVectorsCarry()
    {
        var fingerprint = Root["fingerprint"]!.AsObject();
        var expected = fingerprint["sha256"]!.GetValue<string>();
        var der = CertificateDer(RepoRoot.Read(fingerprint["certificate"]!.GetValue<string>()));

        Assert.Equal(expected, PairingFingerprint.Render(der));
        Assert.Matches("^[0-9a-f]{64}$", expected);
    }

    // ------------------------------------------------------------------ the vector file

    private static IEnumerable<JsonObject> Frames() =>
        Root["frames"]!.AsArray().Select(node => node!.AsObject())
            // Inbox frames use their own codec on the phone and router. Windows reads the loopback inbox routes.
            .Where(frame => frame["channel"]?.GetValue<string>() != "inbox");

    private static IEnumerable<string> PhoneDecodeNames() =>
        Frames().Where(vector => Expect(vector, "phone") is { } phone && (phone.ContainsKey("error") || phone.ContainsKey("decodes")))
            .Select(Name);

    private static IEnumerable<string> PhoneEncodeNames() =>
        Frames().Where(vector => Expect(vector, "phone")?.ContainsKey("encodes") == true).Select(Name);

    private static TheoryData<string> Cases(IEnumerable<string> names)
    {
        var cases = new TheoryData<string>();
        foreach (var name in names) cases.Add(name);
        return cases;
    }

    private static JsonObject Frame(string name) => Frames().Single(vector => Name(vector) == name);

    private static string Name(JsonObject vector) => vector["name"]!.GetValue<string>();

    /// <summary>A side's expectation, or null when the vector does not name one for that side.</summary>
    private static JsonObject? Expect(JsonObject vector, string side) => vector["expect"]?[side]?.AsObject();

    /// <summary>The body with <c>{{code}}</c> and <c>{{phoneId}}</c> replaced by the fixed placeholder values.</summary>
    private static string Substituted(JsonObject vector)
    {
        var text = vector["body"]!.ToJsonString();
        foreach (var (key, value) in Root["placeholders"]!.AsObject())
        {
            text = text.Replace("{{" + key + "}}", value!.GetValue<string>());
        }
        return text;
    }

    /// <summary>The bytes a vector puts on the wire: the length prefix, the body, then any trailing bytes.</summary>
    private static byte[] WireBytes(JsonObject vector)
    {
        var payload = vector["rawBody"] is { } raw
            ? Encoding.UTF8.GetBytes(raw.GetValue<string>())
            : Encoding.UTF8.GetBytes(Substituted(vector));
        var declared = vector["declaredLength"] is { } length ? length.GetValue<int>() : payload.Length;
        var trailing = Encoding.UTF8.GetBytes(vector["trailing"]?.GetValue<string>() ?? string.Empty);

        var frame = new byte[4 + payload.Length + trailing.Length];
        BinaryPrimitives.WriteUInt32BigEndian(frame, (uint)declared);
        payload.CopyTo(frame, 4);
        trailing.CopyTo(frame, 4 + payload.Length);
        return frame;
    }

    /// <summary>The message a phone builds from a request or ack body.</summary>
    private static PairingMessage Message(JsonObject body) => body["type"]!.GetValue<string>() switch
    {
        "pair.request" => new PairingRequest(
            body["code"]!.GetValue<string>(),
            body["phoneName"]!.GetValue<string>(),
            Convert.FromBase64String(body["phoneKey"]!.GetValue<string>())),
        "pair.ack" => new PairingAck(body["phoneId"]!.GetValue<string>()),
        var other => throw new InvalidOperationException($"the phone does not send {other}"),
    };

    // ------------------------------------------------------------------ labels

    private static string ExpectedError(string name, JsonObject phone) =>
        phone["type"] is { } type ? $"{name}:{type.GetValue<string>()}"
        : phone["found"] is { } found ? $"{name}:{found.GetValue<int>()}"
        : name;

    private static string ExpectedLabel(JsonObject phone)
    {
        var label = phone["decodes"]!.GetValue<string>();
        if (phone["reason"] is { } reason) label += ":" + reason.GetValue<string>();
        if (phone["found"] is { } found) label += ":" + found.GetValue<int>();
        return label;
    }

    private static string ErrorLabel(PairingFrameError error) => error switch
    {
        PairingFrameError.Oversized => "oversized",
        PairingFrameError.Truncated => "truncated",
        PairingFrameError.Malformed => "malformed",
        PairingFrameError.UnknownType unknown => "unknownType:" + unknown.Type,
        PairingFrameError.UnsupportedVersion version => "unsupportedVersion:" + version.Found,
        _ => throw new InvalidOperationException($"no label for {error}"),
    };

    private static string MessageLabel(PairingMessage message) => message switch
    {
        PairingRequest => "pair.request",
        PairingOk => "pair.ok",
        PairingRefused refused => "pair.refused:" + (refused.Reason == PairingWireReason.UnsupportedVersion
            ? "unsupportedVersion:" + refused.Found
            : PairingFrame.ReasonName(refused.Reason)),
        PairingAck => "pair.ack",
        _ => throw new InvalidOperationException($"no label for {message}"),
    };

    /// <summary>The DER body of a PEM certificate: the base64 between the BEGIN and END lines.</summary>
    private static byte[] CertificateDer(string pem)
    {
        var base64 = string.Concat(pem.Split('\n').Where(line => !line.StartsWith("-----", StringComparison.Ordinal)));
        return Convert.FromBase64String(base64);
    }
}
