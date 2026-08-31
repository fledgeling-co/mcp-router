using MCPRouter.Shell.Model.Registry;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The detail surface a row opens - the only place in the entire board where an Add exists
/// (spec-WIN7 section 3: one tap from a gameable ranking to executing someone's code is the
/// affordance an adversary wants, so the row carries no action but this opening).
///
/// The Add is the dialog's primary button: leftmost, accent-filled, the one Enter fires -
/// the Windows "do it" position (DESIGN.md section 11 rule 4) - with Close, the safe action,
/// rightmost. Every disabled state dims in place with its reason in the content beside the
/// button, and an ellipsis on the label means the click reveals the requirement fields rather
/// than committing.
///
/// The install itself is the real boundary: the model performs the token-authenticated
/// <c>POST /servers</c>, and <c>force</c> does not exist in the declaration type. A refusal
/// leaves the dialog open with the router's message beside the button - the row is not marked
/// installed, because nothing was.
/// </summary>
public sealed class DiscoverDetailDialog
{
    private readonly DiscoverBoardModel _model;
    private readonly RegistryEntry _entry;
    private readonly Action<string> _onInstalled;
    private readonly XamlRoot _xamlRoot;

    public DiscoverDetailDialog(DiscoverBoardModel model, RegistryEntry entry, XamlRoot xamlRoot, Action<string> onInstalled)
    {
        _model = model;
        _entry = entry;
        _xamlRoot = xamlRoot;
        _onInstalled = onInstalled;
    }

    public async Task ShowAsync()
    {
        var content = new DiscoverDetailContent(_entry);
        var action = RegistryCapability.ActionFor(_entry);
        var requirementsRevealed = false;
        var installing = false;

        var dialog = new ContentDialog
        {
            Title = RegistryText.Sanitize(_entry.DisplayName, cap: 80),
            Content = content,
            CloseButtonText = DiscoverCopy.DetailCloseAction,
            // The primary (accent) button is the default, so Enter commits - and a commit is
            // only ever reachable through the states the content explains.
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = _xamlRoot,
        };

        dialog.PrimaryButtonText = action.Label;
        dialog.IsPrimaryButtonEnabled = action.IsEnabled;
        if (action.DisabledReason is { } reason && action.Kind != RegistryCapability.ActionKind.NoInstall)
        {
            content.ShowBlockedReason(reason);
        }

        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            try
            {
                // First click with an unrevealed requirement set reveals the fields instead of
                // committing: the ellipsis promised a further view, and this is it.
                var current = RegistryCapability.ActionFor(_entry, installing, requirementsRevealed, content.Values);
                if (current.RevealsRequirements)
                {
                    requirementsRevealed = true;
                    args.Cancel = true;
                    dialog.PrimaryButtonText = RegistryCapability.ActionFor(
                        _entry, isInstalling: installing, requirementsRevealed: true, values: content.Values).Label;
                    return;
                }

                if (current.Kind == RegistryCapability.ActionKind.MissingRequirements)
                {
                    args.Cancel = true;
                    content.ShowBlockedReason(current.DisabledReason ?? "");
                    return;
                }

                var declaration = RegistryCapability.DeclarationFor(_entry, content.Values);
                if (declaration is null)
                {
                    args.Cancel = true;
                    content.ShowBlockedReason(DiscoverCopy.NoInstallDisabledReason);
                    return;
                }

                installing = true;
                dialog.IsPrimaryButtonEnabled = false;
                dialog.PrimaryButtonText = DiscoverCopy.AddActionInstalling;
                content.ClearError();

                var result = await _model.AddAsync(declaration);
                if (result.Ok)
                {
                    // Installed is mutated from the router's own answer, never optimistically -
                    // a refusal must leave the row saying what is true, which is that nothing
                    // was added.
                    _onInstalled(_entry.Id);
                    dialog.Hide();
                    return;
                }

                // A refusal keeps the dialog open with the reason beside the button, and the
                // button returns to what it was: nothing was added, so nothing may read as if
                // it had been.
                installing = false;
                dialog.IsPrimaryButtonEnabled = true;
                dialog.PrimaryButtonText = RegistryCapability.ActionFor(
                    _entry, isInstalling: false, requirementsRevealed: true, values: content.Values).Label;
                content.ShowError(result.Failure switch
                {
                    { Kind: RegistryClient.AddFailureKind.Unauthorized } => DiscoverCopy.InstallUnauthorizedBody,
                    { Kind: RegistryClient.AddFailureKind.NoToken } => DiscoverCopy.InstallUnauthorizedBody,
                    { Kind: RegistryClient.AddFailureKind.AlreadyDeclared, RouterMessage: { } m } => m,
                    { Kind: RegistryClient.AddFailureKind.IndexFailed, RouterMessage: { } m } =>
                        DiscoverCopy.InstallFailedBody.Replace("{reason}", m, StringComparison.Ordinal),
                    { Kind: RegistryClient.AddFailureKind.Invalid, RouterMessage: { } m } => m,
                    { Kind: RegistryClient.AddFailureKind.RouterUnreachable } =>
                        DiscoverCopy.ReasonText(DiscoverCopy.FailureReason.Transport),
                    _ => DiscoverCopy.InstallFailedHeadline,
                });
                args.Cancel = true;
            }
            finally
            {
                deferral.Complete();
            }
        };

        await dialog.ShowAsync();
    }
}
