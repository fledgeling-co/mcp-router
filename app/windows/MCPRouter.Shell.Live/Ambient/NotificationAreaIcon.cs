using System;
using System.Runtime.InteropServices;
using MCPRouter.Shell.Model.Settings;

namespace MCPRouter.Shell.Live.Ambient;

/// <summary>
/// The notification-area icon "Show status in notification area" switches, and the only thing in
/// this build that talks to <c>Shell_NotifyIcon</c>.
/// </summary>
/// <remarks>
/// <para>DEF-101: the setting existed, the icon did not. <c>AmbientPresentation.TrayToolTip</c>
/// formatted a string nothing displayed and the Settings row's caption was the only other place
/// the words "notification area" appeared in the build.</para>
///
/// <para><b>Why the icon is registered by GUID.</b> A notification-area icon is identified either
/// by the pair (window handle, id) or by a GUID. The pair is private to this process - nothing
/// outside it can name the window - and an effect only this process can name is an effect only
/// this process can witness, which is the failure the whole item is about. A GUID is a name a
/// DIFFERENT program can hold, so <c>Shell_NotifyIconGetRect</c> called from another process asks
/// the shell whether this icon is there, and the answer comes from the notification area rather
/// than from us. <c>scripts/windows/uia/notification-icon-probe.ps1</c> is that other program.</para>
///
/// <para><b>The window is message-only.</b> A notification-area icon needs a window to send its
/// clicks to, and a hidden top-level window would join the shell's own on the automation plane,
/// where the UIA lane looks for "a top-level window owned by this process". A message-only window
/// (parented to <c>HWND_MESSAGE</c>) is not a top-level window and is not in the accessibility
/// tree at all.</para>
///
/// <para><b>Why the icon comes back by polling rather than by TaskbarCreated</b> (DEF-300). A
/// message-only window receives no broadcast message, so this process is never told that the
/// shell restarted, and an icon dropped by an Explorer restart never came back. The two ways out
/// were a hidden TOP-LEVEL window that can receive <c>TaskbarCreated</c>, or asking the shell
/// whether the icon is still there. The first one gives the fault back to the automation plane:
/// the UIA lane binds to "a top-level window owned by this process", a second one would be a
/// second candidate, and DEF-089 is already the record of what that costs - a run bound to the
/// wrong window and reported eight destinations unreachable and three failures, every one of them
/// a statement about the harness's handle. So the icon is watched instead, with
/// <see cref="Shell_NotifyIconGetRect"/>: the shell's own answer about its own notification area,
/// asked every couple of seconds while the setting is on, and the icon re-added when the answer is
/// no. It costs one call per tick and it needs no window that anything else can mistake for the
/// shell's.</para>
/// </remarks>
public sealed class NotificationAreaIcon
{
    /// <summary>
    /// The icon's name in the shell, and the string the out-of-process probe is pointed at. It is
    /// a constant of the product, not of a run: change it and every witness taken before the
    /// change is about a different icon.
    /// </summary>
    public static readonly Guid IconId = new("0F5B6D3A-8C41-4E2B-9D77-2A6E5C1B4A90");

    /// <summary>The same GUID in the registry-style braces form the probe script takes.</summary>
    public const string IconIdText = "{0F5B6D3A-8C41-4E2B-9D77-2A6E5C1B4A90}";

    private readonly Action? _onActivated;
    private readonly Func<string> _tooltip;

    private IntPtr _window = IntPtr.Zero;
    private WndProcDelegate? _wndProc;   // held alive: the shell calls it from native code
    private string _registeredClass = "";

    /// <summary>Serialises the UI thread's <see cref="Apply"/> against the watchdog's re-add.</summary>
    private readonly object _gate = new();

    /// <summary>Whether the setting says the icon is to be there. The watchdog acts only on this.</summary>
    private bool _wanted;

    private System.Threading.Timer? _watchdog;

    /// <summary>How often the shell is asked whether it still holds the icon.</summary>
    private static readonly TimeSpan WatchInterval = TimeSpan.FromSeconds(2);

    /// <summary>
    /// How many times the watchdog has put the icon back after finding it gone - the count an
    /// Explorer restart moves, and the one the DEF-300 arm reads out of the startup log.
    /// </summary>
    public int RestoredCount { get; private set; }

    /// <param name="tooltip">
    /// What the icon says when hovered. Supplied as a function rather than a string so the caller
    /// can hand it <c>AmbientPresentation.TrayToolTip</c> and the tip follows the router's state
    /// rather than freezing at whatever it was when the icon was placed.
    /// </param>
    /// <param name="onActivated">Run when the icon is clicked. Called on the thread that created
    /// this instance, because that is the thread whose message loop delivers the click.</param>
    public NotificationAreaIcon(Func<string> tooltip, Action? onActivated = null)
    {
        _tooltip = tooltip;
        _onActivated = onActivated;
    }

    /// <summary>The last thing the shell said when it was asked to place or remove the icon.</summary>
    public string LastDetail { get; private set; } = "nothing has been attempted";

    /// <summary>
    /// Whether the notification area holds this icon, asked of the shell rather than remembered.
    /// </summary>
    /// <remarks>
    /// This is a cross-process question even when it is asked from inside this process:
    /// <c>Shell_NotifyIconGetRect</c> is answered by the shell's notification area, not by a field
    /// here. A field would say yes after Explorer had dropped the icon.
    /// </remarks>
    public bool? IsPlaced()
    {
        var identifier = new NOTIFYICONIDENTIFIER
        {
            cbSize = (uint)Marshal.SizeOf<NOTIFYICONIDENTIFIER>(),
            hWnd = IntPtr.Zero,
            uID = 0,
            guidItem = IconId,
        };
        try
        {
            var hr = Shell_NotifyIconGetRect(ref identifier, out _);
            // S_OK and S_FALSE both mean the shell knows the icon; S_FALSE is the answer when it
            // is in the overflow rather than promoted, which is still present.
            if (hr >= 0) return true;
            return false;
        }
        catch (EntryPointNotFoundException)
        {
            return null;
        }
        catch (DllNotFoundException)
        {
            return null;
        }
    }

    /// <summary>Place the icon, or remove it.</summary>
    /// <remarks>
    /// Placing it also arms the watchdog that puts it back after an Explorer restart (DEF-300);
    /// removing it disarms the watchdog first, so a switch driven Off can never race a re-add.
    /// </remarks>
    public bool Apply(bool shown)
    {
        lock (_gate)
        {
            _wanted = shown;
            if (!shown) StopWatchdog();
            var ok = ApplyLocked(shown);
            if (shown && ok) StartWatchdog();
            return ok;
        }
    }

    /// <summary>
    /// Refresh the hover text from the tooltip function, so the tip follows the router's state
    /// instead of freezing at whatever it said when the icon was placed.
    /// </summary>
    /// <returns>False when there is no icon to modify, or the shell refused the change.</returns>
    public bool RefreshTooltip()
    {
        lock (_gate)
        {
            if (!_wanted || _window == IntPtr.Zero) return false;
            var data = NewData(NIF_TIP | NIF_SHOWTIP | NIF_GUID);
            return Shell_NotifyIconW(NIM_MODIFY, ref data);
        }
    }

    // ------------------------------------------------------------------ the watchdog (DEF-300)

    private void StartWatchdog()
    {
        _watchdog ??= new System.Threading.Timer(_ => Watch(), null, WatchInterval, WatchInterval);
    }

    private void StopWatchdog()
    {
        _watchdog?.Dispose();
        _watchdog = null;
    }

    /// <summary>
    /// Re-assert the icon, and place it again if the shell will not take the change.
    /// </summary>
    /// <remarks>
    /// <para><b>It re-asserts rather than asks, and that is a correction.</b> The first version of
    /// this called <see cref="IsPlaced"/> and re-added on a false. Measured 2026-09-03 by
    /// scripts/windows/uia/shell-lane.ps1: <c>Shell_NotifyIconGetRect</c> is not a reliable
    /// question to ask across an Explorer restart. On one run, with NO instance of this
    /// application running at all and the icon's record deleted, a restarted notification area
    /// still answered S_OK for this GUID; on another, with the application running and the icon
    /// placed, it answered 0x80004005 for two minutes. A watchdog whose trigger is that reader
    /// inherits both errors - it sits still while the icon is gone, and it would re-add over an
    /// icon that is there.</para>
    ///
    /// <para><c>NIM_MODIFY</c> has no such problem: it is answered by the shell's accept-or-refuse
    /// on the icon this process owns, which is the same path <c>NIM_ADD</c> takes and the one
    /// DEF-101's arms measure end to end. A refusal means the shell is not carrying this icon, and
    /// the answer to that is to add it. It also carries the current tooltip while it is there, so
    /// the tip follows the router without a second timer.</para>
    /// </remarks>
    private void Watch()
    {
        lock (_gate)
        {
            if (!_wanted || _window == IntPtr.Zero) return;

            var reassert = NewData(NIF_TIP | NIF_SHOWTIP | NIF_GUID);
            if (Shell_NotifyIconW(NIM_MODIFY, ref reassert)) return;

            if (ApplyLocked(true))
            {
                RestoredCount++;
                LastDetail = $"the shell refused a change to this icon, so it was placed again "
                    + $"(restore #{RestoredCount})";
            }
        }
    }

    private bool ApplyLocked(bool shown)
    {
        if (shown)
        {
            if (!EnsureWindow(out var why))
            {
                LastDetail = why;
                return false;
            }
            var data = NewData(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP | NIF_GUID);
            if (!Shell_NotifyIconW(NIM_ADD, ref data))
            {
                // An icon left behind by a process that was killed keeps the GUID, and the shell
                // refuses a second ADD under it. Removing that record and adding once more is the
                // difference between "this build cannot place an icon" and "a previous run of it
                // did not get to clean up".
                var stale = NewData(NIF_GUID);
                Shell_NotifyIconW(NIM_DELETE, ref stale);
                data = NewData(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP | NIF_GUID);
                if (!Shell_NotifyIconW(NIM_ADD, ref data))
                {
                    LastDetail = "the shell refused Shell_NotifyIcon(NIM_ADD), error "
                        + Marshal.GetLastWin32Error();
                    return false;
                }
            }

            var version = NewData(NIF_GUID);
            version.uVersion = NOTIFYICON_VERSION_4;
            Shell_NotifyIconW(NIM_SETVERSION, ref version);
            LastDetail = "the icon was placed in the notification area";
            return true;
        }

        var remove = NewData(NIF_GUID);
        var removed = Shell_NotifyIconW(NIM_DELETE, ref remove);
        LastDetail = removed
            ? "the icon was removed from the notification area"
            : "the shell refused Shell_NotifyIcon(NIM_DELETE), error " + Marshal.GetLastWin32Error();
        return removed;
    }

    /// <summary>
    /// Take the icon down on the way out. Called from the window's Closed handler, because an icon
    /// whose owner has gone lingers in the notification area until Explorer next prunes it - and a
    /// lingering icon is a false yes for anything reading the area afterwards.
    /// </summary>
    public void Dispose()
    {
        Apply(false);
        StopWatchdog();
        if (_window != IntPtr.Zero)
        {
            DestroyWindow(_window);
            _window = IntPtr.Zero;
        }
    }

    // ------------------------------------------------------------------ the window

    private bool EnsureWindow(out string why)
    {
        why = "";
        if (_window != IntPtr.Zero) return true;

        _wndProc = WindowProcedure;
        _registeredClass = "MCPRouterNotificationArea." + Environment.ProcessId;
        var wndClass = new WNDCLASS
        {
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_wndProc),
            hInstance = GetModuleHandleW(null),
            lpszClassName = _registeredClass,
        };
        if (RegisterClassW(ref wndClass) == 0)
        {
            var error = Marshal.GetLastWin32Error();
            // 1410 is ERROR_CLASS_ALREADY_EXISTS, which is not a failure: this instance is being
            // built a second time in one process and the class from the first is still good.
            if (error != 1410)
            {
                why = "the window class could not be registered, error " + error;
                return false;
            }
        }

        _window = CreateWindowExW(
            0, _registeredClass, "MCP Router notification area", 0, 0, 0, 0, 0,
            HWND_MESSAGE, IntPtr.Zero, wndClass.hInstance, IntPtr.Zero);
        if (_window == IntPtr.Zero)
        {
            why = "the message-only window could not be created, error " + Marshal.GetLastWin32Error();
            return false;
        }
        return true;
    }

    private IntPtr WindowProcedure(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (message == TrayCallbackMessage)
        {
            // Under NOTIFYICON_VERSION_4 the mouse message is the low word of lParam.
            var mouse = (uint)((long)lParam & 0xFFFF);
            if (mouse == WM_LBUTTONUP)
            {
                _onActivated?.Invoke();
            }
        }
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }

    private NOTIFYICONDATAW NewData(uint flags)
    {
        var tip = "";
        try { tip = _tooltip() ?? ""; } catch (Exception) { tip = "MCP Router"; }
        if (tip.Length > 127) tip = tip[..127];

        return new NOTIFYICONDATAW
        {
            cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATAW>(),
            hWnd = _window,
            uID = 1,
            uFlags = flags,
            uCallbackMessage = TrayCallbackMessage,
            hIcon = LoadIconW(IntPtr.Zero, (IntPtr)IDI_APPLICATION),
            szTip = tip,
            guidItem = IconId,
        };
    }

    // ------------------------------------------------------------------ the platform

    private const uint NIM_ADD = 0x0;
    private const uint NIM_MODIFY = 0x1;
    private const uint NIM_DELETE = 0x2;
    private const uint NIM_SETVERSION = 0x4;
    private const uint NIF_MESSAGE = 0x1;
    private const uint NIF_ICON = 0x2;
    private const uint NIF_TIP = 0x4;
    private const uint NIF_GUID = 0x20;
    private const uint NIF_SHOWTIP = 0x80;
    private const uint NOTIFYICON_VERSION_4 = 4;
    private const uint TrayCallbackMessage = 0x8000 + 1;  // WM_APP + 1
    private const uint WM_LBUTTONUP = 0x0202;
    private const int IDI_APPLICATION = 32512;
    private static readonly IntPtr HWND_MESSAGE = new(-3);

    private delegate IntPtr WndProcDelegate(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATAW
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState;
        public uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NOTIFYICONIDENTIFIER
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public Guid guidItem;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASS
    {
        public uint style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpszMenuName;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpszClassName;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Shell_NotifyIconW(uint message, ref NOTIFYICONDATAW data);

    [DllImport("shell32.dll")]
    private static extern int Shell_NotifyIconGetRect(ref NOTIFYICONIDENTIFIER identifier, out RECT location);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassW(ref WNDCLASS wndClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(
        uint exStyle, string className, string windowName, uint style,
        int x, int y, int width, int height,
        IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyWindow(IntPtr hwnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr DefWindowProcW(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadIconW(IntPtr instance, IntPtr iconName);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandleW(string? moduleName);
}

/// <summary>
/// What the Settings board's "Show status in notification area" switch owns, as the board sees it.
/// </summary>
/// <remarks>
/// The icon host is process-wide because the notification area is: the shell places its icon at
/// launch from the stored setting, and the Settings board - which is built and thrown away by
/// navigation - must switch THAT icon rather than one of its own. So the host is handed in rather
/// than constructed here.
/// </remarks>
public sealed class NotificationAreaAgent : INotificationAreaAgent
{
    private readonly NotificationAreaIcon _icon;

    public NotificationAreaAgent(NotificationAreaIcon icon)
    {
        _icon = icon;
    }

    /// <summary>Null: this build owns a notification-area host, so the switch can act.</summary>
    public string? UnavailableReason => null;

    public bool? CurrentlyShown() => _icon.IsPlaced();

    public ToggleEffectResult Apply(bool shown)
    {
        var applied = _icon.Apply(shown);
        return new ToggleEffectResult(
            applied ? ToggleEffectOutcome.Applied : ToggleEffectOutcome.Failed,
            _icon.LastDetail);
    }
}
