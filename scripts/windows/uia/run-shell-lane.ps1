<#
.SYNOPSIS
  Run the shell's automation-plane lane in the interactive session, from wherever you are.

.DESCRIPTION
  Identical bridge to run-probe-lane.ps1, pointed at shell-lane.ps1 instead of probe-lane.ps1,
  and it exists for the same measured reason: an agent shell on this machine runs in session 0 on
  `Service-0x0-...`, where a WinUI process dies at Application.Start and a UIA walk returns an
  empty list rather than an error. A task registered with /IT — "run only when the user is logged
  on" — is what gets the lane onto WinSta0.

  The two scheduled-task facts this repo has paid for twice, restated because they decide how this
  file judges anything:

    · a task's stdout is lost. Everything the lane says, it says into files under -Out.
    · `schtasks /run` prints "SUCCESS: Attempted to run" whether or not anything ran, so its exit
      code is not evidence. lane.json on disk is the oracle, and a missing lane.json after the
      timeout is NO VERDICT rather than either outcome.

  WHY THE TIMEOUT DEFAULTS SO MUCH HIGHER THAN THE PROBE'S. The probe lane opens one window and
  walks it twice. This lane opens the product, then actuates and dumps ten destinations in turn,
  so its floor is the shell's own startup plus ten settle-and-walk cycles. A timeout below that
  reports NO VERDICT over a lane that was still working — a timeout of the timer rather than of
  the thing being timed — which is the failure the probe wrapper's own note warns about.

.OUTPUTS
  The lane's own exit code: 0 pass, 1 fail, 3 no verdict.
#>
[CmdletBinding()]
param(
    [string] $Out = '',
    [string] $ExePath = '',
    [int]    $TimeoutSeconds = 900
)

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $Out) { $Out = Join-Path $repoRoot 'planning/evidence/WIN-SHELL/run' }
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force -Path $Out | Out-Null }

$lane = Join-Path $PSScriptRoot 'shell-lane.ps1'

Add-Type -Namespace WinShellRun -Name Native -MemberDefinition @'
    [DllImport("user32.dll")] public static extern System.IntPtr GetProcessWindowStation();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetUserObjectInformationW(System.IntPtr h, int index,
        System.Text.StringBuilder buffer, int length, out int needed);
'@
$sb = New-Object System.Text.StringBuilder 256
$needed = 0
[void][WinShellRun.Native]::GetUserObjectInformationW(
    [WinShellRun.Native]::GetProcessWindowStation(), 2, $sb, 256, [ref] $needed)
$station = $sb.ToString()

$laneArgs = @('-Out', $Out)
if ($ExePath) { $laneArgs += @('-ExePath', $ExePath) }

if ($station -eq 'WinSta0') {
    Write-Host "already on WinSta0; running the shell lane directly"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $lane @laneArgs
    exit $LASTEXITCODE
}

Write-Host "window station is '$station'; scheduling the shell lane into the interactive session"

$taskName = 'MCPRouter-WINSHELL-AutomationPlaneLane'
$laneJson = Join-Path $Out 'lane.json'
Remove-Item $laneJson -ErrorAction SilentlyContinue

$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$lane`" -Out `"$Out`""
if ($ExePath) { $command += " -ExePath `"$ExePath`"" }

& schtasks.exe /Create /TN $taskName /TR $command /SC ONCE /ST 00:00 /IT /F | Out-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "NO VERDICT: could not register the interactive task (schtasks exit $LASTEXITCODE)."
    exit 3
}

& schtasks.exe /Run /TN $taskName | Out-Host
# Deliberately not checked: schtasks reports "Attempted to run" either way. lane.json is the oracle.

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline -and -not (Test-Path $laneJson)) {
    Start-Sleep -Seconds 3
}

& schtasks.exe /Delete /TN $taskName /F | Out-Null

if (-not (Test-Path $laneJson)) {
    Write-Host "NO VERDICT: the interactive shell lane produced no lane.json within $TimeoutSeconds seconds."
    Write-Host "            Its transcript, if it got that far:"
    Get-Content (Join-Path $Out 'lane.log') -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  $_" }
    exit 3
}

Get-Content (Join-Path $Out 'lane.log') -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host $_ }

$summary = Get-Content $laneJson -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ""
Write-Host ("shell lane verdict: {0} (exit {1})" -f $summary.verdict, $summary.exitCode)
Write-Host $summary.why
exit ([int]$summary.exitCode)
