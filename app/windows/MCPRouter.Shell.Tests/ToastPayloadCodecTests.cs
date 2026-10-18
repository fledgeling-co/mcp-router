using System;
using System.Linq;
using System.Xml.Linq;
using MCPRouter.Shell.Model.Notifications;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The toast's wire format, on both sides of the trip: what the platform is handed, and what comes
/// back when somebody presses a button.
/// </summary>
/// <remarks>
/// DEF-072's finding was that WIN22's entire suite asserted a builder built the record it returned.
/// Nothing here does that. Every test either parses the XML the platform will parse, or drives an
/// argument string back through the reader that will read it on a real click, or asserts a closed
/// set that a careless addition would open.
/// </remarks>
public sealed class ToastPayloadCodecTests
{
    private static ToastNotificationPayload Payload() =>
        NotificationPresentation.ForQueuedItem("postgres-mcp", "Luke's iPhone", "postgres-mcp");

    private static XElement Toast() => XDocument.Parse(ToastPayloadCodec.BuildXml(Payload())).Root!;

    [Fact]
    public void BuildXml_IsWellFormedAndIsAToast()
    {
        var toast = Toast();

        Assert.Equal("toast", toast.Name.LocalName);
        Assert.Equal("foreground", (string?)toast.Attribute("activationType"));
    }

    [Fact]
    public void BuildXml_CarriesTheTitleAndTheDidNotHappenLine()
    {
        var texts = Toast().Descendants("text").Select(t => t.Value).ToArray();

        Assert.Contains("postgres-mcp is waiting for review", texts);

        // The body is on the TOAST and not only in the app, because the Action Center is where an
        // operator reads this at a glance, possibly hours later. A notification that says only that
        // something arrived invites the reading that something was done.
        Assert.Contains(texts, t => t.Contains("Nothing has been installed", StringComparison.Ordinal));
    }

    [Fact]
    public void BuildXml_OffersExactlyReviewAndDismiss()
    {
        var actions = Toast().Descendants("action").ToArray();

        Assert.Equal(2, actions.Length);
        Assert.Equal(
            new[] { NotificationPresentation.ReviewActionLabel, NotificationPresentation.DismissActionLabel },
            actions.Select(a => (string?)a.Attribute("content")).ToArray());
    }

    [Fact]
    public void BuildXml_NoActionCanEncodeAnythingThatActs()
    {
        // THE SAFETY RULE, AS A PROPERTY OF THE WIRE. ToastSafetyRule says no toast action
        // installs, approves or grants anything directly, and WIN22 tested that claim by asserting
        // the sentence contained its own words. This asserts it of the document: every argument
        // string a button carries is parsed back through the real reader, and each one resolves to
        // a member of the closed set. A button added with an "install" argument fails here, and it
        // fails whether or not anybody remembered to update the sentence.
        foreach (var action in Toast().Descendants("action"))
        {
            var parsed = ToastPayloadCodec.Parse((string?)action.Attribute("arguments"));
            Assert.NotNull(parsed);
            Assert.Contains(parsed!.Action, ToastPayloadCodec.EncodableActions);
        }

        Assert.Equal(
            new[] { ToastActionKind.OpenReviewSheet, ToastActionKind.Dismiss }.OrderBy(a => a),
            ToastPayloadCodec.EncodableActions.OrderBy(a => a));
    }

    [Fact]
    public void ReviewAction_RoundTripsToTheReviewSheetAndTheCapabilityItIsAbout()
    {
        // The whole claim of WIN22, in one assertion: a click on Review comes back as "open the
        // review sheet, for THIS capability". Without the capability travelling, the action is a
        // navigation to a list, and the operator has to find the item the toast was about.
        var review = Toast().Descendants("action")
            .First(a => (string?)a.Attribute("content") == NotificationPresentation.ReviewActionLabel);

        var parsed = ToastPayloadCodec.Parse((string?)review.Attribute("arguments"));

        Assert.NotNull(parsed);
        Assert.Equal(ToastActionKind.OpenReviewSheet, parsed!.Action);
        Assert.Equal("postgres-mcp", parsed.CapabilityId);
    }

    [Fact]
    public void DismissAction_RoundTripsToDismissAndActivatesInTheBackground()
    {
        var dismiss = Toast().Descendants("action")
            .First(a => (string?)a.Attribute("content") == NotificationPresentation.DismissActionLabel);

        Assert.Equal("background", (string?)dismiss.Attribute("activationType"));
        Assert.Equal(ToastActionKind.Dismiss, ToastPayloadCodec.Parse((string?)dismiss.Attribute("arguments"))!.Action);
    }

    [Fact]
    public void BodyOfTheToastActivatesTheSameWayTheReviewButtonDoes()
    {
        // Clicking the toast itself, rather than a button, delivers the `launch` attribute. An
        // operator who taps the notification body expects what the primary button does, and a
        // launch string that parsed to nothing would leave that click doing nothing at all.
        var launch = (string?)Toast().Attribute("launch");

        var parsed = ToastPayloadCodec.Parse(launch);
        Assert.Equal(ToastActionKind.OpenReviewSheet, parsed!.Action);
        Assert.Equal("postgres-mcp", parsed.CapabilityId);
    }

    // ------------------------------------------------------------------ the reader's refusals

    [Theory]
    [InlineData(null, "nothing at all")]
    [InlineData("", "an empty string")]
    [InlineData("action=open-review-sheet&capability=x", "the bare form, with no scheme")]
    [InlineData("other-app://invoke?action=open-review-sheet", "another application's scheme")]
    [InlineData("mcprouter-toast://invoke?capability=x", "our scheme with no action")]
    [InlineData("mcprouter-toast://invoke?action=install&capability=x", "an action outside the closed set")]
    public void Parse_RefusesRatherThanDefaulting(string? arguments, string why)
    {
        // NULL AND NOT A DEFAULT, and the last row is the one that matters. This process does not
        // control what sits in the Action Center - a toast from a previous build, a toast from
        // another application activating the same COM server - and Windows hands back whatever
        // string the clicked notification carried. A reader that fell back to OpenReviewSheet would
        // navigate on a string it did not understand; one that fell back to anything that ACTS
        // would be the defect ToastSafetyRule names, arriving through the parser.
        Assert.True(ToastPayloadCodec.Parse(arguments) is null, why);
    }

    [Fact]
    public void Arguments_SurviveACapabilityIdCarryingSeparators()
    {
        // An id holding & or = would otherwise split the query and be read as a second field. Ids
        // are not this code's to choose, so this is escaping the parser must undo rather than a
        // shape that cannot arrive.
        var arguments = ToastPayloadCodec.Arguments(ToastActionKind.OpenReviewSheet, "weird&id=1 2");

        Assert.Equal("weird&id=1 2", ToastPayloadCodec.Parse(arguments)!.CapabilityId);
    }

    [Fact]
    public void BuildXml_EscapesAPayloadThatWouldOtherwiseBreakTheDocument()
    {
        // The title carries a capability name, which arrives from a pairing device and is not this
        // code's to choose. An unescaped one produces XML the platform refuses, and the toast
        // simply never appears - a silent failure at exactly the moment the operator is being told
        // something needs their attention.
        var payload = new ToastNotificationPayload(
            "a & b <script>", "body \" with ' quotes", "iPhone", "cap&1");

        var toast = XDocument.Parse(ToastPayloadCodec.BuildXml(payload)).Root!;

        Assert.Contains("a & b <script>", toast.Descendants("text").Select(t => t.Value));
        Assert.Equal("cap&1", ToastPayloadCodec.Parse((string?)toast.Attribute("launch"))!.CapabilityId);
    }

    [Fact]
    public void TokenFor_RefusesAnEnumMemberNobodyGaveAWireToken()
    {
        // Guards the direction a new action actually arrives from: somebody adds a member to
        // ToastActionKind, and every switch that silently defaults makes it behave as one of the
        // existing ones. This throws instead, at the point of encoding, with the member named.
        Assert.Throws<ArgumentOutOfRangeException>(
            () => ToastPayloadCodec.TokenFor((ToastActionKind)999));
    }
}
