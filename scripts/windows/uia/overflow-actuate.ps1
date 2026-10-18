<#
.SYNOPSIS
  WIN20 — open or shut a CommandBar's overflow through the automation plane, and nothing else.

.DESCRIPTION
  This is the ONE script in the UIA lane that calls a pattern METHOD. It exists as its own file,
  and as its own process, for two reasons that are the whole point of the arm it serves:

    · `uia-dump.ps1` promises in its own header that it never calls Invoke, Toggle, Select or
      Expand. That promise is load-bearing for the at-rest lane, where the two SecondaryCommands
      are asserted ABSENT. Putting an actuation into the dumper would quietly retire that
      promise, so the actuation lives here instead.
    · the reader must not be the writer. This process expands; `uia-dump.ps1`, started separately
      by the lane, reads the tree back. A process reporting its own effect is not evidence.

  WHAT IT DOES NOT DO. It never calls SetForegroundWindow or SetFocus, and it samples
  GetForegroundWindow() before and after the actuation with the target window's HWND beside it.
  Expanding a CommandBar is a mutation of the surface; it is NOT an activation of it, and the
  difference is measured here rather than asserted downstream.

.PARAMETER ProcessId
  The process that owns the window carrying the element.

.PARAMETER AutomationId
  The AutomationId of the element to expand or collapse.

.PARAMETER Action
  Expand or Collapse.

.PARAMETER Out
  Path for the JSON receipt: the ExpandCollapseState this process read before and after its call,
  plus its two foreground samples.

.OUTPUTS
  Exit 0  the pattern method was called and the state moved the way the action asks.
  Exit 1  the pattern method was called and the state did not move.
  Exit 3  NO VERDICT — no window, no element, or no ExpandCollapsePattern to call.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int]    $ProcessId,
    [Parameter(Mandatory = $true)][string] $AutomationId,
    [Parameter(Mandatory = $true)][ValidateSet('Expand', 'Collapse')][string] $Action,
    [Parameter(Mandatory = $true)][string] $Out
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host "NO VERDICT: this script needs Windows PowerShell 5.1; System.Windows.Automation is"
    Write-Host "            a .NET Framework assembly and pwsh cannot load it."
    exit 3
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -Namespace Win20Act -Name Native -MemberDefinition @'
    [DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(System.IntPtr h, out int pid);
'@

function Get-ForegroundSample {
    param([string] $When)
    $h = [Win20Act.Native]::GetForegroundWindow()
    $pid2 = 0
    [void][Win20Act.Native]::GetWindowThreadProcessId($h, [ref] $pid2)
    [ordered]@{
        when      = $When
        hwnd      = [int64]$h
        processId = $pid2
    }
}

$receipt = [ordered]@{
    schema           = 'win20.actuate/1'
    action           = $Action
    automationId     = $AutomationId
    processId        = $ProcessId
    capturedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
    targetHwnd       = 0
    stateBefore      = $null
    stateAfter       = $null
    foregroundSamples = @()
    note             = $null
}

function Write-Receipt {
    param([int] $Code, [string] $Note)
    $receipt.note = $Note
    $dir = Split-Path -Parent $Out
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -Path $Out -Encoding UTF8
    Write-Host $Note
    exit $Code
}

$root = [System.Windows.Automation.AutomationElement]::RootElement
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$window = $null
$child = $walker.GetFirstChild($root)
while ($null -ne $child) {
    try { if ($child.Current.ProcessId -eq $ProcessId) { $window = $child; break } } catch { }
    $child = $walker.GetNextSibling($child)
}

if ($null -eq $window) {
    Write-Receipt 3 "NO VERDICT: process $ProcessId publishes no top-level window on this desktop."
}
$receipt.targetHwnd = [int64]$window.Current.NativeWindowHandle

$condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId)
$element = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)

if ($null -eq $element) {
    Write-Receipt 3 "NO VERDICT: no descendant of that window carries AutomationId '$AutomationId'."
}

$pattern = $null
try {
    $pattern = $element.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
} catch { }

if ($null -eq $pattern) {
    Write-Receipt 3 ("NO VERDICT: '$AutomationId' publishes no ExpandCollapsePattern, so the " +
        "overflow cannot be opened from the automation plane at all. That is a finding about the " +
        "plane and it is recorded as measuring nothing rather than as a failure of the surface.")
}

$receipt.foregroundSamples += (Get-ForegroundSample -When 'before')
$receipt.stateBefore = $pattern.Current.ExpandCollapseState.ToString()

if ($Action -eq 'Expand') { $pattern.Expand() } else { $pattern.Collapse() }

# WinUI animates the overflow flyout in. The state property settles immediately; the flyout's
# children do not, which is why the LANE waits before dumping rather than this script pretending
# the tree is quiet the instant the call returns.
Start-Sleep -Milliseconds 900

$receipt.stateAfter = $pattern.Current.ExpandCollapseState.ToString()
$receipt.foregroundSamples += (Get-ForegroundSample -When 'after')

$want = if ($Action -eq 'Expand') { 'Expanded' } else { 'Collapsed' }
if ($receipt.stateAfter -eq $want) {
    Write-Receipt 0 ("$Action called on '$AutomationId': ExpandCollapseState went " +
        "$($receipt.stateBefore) -> $($receipt.stateAfter).")
}
Write-Receipt 1 ("FAIL: $Action called on '$AutomationId' and ExpandCollapseState reads " +
    "$($receipt.stateAfter), not $want.")
