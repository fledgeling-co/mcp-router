<#
.SYNOPSIS
  Asks the Windows shell whether MCP Router's notification-area icon is there. DEF-101's recorder.

.DESCRIPTION
  This script is deliberately not part of the application. DEF-101 is a setting that reached
  nothing, and a fix for it read back through the app's own handle would be the same defect with a
  larger surface: a process reporting its own effect. So the icon is registered by GUID - a name
  something else can hold - and this script calls Shell_NotifyIconGetRect with that GUID from its
  own process. The answer comes from the shell's notification area, which is neither the writer
  nor a copy of the writer's memory.

  -Delete removes the icon by the same GUID. That is not a measurement and it is not used to make
  an arm pass: it exists so a lane whose previous run was killed before it could tidy up can clear
  a stale record and then take a baseline that means something, rather than reading a dead
  process's leftovers as a live icon.

  Prints one JSON object on stdout. `found` is the answer; `hresult` is what the shell actually
  returned, so a failure that is not "no such icon" can be told apart from one that is.

  Exit 0 the question was asked and answered - INCLUDING when the answer is "no icon".
  Exit 2 the question could not be asked at all.
#>
param(
    [string] $IconGuid = '{0F5B6D3A-8C41-4E2B-9D77-2A6E5C1B4A90}',
    [switch] $Delete
)

$ErrorActionPreference = 'Continue'

$source = @'
using System;
using System.Runtime.InteropServices;

public static class NotificationAreaProbe
{
    [StructLayout(LayoutKind.Sequential)]
    public struct NOTIFYICONIDENTIFIER
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public Guid guidItem;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct NOTIFYICONDATAW
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

    [DllImport("shell32.dll")]
    private static extern int Shell_NotifyIconGetRect(ref NOTIFYICONIDENTIFIER id, out RECT rect);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern bool Shell_NotifyIconW(uint message, ref NOTIFYICONDATAW data);

    public static int Ask(Guid icon, out int left, out int top, out int right, out int bottom)
    {
        NOTIFYICONIDENTIFIER id = new NOTIFYICONIDENTIFIER();
        id.cbSize = (uint)Marshal.SizeOf(typeof(NOTIFYICONIDENTIFIER));
        id.guidItem = icon;
        RECT rect;
        int hr = Shell_NotifyIconGetRect(ref id, out rect);
        left = rect.Left; top = rect.Top; right = rect.Right; bottom = rect.Bottom;
        return hr;
    }

    public static bool Remove(Guid icon)
    {
        NOTIFYICONDATAW data = new NOTIFYICONDATAW();
        data.cbSize = (uint)Marshal.SizeOf(typeof(NOTIFYICONDATAW));
        data.uFlags = 0x20;   // NIF_GUID
        data.guidItem = icon;
        data.szTip = "";
        data.szInfo = "";
        data.szInfoTitle = "";
        return Shell_NotifyIconW(2, ref data);   // NIM_DELETE
    }
}
'@

try {
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
} catch {
    Write-Output ('{{"asked": false, "why": {0}}}' -f (ConvertTo-Json $_.Exception.Message))
    exit 2
}

$guid = [guid] $IconGuid

if ($Delete) {
    $removed = [NotificationAreaProbe]::Remove($guid)
    Write-Output ("{{`"deleted`": {0}}}" -f $removed.ToString().ToLowerInvariant())
    exit 0
}

$left = 0; $top = 0; $right = 0; $bottom = 0
$hr = [NotificationAreaProbe]::Ask($guid, [ref] $left, [ref] $top, [ref] $right, [ref] $bottom)

# S_OK and S_FALSE both mean the shell holds the icon. S_FALSE is the answer when it is in the
# overflow rather than promoted to the taskbar, and an icon in the overflow is still an icon.
$found = ($hr -ge 0)

[pscustomobject]@{
    asked   = $true
    found   = $found
    hresult = ('0x{0:X8}' -f $hr)
    rect    = @{ left = $left; top = $top; right = $right; bottom = $bottom }
    guid    = $IconGuid
    reader  = 'Shell_NotifyIconGetRect, called from ' + [System.Diagnostics.Process]::GetCurrentProcess().ProcessName + ' pid ' + $PID
} | ConvertTo-Json -Compress

exit 0
