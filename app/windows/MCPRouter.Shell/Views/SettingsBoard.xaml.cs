using System;
using MCPRouter.Shell.Model.Settings;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

public sealed partial class SettingsBoard : UserControl
{
    private readonly SettingsBoardModel _model = new();

    public SettingsBoard()
    {
        InitializeComponent();
    }
}
