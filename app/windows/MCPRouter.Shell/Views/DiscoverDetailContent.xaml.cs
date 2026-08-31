using MCPRouter.Shell.Model.Registry;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The content of the Discover detail dialog - the dialog itself is created by
/// <see cref="DiscoverDetailDialog" />, which supplies the title and the two buttons around this
/// view. The requirement fields are built here because they are dynamic: one field per entry the
/// install block asks for, a <see cref="PasswordBox" /> for a secret and a <see cref="TextBox" />
/// for anything else.
/// </summary>
public sealed partial class DiscoverDetailContent : UserControl
{
    private readonly RegistryEntry _entry;
    private readonly Dictionary<string, string> _values = new(StringComparer.Ordinal);

    public DiscoverDetailContent(RegistryEntry entry)
    {
        InitializeComponent();
        _entry = entry;
        Render();
    }

    private void Render()
    {
        var statement = RegistryCapability.StatementFor(_entry);

        NameText.Text = RegistryText.Sanitize(_entry.DisplayName, cap: 80);
        ProvenanceText.Text = RegistryPresentation.ProvenanceSentenceFor(_entry) ?? "";

        if (RegistryPresentation.FigureFor(_entry) is { } figure)
        {
            FigureText.Text = figure.Text;
            ToolTipService.SetToolTip(FigureText, figure.Attribution);
            FigureText.Visibility = Visibility.Visible;
        }

        if (RegistryPresentation.DateCellFor(_entry) is { } date)
        {
            DateText.Text = date.Text;
            DateText.Visibility = Visibility.Visible;
        }

        if (RegistryPresentation.ArchivedNoteFor(_entry) is { } archived)
        {
            // The word carries the meaning; the colour only underlines it (section 12: on
            // Windows the caution and critical hues are near-identical in luminance, so colour
            // is never the only channel).
            ArchivedText.Text = archived;
            ArchivedText.Visibility = Visibility.Visible;
        }

        DescriptionText.Text = RegistryText.Sanitize(_entry.Description, cap: 500);

        StatementHeadline.Text = statement.Headline;
        StatementBody.Text = statement.Body;
        ArgvList.ItemsSource = statement.Argv;
        DerivationNote.Text = DiscoverCopy.StatementDerivationNote;

        BuildRequirementFields();
    }

    private void BuildRequirementFields()
    {
        var requirements = _entry.Install?.Requires;
        if (requirements is null || requirements.Count == 0) return;

        RequirementsPanel.Visibility = Visibility.Visible;
        if (RegistryCapability.RequirementSummaryFor(_entry) is { } summary)
        {
            RequirementsSummary.Text = summary;
        }

        SecretDestinationNote.Text = DiscoverCopy.SecretDestination;

        foreach (var requirement in requirements)
        {
            var label = RegistryText.Sanitize(requirement.Name, cap: 40);
            var help = RegistryText.Sanitize(requirement.Description ?? "", cap: 120);
            if ((requirement.IsSecret ?? false))
            {
                var secret = new PasswordBox { Header = label };
                AutomationProperties.SetName(secret, label);
                if (help.Length > 0) ToolTipService.SetToolTip(secret, help);
                secret.PasswordChanged += (_, args) =>
                {
                    _values[RegistryText.Sanitize(requirement.Name)] = secret.Password;
                };
                RequirementFields.Children.Add(secret);
            }
            else
            {
                var field = new TextBox { Header = label };
                AutomationProperties.SetName(field, label);
                if (help.Length > 0) ToolTipService.SetToolTip(field, help);
                field.TextChanged += (_, _) =>
                {
                    _values[RegistryText.Sanitize(requirement.Name)] = field.Text;
                };
                RequirementFields.Children.Add(field);
            }
        }
    }

    /// <summary>Re-renders the Add decision after the fields have been revealed. Called by the
    /// dialog when the ellipsis click lands.</summary>
    public void ShowBlockedReason(string reason)
    {
        BlockedReasonText.Text = reason;
        BlockedReasonText.Visibility = Visibility.Visible;
    }

    public void ShowError(string message)
    {
        ErrorText.Text = message;
        ErrorText.Visibility = Visibility.Visible;
    }

    public void ClearError()
    {
        ErrorText.Text = "";
        ErrorText.Visibility = Visibility.Collapsed;
    }

    public IReadOnlyDictionary<string, string> Values => _values;
}
