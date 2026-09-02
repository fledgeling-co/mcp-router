<#
.SYNOPSIS
  SURF-029 — run the overflow lane in the interactive session, from wherever you are.

.DESCRIPTION
  `overflow-lane.ps1` has to run on window station WinSta0, and for a sharper reason than the
  at-rest lane has. A UIA walk from session 0 returns an EMPTY LIST rather than an error, and this
  lane asserts two ABSENCES (baseline and silence) either side of its one presence — an empty tree
  satisfies both absences for free and would leave a single failing arm looking like a flaky one.

  So: if this wrapper is already on WinSta0 it runs the lane directly. If it is not, it registers
  a scheduled task with /IT — "run only when the user is logged on", which is what gets the task
  the interactive window station — runs it, waits for the lane's own lane.json, and adopts the
  lane's exit code.

  `schtasks /run` prints "SUCCESS: Attempted to run" whether or not anything ran, and a task's
  stdout is lost. lane.json on disk is the oracle here; a missing one after the timeout is NO
  VERDICT rather than either outcome.

.PARAMETER Out
  Directory for the artifacts. Defaults to planning/evidence/SURF-029/run.

.PARAMETER TimeoutSeconds
  How long to wait for lane.json. It must exceed the lane's own window-wait (180s) plus SIX tree
  walks and two actuations, which is why it is larger than the at-rest wrapper's 420.

.OUTPUTS
  The lane's own exit code: 0 pass, 1 fail, 3 no verdict.
#>
[CmdletBinding()]
param(
    [string] $Out = '',
    [int]    $TimeoutSeconds = 600
)

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $Out) { $Out = Join-Path $repoRoot 'planning/evidence/SURF-029/run' }
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force -Path $Out | Out-Null }

$lane = Join-Path $PSScriptRoot 'overflow-lane.ps1'

Add-Type -Namespace Surf029Run -Name Native -MemberDefinition @'
    [DllImport("user32.dll")] public static extern System.IntPtr GetProcessWindowStation();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetUserObjectInformationW(System.IntPtr h, int index,
        System.Text.StringBuilder buffer, int length, out int needed);
'@
$sb = New-Object System.Text.StringBuilder 256
$needed = 0
[void][Surf029Run.Native]::GetUserObjectInformationW(
    [Surf029Run.Native]::GetProcessWindowStation(), 2, $sb, 256, [ref] $needed)
$station = $sb.ToString()

if ($station -eq 'WinSta0') {
    Write-Host "already on WinSta0; running the lane directly"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $lane -Out $Out
    exit $LASTEXITCODE
}

Write-Host "window station is '$station'; scheduling the lane into the interactive session"

$taskName = 'MCPRouter-SURF029-OverflowLane'
$laneJson = Join-Path $Out 'lane.json'
Remove-Item $laneJson -ErrorAction SilentlyContinue

$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$lane`" -Out `"$Out`""

& schtasks.exe /Create /TN $taskName /TR $command /SC ONCE /ST 00:00 /IT /F | Out-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "NO VERDICT: could not register the interactive task (schtasks exit $LASTEXITCODE)."
    exit 3
}

& schtasks.exe /Run /TN $taskName | Out-Host
# Deliberately not checked: schtasks reports "Attempted to run" either way. lane.json is the oracle.

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline -and -not (Test-Path $laneJson)) {
    Start-Sleep -Seconds 2
}

& schtasks.exe /Delete /TN $taskName /F | Out-Null

if (-not (Test-Path $laneJson)) {
    Write-Host "NO VERDICT: the interactive lane produced no lane.json within $TimeoutSeconds seconds."
    Write-Host "            Its transcript, if it got that far:"
    Get-Content (Join-Path $Out 'lane.log') -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  $_" }
    exit 3
}

Get-Content (Join-Path $Out 'lane.log') -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host $_ }

$summary = Get-Content $laneJson -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ""
Write-Host ("lane verdict: {0} (exit {1})" -f $summary.verdict, $summary.exitCode)
Write-Host $summary.why
exit ([int]$summary.exitCode)
