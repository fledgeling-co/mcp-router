using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security;
using System.Text;

namespace MCPRouter.Shell.Model.Notifications;

/// <summary>What a viewer did to a toast, once the arguments have been read back.</summary>
/// <remarks>
/// A record and not a bare <see cref="ToastActionKind"/> because the action alone is not enough to
/// act on. "Open the review sheet" without knowing WHICH capability is a navigation to a list, and
/// the whole point of the notification is that the operator is being told about one specific thing
/// that arrived.
/// </remarks>
public sealed record ToastInvocation(ToastActionKind Action, string CapabilityId);

/// <summary>
/// The toast's wire format: a payload rendered to AppNotification XML, and the arguments a click
/// hands back read into an invocation.
/// </summary>
/// <remarks>
/// WHY THIS IS IN THE MODEL PROJECT AND NOT BESIDE THE NOTIFIER. DEF-072 found WIN22 shipping a
/// payload record, a builder for it, and a test asserting the builder built it - with no toast
/// anywhere, because `AppNotificationManager` and `ToastNotificationManager` had zero hits in
/// product source. The correction is not only to call the platform, but to put the part that can
/// be WRONG somewhere a test can reach without a display: the XML a click will be interpreted
/// against, and the interpretation itself. The reference machine cannot host a XAML window from
/// the session that runs the gates, so a claim checkable only against a running window is a claim
/// nothing here checks - the same reasoning that split this project out in WIN3.
///
/// THE SAFETY RULE IS STRUCTURAL HERE, not a sentence. NotificationPresentation.ToastSafetyRule
/// says "no toast action installs, approves or grants anything directly", and WIN22's test asserted
/// that the sentence contained its own words. What enforces it is <see cref="Parse"/>: the only
/// actions that can come back out are OpenReviewSheet and Dismiss, an unrecognised action returns
/// null rather than a default, and there is no encoding for an approve. A future edit that adds an
/// "Install" button has to add it here, in front of the tests that assert the closed set.
/// </remarks>
public static class ToastPayloadCodec
{
    /// <summary>The scheme prefix every toast argument string carries.</summary>
    /// <remarks>
    /// Prefixed so an argument string that did not come from this codec is refused rather than
    /// misread. Windows hands back whatever string the notification carried, including one written
    /// by an older version of this application still sitting in the Action Center across an
    /// upgrade, and a parser that read a bare `action=...` would act on it.
    /// </remarks>
    public const string Scheme = "mcprouter-toast";

    public const string ActionKey = "action";
    public const string CapabilityKey = "capability";

    private const string OpenReviewSheetToken = "open-review-sheet";
    private const string DismissToken = "dismiss";

    /// <summary>The closed set, and the reason Parse can refuse.</summary>
    private static readonly IReadOnlyDictionary<string, ToastActionKind> Actions =
        new Dictionary<string, ToastActionKind>(StringComparer.Ordinal)
        {
            [OpenReviewSheetToken] = ToastActionKind.OpenReviewSheet,
            [DismissToken] = ToastActionKind.Dismiss,
        };

    public static string TokenFor(ToastActionKind action) => action switch
    {
        ToastActionKind.OpenReviewSheet => OpenReviewSheetToken,
        ToastActionKind.Dismiss => DismissToken,
        // Not a default token. A new member of the enum must be given a wire token deliberately,
        // and until it is, encoding it is a bug this throws on rather than a toast that comes back
        // as something else.
        _ => throw new ArgumentOutOfRangeException(
            nameof(action), action, "this action has no toast wire token"),
    };

    /// <summary>The argument string a button carries, and which comes back on a click.</summary>
    public static string Arguments(ToastActionKind action, string capabilityId) =>
        string.Format(
            CultureInfo.InvariantCulture,
            "{0}://invoke?{1}={2}&{3}={4}",
            Scheme, ActionKey, TokenFor(action), CapabilityKey, Uri.EscapeDataString(capabilityId ?? ""));

    /// <summary>Read an argument string back, or null if it did not come from this codec.</summary>
    /// <remarks>
    /// NULL AND NOT A DEFAULT. Windows delivers the arguments of whatever notification was clicked,
    /// and this process does not control what is sitting in the Action Center - a toast from a
    /// previous build, a toast from a different application activating the same COM server. A
    /// parser that fell back to OpenReviewSheet would navigate on a string it did not understand;
    /// one that fell back to anything that acts would be the defect the safety rule names.
    /// </remarks>
    public static ToastInvocation? Parse(string? arguments)
    {
        if (string.IsNullOrWhiteSpace(arguments))
        {
            return null;
        }
        var prefix = Scheme + "://invoke?";
        if (!arguments!.StartsWith(prefix, StringComparison.Ordinal))
        {
            return null;
        }

        string? action = null;
        var capability = "";
        foreach (var pair in arguments[prefix.Length..].Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var split = pair.Split('=', 2);
            if (split.Length != 2)
            {
                continue;
            }
            if (split[0] == ActionKey)
            {
                action = split[1];
            }
            else if (split[0] == CapabilityKey)
            {
                capability = Uri.UnescapeDataString(split[1]);
            }
        }

        if (action is null || !Actions.TryGetValue(action, out var kind))
        {
            return null;
        }
        return new ToastInvocation(kind, capability);
    }

    /// <summary>Render the payload to the AppNotification XML the platform takes.</summary>
    /// <remarks>
    /// Two buttons and no others, because the toast is a pointer and never a control surface:
    /// "Review..." carries OpenReviewSheet and "Dismiss" carries Dismiss, and neither argument
    /// string has an encoding for installing, approving or granting. That is what makes
    /// ToastSafetyRule a property of the wire rather than a sentence in a constant.
    ///
    /// The body says what has NOT happened - "Nothing has been installed" comes from
    /// NotificationPresentation.ForQueuedItem - and it is on the toast rather than only in the app
    /// because the Action Center is where an operator reads it at a glance, possibly hours later,
    /// and a notification that only says something arrived invites the reading that something was
    /// done.
    /// </remarks>
    public static string BuildXml(ToastNotificationPayload payload)
    {
        if (payload is null)
        {
            throw new ArgumentNullException(nameof(payload));
        }

        var launch = Arguments(payload.PrimaryAction, payload.CapabilityId);
        var builder = new StringBuilder();
        builder.Append("<toast launch=\"").Append(Escape(launch)).Append("\" activationType=\"foreground\">");
        builder.Append("<visual><binding template=\"ToastGeneric\">");
        builder.Append("<text>").Append(Escape(payload.Title)).Append("</text>");
        builder.Append("<text>").Append(Escape(payload.Body)).Append("</text>");
        builder.Append("</binding></visual>");
        builder.Append("<actions>");
        AppendAction(builder, NotificationPresentation.ReviewActionLabel,
            Arguments(ToastActionKind.OpenReviewSheet, payload.CapabilityId), "foreground");
        AppendAction(builder, NotificationPresentation.DismissActionLabel,
            Arguments(ToastActionKind.Dismiss, payload.CapabilityId), "background");
        builder.Append("</actions>");
        builder.Append("</toast>");
        return builder.ToString();
    }

    private static void AppendAction(StringBuilder builder, string content, string arguments, string activation)
    {
        builder.Append("<action content=\"").Append(Escape(content))
               .Append("\" arguments=\"").Append(Escape(arguments))
               .Append("\" activationType=\"").Append(activation).Append("\" />");
    }

    /// <summary>The set of actions a toast this codec builds can possibly come back as.</summary>
    /// <remarks>
    /// Exposed so a test can assert the set rather than assert two members of it. An "Install"
    /// button added to BuildXml without being added to the enum and to Actions would leave this
    /// unchanged and fail the round-trip test instead of passing quietly.
    /// </remarks>
    public static IReadOnlyCollection<ToastActionKind> EncodableActions =>
        Actions.Values.Distinct().ToArray();

    private static string Escape(string value) => SecurityElement.Escape(value ?? "") ?? "";
}
