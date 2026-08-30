<#
.SYNOPSIS
  WIN20 — run the automation-plane lane in the interactive session, from wherever you are.

.DESCRIPTION
  `probe-lane.ps1` has to run on window station WinSta0. An agent shell on this machine does not:
  measured on LUKESFF, 2026-08-30, it runs in session 0 on `Service-0x0-...`, where a WinUI process
  dies at Application.Start and a UIA walk returns an empty list rather than an error.

  This wrapper is the bridge. If it is already on WinSta0 it just runs the lane. If it is not, it
  registers a scheduled task with /IT — "run only when the user is logged on", which is what gets
  the task the interactive window station — runs it, waits for the lane's own lane.json to appear,
  and adopts the lane's exit code.

  TWO THINGS ABOUT SCHEDULED TASKS THAT COST TIME IF THEY ARE NOT KNOWN (both in this repo's
  CLAUDE.md, both re-confirmed here):

    · a task's stdout is lost. Everything the lane needs to say, it says into files under -Out.
    · `schtasks /run` prints "SUCCESS: Attempted to run" whether or not anything ran. Its exit code
      is not evidence. This wrapper judges by lane.json on disk, and treats a missing lane.json
      after the timeout as NO VERDICT rather than as either outcome.

.PARAMETER Out
  Directory for the artifacts. Defaults to planning/evidence/WIN20/run.

.PARAMETER TimeoutSeconds
  How long to wait for the scheduled lane to produce lane.json. It must exceed the lane's own
  window-wait (180s) plus both tree walks, or this wrapper reports NO VERDICT over a lane that was
  still working - a timeout of the timer rather than of the thing being timed.

.OUTPUTS
  The lane's own exit code: 0 pass, 1 fail, 3 no verdict.
#>
[CmdletBinding()]
param(
    [string] $Out = '',
    [int]    $TimeoutSeconds = 420
)

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $Out) { $Out = Join-Path $repoRoot 'planning/evidence/WIN20/run' }
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force -Path $Out | Out-Null }

$lane = Join-Path $PSScriptRoot 'probe-lane.ps1'

Add-Type -Namespace Win20Run -Name Native -MemberDefinition @'
    [DllImport("user32.dll")] public static extern System.IntPtr GetProcessWindowStation();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetUserObjectInformationW(System.IntPtr h, int index,
        System.Text.StringBuilder buffer, int length, out int needed);
'@
$sb = New-Object System.Text.StringBuilder 256
$needed = 0
[void][Win20Run.Native]::GetUserObjectInformationW(
    [Win20Run.Native]::GetProcessWindowStation(), 2, $sb, 256, [ref] $needed)
$station = $sb.ToString()

if ($station -eq 'WinSta0') {
    Write-Host "already on WinSta0; running the lane directly"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $lane -Out $Out
    exit $LASTEXITCODE
}

Write-Host "window station is '$station'; scheduling the lane into the interactive session"

$taskName = 'MCPRouter-WIN20-AutomationPlaneLane'
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
