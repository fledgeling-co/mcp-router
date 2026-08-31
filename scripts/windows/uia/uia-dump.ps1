<#
.SYNOPSIS
  WIN20 — read a Windows surface's UI Automation tree, out of process, without foregrounding it.

.DESCRIPTION
  This is the campaign's Windows channel. On macOS the campaign reads the accessibility plane; on
  Windows the equivalent is UI Automation, and unlike the Mac lane it is queryable from another
  process, so a surface can be enumerated while it sits behind whatever the user is doing.

  WHAT THIS SCRIPT WILL NOT DO, because the acceptance turns on it:

    · it never calls SetForegroundWindow, AutomationElement.SetFocus, Invoke, Toggle, Select,
      Expand or any other pattern METHOD. Every pattern here is read for its current state only.
    · it samples GetForegroundWindow() before the walk, at the midpoint, and after, and records
      all three with the target's own HWND beside them, so the "never foregrounded" claim is a
      measurement in the artifact rather than a promise in a comment.

  The invariant asserted downstream is "the TARGET never came to the front", not "the foreground
  never changed" — a distinction this repository already paid for once
  (planning/evidence/M34-oracle-lane.md: a check that cried wolf when frontmost went from Chrome
  to ghostty, neither of them the app under test).

  ONE HARD REQUIREMENT: Windows PowerShell 5.1, not PowerShell 7+.
  System.Windows.Automation ships with .NET Framework and has no .NET 5+ counterpart, so `pwsh`
  cannot load it. The script refuses to run rather than half-running.

.PARAMETER ProcessId
  The process whose top-level windows are walked.

.PARAMETER TitleContains
  Alternative to -ProcessId: match a top-level window by a substring of its name.

.PARAMETER Out
  Path for the JSON dump.

.PARAMETER MaxDepth
  Depth guard. A provider that loops would otherwise walk forever.

.PARAMETER MaxElements
  Element guard, same reason.

.PARAMETER View
  Control (default) or Raw. The control view is what a screen reader and the campaign see. The raw
  view is every provider node including the presentational scaffolding, and is worth a second dump
  when something expected is missing: an element absent from BOTH views is not realised at all,
  which is a different finding from one the control view merely hides.

.OUTPUTS
  Exit 0  a tree was read and written.
  Exit 3  NO VERDICT — the target could not be found, or has no readable window. This is not a
          failure of the surface; it is the harness saying it measured nothing.
  Exit 1  the harness itself failed.
#>
[CmdletBinding()]
param(
    [int]    $ProcessId = 0,
    [string] $TitleContains = '',
    [Parameter(Mandatory = $true)][string] $Out,
    [int]    $MaxDepth = 40,
    [int]    $MaxElements = 5000,
    [ValidateSet('Control', 'Raw')][string] $View = 'Control'
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------- host check
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host "NO VERDICT: this script needs Windows PowerShell 5.1. System.Windows.Automation is"
    Write-Host "            a .NET Framework assembly and PowerShell $($PSVersionTable.PSVersion)"
    Write-Host "            ($($PSVersionTable.PSEdition)) cannot load it. Run it with powershell.exe."
    exit 3
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -Namespace Win20 -Name Native -MemberDefinition @'
    [DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(System.IntPtr h, out int pid);
'@

function Get-ForegroundSample {
    param([string] $When)
    $h = [Win20.Native]::GetForegroundWindow()
    $fpid = 0
    [void][Win20.Native]::GetWindowThreadProcessId($h, [ref] $fpid)
    [pscustomobject]@{ when = $When; hwnd = [int64]$h; processId = $fpid }
}

# ----------------------------------------------------------------- pattern reads
# Every entry is a READ. Nothing here changes the surface, which is what makes a dump repeatable
# and what keeps the harness out of the "the test moved the thing it measured" class.
function Read-PatternState {
    param([System.Windows.Automation.AutomationElement] $El)

    $state = [ordered]@{}
    $patterns = New-Object System.Collections.Generic.List[string]

    foreach ($p in $El.GetSupportedPatterns()) { $patterns.Add([string]$p.ProgrammaticName) }

    $try = {
        param($PatternId, $Body)
        $obj = $null
        if ($El.TryGetCurrentPattern($PatternId, [ref] $obj)) { & $Body $obj }
    }

    & $try ([System.Windows.Automation.TogglePattern]::Pattern) {
        param($p) $state['toggleState'] = $p.Current.ToggleState.ToString()
    }
    & $try ([System.Windows.Automation.SelectionItemPattern]::Pattern) {
        param($p) $state['isSelected'] = [bool]$p.Current.IsSelected
    }
    & $try ([System.Windows.Automation.SelectionPattern]::Pattern) {
        param($p)
        $state['canSelectMultiple'] = [bool]$p.Current.CanSelectMultiple
        $sel = New-Object System.Collections.Generic.List[string]
        foreach ($s in $p.Current.GetSelection()) { $sel.Add([string]$s.Current.Name) }
        $state['selection'] = $sel.ToArray()
    }
    & $try ([System.Windows.Automation.RangeValuePattern]::Pattern) {
        param($p)
        $state['rangeValue']    = [double]$p.Current.Value
        $state['rangeMinimum']  = [double]$p.Current.Minimum
        $state['rangeMaximum']  = [double]$p.Current.Maximum
        $state['rangeReadOnly'] = [bool]$p.Current.IsReadOnly
    }
    & $try ([System.Windows.Automation.ValuePattern]::Pattern) {
        param($p)
        $state['value']         = [string]$p.Current.Value
        $state['valueReadOnly'] = [bool]$p.Current.IsReadOnly
    }
    & $try ([System.Windows.Automation.ExpandCollapsePattern]::Pattern) {
        param($p) $state['expandCollapseState'] = $p.Current.ExpandCollapseState.ToString()
    }

    # @() is load-bearing. `$list | Sort-Object` unrolls to a bare string when the list holds one
    # item, and ConvertTo-Json then writes a JSON string where every other row has a JSON array —
    # so a consumer iterating "patterns" would iterate the CHARACTERS of a single pattern name and
    # see plausible nonsense rather than an error. Measured on the first dump of this probe.
    return @{ patterns = @($patterns | Sort-Object); state = $state }
}

function Read-Element {
    param(
        [System.Windows.Automation.AutomationElement] $El,
        [int] $Depth,
        [string] $Path
    )

    $c = $El.Current
    $rect = $c.BoundingRectangle
    $ps = Read-PatternState -El $El

    [ordered]@{
        depth               = $Depth
        path                = $Path
        automationId        = [string]$c.AutomationId
        name                = [string]$c.Name
        controlType         = $c.ControlType.ProgrammaticName -replace '^ControlType\.', ''
        localizedControlType= [string]$c.LocalizedControlType
        className           = [string]$c.ClassName
        frameworkId         = [string]$c.FrameworkId
        isEnabled           = [bool]$c.IsEnabled
        isOffscreen         = [bool]$c.IsOffscreen
        isKeyboardFocusable = [bool]$c.IsKeyboardFocusable
        hasKeyboardFocus    = [bool]$c.HasKeyboardFocus
        isContentElement    = [bool]$c.IsContentElement
        isControlElement    = [bool]$c.IsControlElement
        accessKey           = [string]$c.AccessKey
        acceleratorKey      = [string]$c.AcceleratorKey
        helpText            = [string]$c.HelpText
        boundingRectangle   = @{
            x      = [double]$rect.X
            y      = [double]$rect.Y
            width  = [double]$rect.Width
            height = [double]$rect.Height
        }
        patterns            = @($ps.patterns)
        patternState        = $ps.state
    }
}

# ----------------------------------------------------------------- locate the target
$root = [System.Windows.Automation.AutomationElement]::RootElement
$walker = if ($View -eq 'Raw') {
    [System.Windows.Automation.TreeWalker]::RawViewWalker
} else {
    [System.Windows.Automation.TreeWalker]::ControlViewWalker
}

$topLevel = @()
$child = $walker.GetFirstChild($root)
while ($null -ne $child) {
    try {
        $ok = $false
        if ($ProcessId -gt 0) {
            $ok = ($child.Current.ProcessId -eq $ProcessId)
        } elseif ($TitleContains) {
            $ok = ($child.Current.Name -like "*$TitleContains*")
        }
        if ($ok) { $topLevel += $child }
    } catch { }
    $child = $walker.GetNextSibling($child)
}

if ($topLevel.Count -eq 0) {
    $which = if ($ProcessId -gt 0) { "process $ProcessId" } else { "a window named like '*$TitleContains*'" }
    Write-Host "NO VERDICT: no top-level UIA window found for $which."
    Write-Host "            Neither pass nor failure - the harness read nothing. If the process is"
    Write-Host "            alive, its window is either not yet mapped or belongs to a window"
    Write-Host "            station this session cannot enumerate."
    exit 3
}

# ----------------------------------------------------------------- walk
$samples = @( (Get-ForegroundSample -When 'before') )
$elements = New-Object System.Collections.ArrayList
$truncated = $false
$midSampled = $false

foreach ($win in $topLevel) {
    $stack = New-Object System.Collections.Stack
    $stack.Push(@{ el = $win; depth = 0; path = '' })

    while ($stack.Count -gt 0) {
        $frame = $stack.Pop()
        if ($elements.Count -ge $MaxElements) { $truncated = $true; break }
        if ($frame.depth -gt $MaxDepth)       { $truncated = $true; continue }

        try { $row = Read-Element -El $frame.el -Depth $frame.depth -Path $frame.path }
        catch { continue }
        [void]$elements.Add($row)

        if (-not $midSampled -and $elements.Count -ge 20) {
            $samples += (Get-ForegroundSample -When 'midwalk')
            $midSampled = $true
        }

        $kids = @()
        try {
            $k = $walker.GetFirstChild($frame.el)
            while ($null -ne $k) { $kids += $k; $k = $walker.GetNextSibling($k) }
        } catch { }

        # Reversed so the stack yields children in document order.
        for ($i = $kids.Count - 1; $i -ge 0; $i--) {
            $seg = "$($frame.path)/$i"
            [void]$stack.Push(@{ el = $kids[$i]; depth = $frame.depth + 1; path = $seg })
        }
    }
}

if (-not $midSampled) { $samples += (Get-ForegroundSample -When 'midwalk') }
$samples += (Get-ForegroundSample -When 'after')

# ----------------------------------------------------------------- target window facts
$targets = @()
foreach ($win in $topLevel) {
    $h = [int64]$win.Current.NativeWindowHandle
    $ptr = [System.IntPtr]$h
    $targets += [ordered]@{
        hwnd        = $h
        name        = [string]$win.Current.Name
        className   = [string]$win.Current.ClassName
        frameworkId = [string]$win.Current.FrameworkId
        processId   = [int]$win.Current.ProcessId
        isVisible   = [bool][Win20.Native]::IsWindowVisible($ptr)
        isMinimised = [bool][Win20.Native]::IsIconic($ptr)
    }
}

$dump = [ordered]@{
    schema         = 'win20.uia-dump/1'
    capturedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
    host           = @{
        machine       = $env:COMPUTERNAME
        psVersion     = $PSVersionTable.PSVersion.ToString()
        osVersion     = [System.Environment]::OSVersion.Version.ToString()
    }
    request        = @{ processId = $ProcessId; titleContains = $TitleContains; view = $View }
    targets        = $targets
    foregroundSamples = $samples
    truncated      = $truncated
    elementCount   = $elements.Count
    elements       = $elements
}

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$dump | ConvertTo-Json -Depth 12 | Set-Content -Path $Out -Encoding UTF8

Write-Host ("read {0} elements from {1} top-level window(s) -> {2}" -f $elements.Count, $topLevel.Count, $Out)
exit 0
