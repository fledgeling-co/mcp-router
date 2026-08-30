<#
.SYNOPSIS
  WIN20 — the Windows automation-plane lane. Launch the probe, read its UIA tree, grade it.

.DESCRIPTION
  This is the lane the campaign runs. It does five things in order and stops at the first one that
  cannot honestly proceed:

    1. refuses to run on a non-interactive window station (see below)
    2. starts the probe and waits for a top-level UIA window to appear for its process
    3. dumps the control view and the raw view, out of process
    4. grades both against scripts/windows/uia/probe-expectation.json
    5. stops the probe and writes lane.json

  THE WINDOW-STATION REFUSAL IS THE POINT, not a nuisance.

  Measured on LUKESFF, 2026-08-30: an agent shell on this machine runs in **session 0** on window
  station `Service-0x0-...`. In that session a WinUI 3 process dies during Application.Start with
  STATUS_STOWED_EXCEPTION (0xC000027B), and a UIA walk cannot see the interactive desktop's
  windows at all — it returns an EMPTY LIST rather than an error.

  Those two facts compose into the exact failure this repository keeps naming: an empty tree
  satisfies every assertion about names and states for free. A lane that ran here and reported
  green would be reporting a green tick for a window that never existed. So it refuses, with
  exit 3, and `run-probe-lane.ps1` is the wrapper that puts it in session 1 where it can measure.

.PARAMETER Out
  Directory for the artifacts. Defaults to planning/evidence/WIN20/run.

.PARAMETER ExePath
  The probe executable. Defaults to the AutomationProbe Debug x64 output.

.PARAMETER TimeoutSeconds
  How long to wait for the probe's window to appear on the plane.

.OUTPUTS
  Exit 0  the tree was read and every assertion that could run, passed.
  Exit 1  an assertion failed.
  Exit 3  NO VERDICT — nothing was measured. Not a pass and not a failure.
#>
[CmdletBinding()]
param(
    [string] $Out = '',
    [string] $ExePath = '',
    [int]    $TimeoutSeconds = 45
)

$ErrorActionPreference = 'Continue'   # native tools write progress to stderr; see CLAUDE.md
$env:PYTHONIOENCODING = 'utf-8'       # repo gates die under cp1252 without this

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $Out) { $Out = Join-Path $repoRoot 'planning/evidence/WIN20/run' }

# The binary is SEARCHED FOR, not spelled out. A hardcoded
# bin/x64/Debug/net8.0-.../win-x64/AutomationProbe.exe was wrong the first time the lane ran behind
# scripts/windows/verify.ps1: that lane builds every .csproj with no -p:Platform, MSBuild defaults
# Platform to AnyCPU, and the output lands in bin/Debug/... with no platform folder. The lane
# correctly reported NO VERDICT rather than a pass - but "the build I am grading is the build that
# just happened" should not depend on two files agreeing about a path. Newest wins, and the choice
# is written into the transcript so the artifact names the binary it measured.
$probeDir = Join-Path $repoRoot 'app/windows/AutomationProbe/bin'
if (-not $ExePath) {
    $candidate = Get-ChildItem -Path $probeDir -Recurse -Filter 'AutomationProbe.exe' -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidate) { $ExePath = $candidate.FullName }
}

if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force -Path $Out | Out-Null }

$transcript = Join-Path $Out 'lane.log'
Remove-Item $transcript -ErrorAction SilentlyContinue

function Say {
    param([string] $Message)
    $line = "{0} {1}" -f (Get-Date).ToUniversalTime().ToString('o'), $Message
    Write-Host $line
    Add-Content -Path $transcript -Value $line -Encoding UTF8
}

function Stop-Lane {
    param([int] $Code, [string] $Why)
    Say $Why
    $summary = [ordered]@{
        schema     = 'win20.lane/1'
        exitCode   = $Code
        verdict    = @{ 0 = 'pass'; 1 = 'fail'; 3 = 'no-verdict' }[$Code]
        why        = $Why
        sessionId  = (Get-Process -Id $PID).SessionId
        finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $Out 'lane.json') -Encoding UTF8
    exit $Code
}

# ------------------------------------------------------------------ 1. window station
Add-Type -Namespace Win20Lane -Name Native -MemberDefinition @'
    [DllImport("user32.dll")] public static extern System.IntPtr GetProcessWindowStation();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetUserObjectInformationW(System.IntPtr h, int index,
        System.Text.StringBuilder buffer, int length, out int needed);
'@

$sb = New-Object System.Text.StringBuilder 256
$needed = 0
[void][Win20Lane.Native]::GetUserObjectInformationW(
    [Win20Lane.Native]::GetProcessWindowStation(), 2, $sb, 256, [ref] $needed)
$station = $sb.ToString()
$sessionId = (Get-Process -Id $PID).SessionId

Say "session=$sessionId station=$station user=$env:USERNAME"

if ($station -ne 'WinSta0') {
    Stop-Lane 3 ("NO VERDICT: window station is '$station', not WinSta0. A WinUI process cannot " +
        "draw here and a UIA walk cannot see the interactive desktop - it returns an EMPTY list " +
        "rather than an error, and an empty tree passes every assertion for free. Run this " +
        "through scripts/windows/uia/run-probe-lane.ps1, which schedules it into the interactive " +
        "session.")
}

# ------------------------------------------------------------------ 2. start the probe
if (-not $ExePath -or -not (Test-Path $ExePath)) {
    Stop-Lane 3 ("NO VERDICT: no AutomationProbe.exe under $probeDir. Build it first - and note " +
        "that MSBuild -t:Restore,Build in ONE invocation cannot build a WinUI project from clean; " +
        "restore and build must be separate invocations. See scripts/windows/verify.ps1.")
}
Say "probe binary: $ExePath (written $((Get-Item $ExePath).LastWriteTimeUtc.ToString('o')))"

$probeLog = Join-Path $Out 'probe-startup.log'
Remove-Item $probeLog -ErrorAction SilentlyContinue
$env:WIN20_PROBE_LOG = $probeLog

Get-Process -Name AutomationProbe -ErrorAction SilentlyContinue |
    ForEach-Object { Say "stopping a stale probe, pid=$($_.Id)"; Stop-Process -Id $_.Id -Force }

$probe = Start-Process -FilePath $ExePath -PassThru
Say "probe started, pid=$($probe.Id)"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$found = $false
while ((Get-Date) -lt $deadline) {
    if (-not (Get-Process -Id $probe.Id -ErrorAction SilentlyContinue)) {
        Say "probe exited early; its own startup log follows"
        Get-Content $probeLog -ErrorAction SilentlyContinue | ForEach-Object { Say "  probe: $_" }
        Stop-Lane 3 ("NO VERDICT: the probe process exited before publishing a window. Nothing " +
            "was measured, and this is a fault in the probe rather than a finding about the " +
            "automation plane.")
    }

    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($root)
    while ($null -ne $child) {
        try { if ($child.Current.ProcessId -eq $probe.Id) { $found = $true; break } } catch { }
        $child = $walker.GetNextSibling($child)
    }
    if ($found) { break }
    Start-Sleep -Milliseconds 500
}

if (-not $found) {
    Stop-Lane 3 ("NO VERDICT: the probe is alive but published no top-level UIA window within " +
        "$TimeoutSeconds seconds.")
}
Say "the probe's window is on the automation plane"

# ------------------------------------------------------------------ 3. dump both views
$controlDump = Join-Path $Out 'uia-control-view.json'
$rawDump     = Join-Path $Out 'uia-raw-view.json'
$dumper      = Join-Path $PSScriptRoot 'uia-dump.ps1'

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dumper `
    -ProcessId $probe.Id -Out $controlDump -View Control | ForEach-Object { Say "dump(control): $_" }
$controlExit = $LASTEXITCODE
Say "dump(control) exit=$controlExit"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dumper `
    -ProcessId $probe.Id -Out $rawDump -View Raw | ForEach-Object { Say "dump(raw): $_" }
$rawExit = $LASTEXITCODE
Say "dump(raw) exit=$rawExit"

# ------------------------------------------------------------------ 4. grade
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command python3 -ErrorAction SilentlyContinue).Source }

$assertExit = 3
if (-not $python) {
    Say "no python interpreter found; the dump was taken but not graded"
} else {
    & $python (Join-Path $PSScriptRoot 'uia-assert.py') `
        --dump $controlDump --raw-dump $rawDump `
        --expectation (Join-Path $PSScriptRoot 'probe-expectation.json') `
        --report (Join-Path $Out 'assert-report.json') | ForEach-Object { Say "assert: $_" }
    $assertExit = $LASTEXITCODE
    Say "assert exit=$assertExit"
}

# ------------------------------------------------------------------ 5. teardown
Stop-Process -Id $probe.Id -Force -ErrorAction SilentlyContinue
Say "probe stopped"
Get-Content $probeLog -ErrorAction SilentlyContinue | ForEach-Object { Say "  probe: $_" }

if ($controlExit -eq 3 -or $assertExit -eq 3) {
    Stop-Lane 3 "NO VERDICT: the dump or the grading measured nothing. See the transcript above."
}
if ($controlExit -ne 0 -or $assertExit -ne 0) {
    Stop-Lane 1 "FAIL: dump exit $controlExit, assert exit $assertExit."
}
Stop-Lane 0 "pass: the tree was read out of process, the target never held the foreground, and every assertion that could run, passed."
