using System.Buffers.Binary;
using System.Text;
using MCPRouter.Shell.Model.Pairing;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The parts of the §2.4 contract the shared vectors do not pin: every refusal reason the table names, the
/// length prefix read as unsigned, the code's wire format on both paths, and what a printed request reveals.
/// </summary>
public sealed class PairingFrameTests
{
    [Theory]
    [InlineData("notRecognised", PairingWireReason.NotRecognised)]
    [InlineData("expired", PairingWireReason.Expired)]
    [InlineData("alreadyUsed", PairingWireReason.AlreadyUsed)]
    [InlineData("declined", PairingWireReason.Declined)]
    [InlineData("badRequest", PairingWireReason.BadRequest)]
    [InlineData("frameTooLarge", PairingWireReason.FrameTooLarge)]
    [InlineData("typedEntryUnavailable", PairingWireReason.TypedEntryUnavailable)]
    public void ARefusalReasonTheContractNamesDecodesToItsReason(string wire, PairingWireReason reason)
    {
        var message = PairingFrame.Decode(Prefixed($"{{\"type\":\"pair.refused\",\"v\":1,\"reason\":\"{wire}\"}}"));

        Assert.Equal(new PairingRefused(reason), message);
        Assert.Equal(wire, PairingFrame.ReasonName(reason));
    }

    [Fact]
    public void ALengthPrefixAboveTheSignedRangeIsOversizedNotNegative()
    {
        var frame = new byte[] { 0xFF, 0xFF, 0xFF, 0xFF, (byte)'{', (byte)'}' };

        var refused = Assert.Throws<PairingFrameException>(() => PairingFrame.Decode(frame));

        Assert.Equal(new PairingFrameError.Oversized(4294967295L), refused.Error);
    }

    [Theory]
    [InlineData("k7qn4fmb")]
    [InlineData("K7QN-4FMB")]
    [InlineData("K7QN4FM")]
    [InlineData("K7QN4FMU")]
    public void ADecodedRequestCodeOutsideTheWireFormatIsMalformed(string code)
    {
        var frame = Prefixed(
            $"{{\"type\":\"pair.request\",\"v\":1,\"code\":\"{code}\",\"phoneName\":\"p\",\"phoneKey\":\"AA==\",\"entry\":\"scan\"}}");

        var refused = Assert.Throws<PairingFrameException>(() => PairingFrame.Decode(frame));

        Assert.IsType<PairingFrameError.Malformed>(refused.Error);
    }

    [Fact]
    public void AnEncodedRequestCodeOutsideTheWireFormatIsRefused()
    {
        var refused = Assert.Throws<PairingFrameException>(
            () => PairingFrame.Encode(new PairingRequest("k7qn4fmb", "p", [1])));

        Assert.IsType<PairingFrameError.Malformed>(refused.Error);
    }

    [Fact]
    public void APrintedRequestDoesNotCarryItsCode()
    {
        var request = new PairingRequest("K7QN4FMB", "Phone", [1]);

        Assert.DoesNotContain("K7QN4FMB", request.ToString());
    }

    [Fact]
    public void AnEncodedBodyOverTheLimitIsOversized()
    {
        var refused = Assert.Throws<PairingFrameException>(
            () => PairingFrame.Encode(new PairingOk(new string('m', 5000), "p")));

        Assert.IsType<PairingFrameError.Oversized>(refused.Error);
    }

    [Fact]
    public void TheMessagesWithoutKeyBytesSurviveAnEncodeAndDecode()
    {
        var messages = new PairingMessage[]
        {
            new PairingOk("Luke's MacBook Pro", "phone-1"),
            new PairingRefused(PairingWireReason.Expired),
            new PairingRefused(PairingWireReason.UnsupportedVersion, 2),
            new PairingAck("phone-1"),
        };

        foreach (var message in messages)
        {
            Assert.Equal(message, PairingFrame.Decode(PairingFrame.Encode(message)));
        }
    }

    [Fact]
    public void FoundIsWrittenOnlyWithUnsupportedVersion()
    {
        var refused = Encoding.UTF8.GetString(PairingFrame.Encode(new PairingRefused(PairingWireReason.NotRecognised)));

        Assert.DoesNotContain("found", refused);
    }

    private static byte[] Prefixed(string json)
    {
        var body = Encoding.UTF8.GetBytes(json);
        var frame = new byte[4 + body.Length];
        BinaryPrimitives.WriteUInt32BigEndian(frame, (uint)body.Length);
        body.CopyTo(frame, 4);
        return frame;
    }
}
