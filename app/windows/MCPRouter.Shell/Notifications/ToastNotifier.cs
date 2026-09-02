using System;
using System.Runtime.InteropServices;
using MCPRouter.Shell.Model.Notifications;
using Microsoft.Windows.AppNotifications;

namespace MCPRouter.Shell.Notifications;

/// <summary>
/// The platform half of WIN22: the AppUserModelID, the COM activator registration, raising a
/// toast, and turning a click on it into a navigation.
/// </summary>
/// <remarks>
/// WHY THIS EXISTS. DEF-072 found WIN22's "Action Center toast notifications" to be three files
/// totalling 62 lines - a payload record, a builder, and a test asserting the builder built the
/// record - with `AppNotificationManager` and `ToastNotificationManager` at zero hits in product
/// source. No toast could reach the Action Center, under a ledger row reading "621 tests green,
/// Action Center toast notifications".
///
/// THREE THINGS HAVE TO BE TRUE for an unpackaged Win32 application to raise a toast that survives
/// its own process, and the item shipped none of them:
///
///   1. AN EXPLICIT AppUserModelID. Without one Windows derives an identity from the process, and
///      the notification is attributed to whatever it derives - which changes when the executable
///      moves. SetCurrentProcessExplicitAppUserModelID is called BEFORE Register, because the
///      registration is written under the identity in force at the time.
///   2. THE COM ACTIVATOR. A toast outlives the process that raised it. When somebody presses a
///      button an hour later, Windows COM-activates the registered LocalServer32 for the CLSID it
///      finds under that AUMID. Without it the toast still appears and pressing it does nothing,
///      which is the failure that looks most like success.
///   3. A HANDLER THAT REFUSES WHAT IT DOES NOT UNDERSTAND. See ToastPayloadCodec.Parse.
///
/// AppNotificationManager.Register() performs (2) for an unpackaged app by writing HKCU: an
/// AppUserModelId key carrying a CustomActivator CLSID, and that CLSID's LocalServer32 pointing at
/// this executable. That registry state is what
/// scripts/windows/win22-toast-witness.ps1 reads back - through the registry rather than through
/// this class - and it is the only part of WIN22 an independent recorder on this host can see.
///
/// WHAT IS STILL NOT WITNESSED, said here rather than left to a green: that a toast actually lands
/// in the Action Center, and that a click on it re-activates this process. Enumerating the Action
/// Center needs UserNotificationListener, whose capability is only grantable to a packaged app, and
/// this one is `WindowsPackageType=None`. DEF-082 carries that.
/// </remarks>
internal sealed class ToastNotifier : IDisposable
{
    /// <summary>The identity the Action Center attributes these notifications to.</summary>
    /// <remarks>
    /// Explicit and stable. A derived id changes when the executable moves, and every notification
    /// raised under the old one becomes unattributable - so an operator who moves the install
    /// directory finds the toasts in their Action Center suddenly belong to nothing.
    /// </remarks>
    internal const string AppUserModelId = "Fledgeling.MCPRouter.Shell";

    private readonly Action<ToastInvocation> _onInvoked;
    private AppNotificationManager? _manager;
    private bool _registered;

    internal ToastNotifier(Action<ToastInvocation> onInvoked)
    {
        _onInvoked = onInvoked ?? throw new ArgumentNullException(nameof(onInvoked));
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SetCurrentProcessExplicitAppUserModelID(
        [MarshalAs(UnmanagedType.LPWStr)] string appId);

    /// <summary>Claim the identity, wire the handler, and register the activator.</summary>
    /// <returns>true when the platform accepted the registration.</returns>
    /// <remarks>
    /// Returns rather than throws, and the caller logs the false. A shell that refused to open
    /// because notifications could not be registered would trade a missing convenience for a
    /// missing application - and the conditions that make this fail (no Windows App SDK runtime
    /// resolved, a session with no notification platform) are exactly the ones where the operator
    /// most needs the rest of the window.
    /// </remarks>
    internal bool Register()
    {
        try
        {
            // Order matters: the AUMID must be in force before Register writes the registration
            // under it, or the activator lands under the derived identity instead.
            SetCurrentProcessExplicitAppUserModelID(AppUserModelId);

            _manager = AppNotificationManager.Default;
            _manager.NotificationInvoked += OnNotificationInvoked;
            _manager.Register();
            _registered = true;
            return true;
        }
        catch (Exception exception) when (exception is COMException or TypeLoadException
                                              or DllNotFoundException or InvalidOperationException)
        {
            StartupLog.Write($"toast registration failed: {exception}");
            _registered = false;
            return false;
        }
    }

    /// <summary>Raise a toast for one queued capability.</summary>
    /// <returns>true when the platform accepted it; false when nothing was raised.</returns>
    internal bool Show(ToastNotificationPayload payload)
    {
        if (!_registered || _manager is null)
        {
            // Not an exception, and not silent either. Showing a toast through an unregistered
            // manager produces a notification whose buttons cannot activate anything, which is
            // strictly worse than no notification: the operator is told to press Review and
            // pressing it does nothing.
            StartupLog.Write("toast not shown: the notification manager is not registered");
            return false;
        }
        try
        {
            _manager.Show(new AppNotification(ToastPayloadCodec.BuildXml(payload)));
            return true;
        }
        catch (Exception exception) when (exception is COMException or ArgumentException)
        {
            StartupLog.Write($"toast not shown: {exception}");
            return false;
        }
    }

    private void OnNotificationInvoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args)
    {
        // Read through the codec, never off the raw arguments, so an unrecognised string is
        // refused here rather than defaulting into a navigation. See ToastPayloadCodec.Parse: this
        // process does not control what sits in the Action Center.
        var invocation = ToastPayloadCodec.Parse(args.Argument);
        if (invocation is null)
        {
            StartupLog.Write($"toast invoked with arguments this build does not recognise: {args.Argument}");
            return;
        }
        StartupLog.Write($"toast invoked: {invocation.Action} for '{invocation.CapabilityId}'");
        _onInvoked(invocation);
    }

    public void Dispose()
    {
        if (_manager is null)
        {
            return;
        }
        _manager.NotificationInvoked -= OnNotificationInvoked;
        if (_registered)
        {
            try
            {
                // Unregistering leaves the HKCU keys in place - it stops this PROCESS receiving
                // activations. That is deliberate on the platform's part: a toast already in the
                // Action Center must still be able to launch the app after it has exited.
                _manager.Unregister();
            }
            catch (COMException exception)
            {
                StartupLog.Write($"toast unregister failed: {exception}");
            }
        }
        _registered = false;
        _manager = null;
    }
}
