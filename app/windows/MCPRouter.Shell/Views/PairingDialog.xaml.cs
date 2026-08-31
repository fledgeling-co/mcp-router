using System;
using MCPRouter.Shell.Model.Pairing;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

public sealed partial class PairingDialog : UserControl
{
    private readonly PairingSessionModel _model = new();

    public PairingDialog()
    {
        InitializeComponent();
        UpdateUI();
    }

    private void UpdateUI()
    {
        PairingCodeText.Text = _model.CurrentState.PairingCode;
        ExpiresText.Text = PairingPresentation.ExpiresIn(_model.CurrentState.RemainingTime);
    }
}
