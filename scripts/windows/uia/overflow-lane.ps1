<#
.SYNOPSIS
  SURF-029 — read WIN20's two CommandBar SecondaryCommands by opening the overflow from the
  automation plane, and prove the reading by taking it three times.

.DESCRIPTION
  SURF-029 enumerates two controls, 'Export log' and 'Reset router', that no case has ever
  reached. `probe-expectation.json` records why: a CommandBar's SecondaryCommands are NOT REALISED
  while the overflow is shut, so they are absent from the control view and from the raw view, and
  the at-rest lane asserts that absence deliberately. An absence is not coverage. The controls
  were enumerated and unmeasured, and `planning/registry-drop-gate.py` reported the surface as
  uncovered for exactly that reason.

  This lane is the arm that reaches them. It does NOT weaken the at-rest lane: `probe-lane.ps1`
  keeps asserting that the two are absent while the overflow is shut, and this lane runs as its
  own process against its own fresh probe.

  THREE READINGS, because a recorder that has only ever said yes is an echo:

    BASELINE  the overflow shut. Both ids absent from the control view and the raw view.
    EFFECT    the overflow opened through ExpandCollapsePattern. Both ids present, with their
              on-screen names and ControlType.Button.
    SILENCE   the overflow shut again. Both ids absent once more.

  BASELINE and SILENCE are what make EFFECT evidence. Without them a dump that happened to hold
  the two ids for any other reason would read the same way.

  THE WRITER IS NOT THE READER. `overflow-actuate.ps1` opens the overflow in its own process and
  writes only what IT saw (ExpandCollapseState before and after). Every element reading comes from
  `uia-dump.ps1`, started separately, walking the tree out of process.

  WHAT THIS LANE GIVES UP, and what it does not. It gives up the at-rest guarantee: the surface is
  mutated, on purpose, and the reading is of an opened overflow rather than of the window as a
  user finds it. It does NOT give up the never-activated guarantee — ExpandCollapsePattern.Expand
  is not an activation, and every dump here still carries its own foreground samples so the claim
  is measured rather than assumed. `probe-expectation.json` predicted that opening the overflow
  would cost the never-activated guarantee; this lane measures that prediction rather than
  inheriting it.

  It runs on WinSta0 or it runs nowhere: a UIA walk from session 0 returns an EMPTY LIST rather
  than an error, and an empty tree makes every absence assertion here pass for free.
  `run-overflow-lane.ps1` is the wrapper that schedules it into the interactive session.

.PARAMETER Out
  Directory for the artifacts. Defaults to planning/evidence/SURF-029/run.

.PARAMETER ExePath
  The probe executable. Newest AutomationProbe.exe under app/windows/AutomationProbe/bin wins.

.PARAMETER TimeoutSeconds
  How long to wait for the probe's window to reach the plane. 180s, for the reason recorded in
  probe-lane.ps1: WinUI cold start on this machine has measured anywhere from 19s to 53s.

.OUTPUTS
  Exit 0  three readings taken and graded, and every assertion passed.
  Exit 1  an assertion failed.
  Exit 3  NO VERDICT — nothing was measured.
#>
[CmdletBinding()]
param(
    [string] $Out = '',
    [string] $ExePath = '',
    [int]    $TimeoutSeconds = 180
)

$ErrorActionPreference = 'Continue'
$env:PYTHONIOENCODING = 'utf-8'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $Out) { $Out = Join-Path $repoRoot 'planning/evidence/SURF-029/run' }
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force -Path $Out | Out-Null }

$probeDir = Join-Path $repoRoot 'app/windows/AutomationProbe/bin'
if (-not $ExePath) {
    $candidate = Get-ChildItem -Path $probeDir -Recurse -Filter 'AutomationProbe.exe' -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidate) { $ExePath = $candidate.FullName }
}

$transcript = Join-Path $Out 'lane.log'
Remove-Item $transcript -ErrorAction SilentlyContinue

function Say {
    param([string] $Message)
    $line = "{0} {1}" -f (Get-Date).ToUniversalTime().ToString('o'), $Message
    Write-Host $line
    Add-Content -Path $transcript -Value $line -Encoding UTF8
}

$script:ProbeProcessId = 0

function Stop-Lane {
    param([int] $Code, [string] $Why)
    if ($script:ProbeProcessId -gt 0) {
        Stop-Process -Id $script:ProbeProcessId -Force -ErrorAction SilentlyContinue
        Say "probe pid $($script:ProbeProcessId) stopped"
    }
    Say $Why
    $summary = [ordered]@{
        schema     = 'surf029.overflow-lane/1'
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
Add-Type -Namespace Surf029Lane -Name Native -MemberDefinition @'
    [DllImport("user32.dll")] public static extern System.IntPtr GetProcessWindowStation();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetUserObjectInformationW(System.IntPtr h, int index,
        System.Text.StringBuilder buffer, int length, out int needed);
    [DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(System.IntPtr h, out int pid);
'@

$sb = New-Object System.Text.StringBuilder 256
$needed = 0
[void][Surf029Lane.Native]::GetUserObjectInformationW(
    [Surf029Lane.Native]::GetProcessWindowStation(), 2, $sb, 256, [ref] $needed)
$station = $sb.ToString()
Say "session=$((Get-Process -Id $PID).SessionId) station=$station user=$env:USERNAME"

if ($station -ne 'WinSta0') {
    Stop-Lane 3 ("NO VERDICT: window station is '$station', not WinSta0. A UIA walk here returns " +
        "an EMPTY list rather than an error, and this lane asserts two ABSENCES either side of " +
        "its effect - every one of which an empty tree satisfies for free. Run it through " +
        "scripts/windows/uia/run-overflow-lane.ps1.")
}

# ------------------------------------------------------------------ 2. start the probe
if (-not $ExePath -or -not (Test-Path $ExePath)) {
    Stop-Lane 3 ("NO VERDICT: no AutomationProbe.exe under $probeDir. Restore and build it in two " +
        "separate MSBuild invocations; -t:Restore,Build in one call cannot build a WinUI project " +
        "from clean.")
}
Say "probe binary: $ExePath (written $((Get-Item $ExePath).LastWriteTimeUtc.ToString('o')))"

$probeLog = Join-Path $Out 'probe-startup.log'
Remove-Item $probeLog -ErrorAction SilentlyContinue
$env:WIN20_PROBE_LOG = $probeLog

$stale = @(Get-Process -Name AutomationProbe -ErrorAction SilentlyContinue)
foreach ($s in $stale) { Say "stopping a stale probe, pid=$($s.Id)"; Stop-Process -Id $s.Id -Force }

# The same precondition probe-lane.ps1 establishes, and for the same reason: when the previous
# foreground owner exits, Windows hands the foreground to the next top-level window, which is
# about to be ours. "The target never held the foreground" is only a measurement if something
# else held it first.
Start-Sleep -Seconds 2
$fgHwnd = [Surf029Lane.Native]::GetForegroundWindow()
$fgPid = 0
[void][Surf029Lane.Native]::GetWindowThreadProcessId($fgHwnd, [ref] $fgPid)
Say "foreground before launch: hwnd=$([int64]$fgHwnd) pid=$fgPid name=$((Get-Process -Id $fgPid -ErrorAction SilentlyContinue).ProcessName)"
if ([int64]$fgHwnd -eq 0 -or $fgPid -eq 0) {
    Stop-Lane 3 ("NO VERDICT: no window owns the foreground on this desktop, so 'the target never " +
        "held the foreground' cannot be measured on this run.")
}

$probe = Start-Process -FilePath $ExePath -PassThru
$script:ProbeProcessId = $probe.Id
Say "probe started, pid=$($probe.Id)"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$found = $false
while ((Get-Date) -lt $deadline) {
    if (-not (Get-Process -Id $probe.Id -ErrorAction SilentlyContinue)) {
        Get-Content $probeLog -ErrorAction SilentlyContinue | ForEach-Object { Say "  probe: $_" }
        Stop-Lane 3 "NO VERDICT: the probe exited before publishing a window."
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
    Stop-Lane 3 "NO VERDICT: the probe is alive but published no top-level UIA window within $TimeoutSeconds seconds."
}
Say "the probe's window is on the automation plane"

# ------------------------------------------------------------------ 3. three readings
$dumper   = Join-Path $PSScriptRoot 'uia-dump.ps1'
$actuator = Join-Path $PSScriptRoot 'overflow-actuate.ps1'
$barId    = 'probe.commandbar'

function Read-Phase {
    param([string] $Phase)
    $control = Join-Path $Out "$Phase-control-view.json"
    $raw     = Join-Path $Out "$Phase-raw-view.json"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dumper `
        -ProcessId $script:ProbeProcessId -Out $control -View Control | ForEach-Object { Say "dump($Phase/control): $_" }
    $c = $LASTEXITCODE
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dumper `
        -ProcessId $script:ProbeProcessId -Out $raw -View Raw | ForEach-Object { Say "dump($Phase/raw): $_" }
    $r = $LASTEXITCODE
    Say "dump($Phase) exits: control=$c raw=$r"
    if ($c -ne 0 -or $r -ne 0) { Stop-Lane 3 "NO VERDICT: the $Phase dump measured nothing (control=$c raw=$r)." }
}

function Invoke-Overflow {
    param([string] $Action)
    $receipt = Join-Path $Out ("actuate-" + $Action.ToLower() + ".json")
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $actuator `
        -ProcessId $script:ProbeProcessId -AutomationId $barId -Action $Action -Out $receipt |
        ForEach-Object { Say "actuate($Action): $_" }
    $code = $LASTEXITCODE
    Say "actuate($Action) exit=$code"
    if ($code -eq 3) { Stop-Lane 3 "NO VERDICT: the $Action actuation could not run. See its receipt." }
    if ($code -ne 0) { Stop-Lane 1 "FAIL: the $Action actuation did not move ExpandCollapseState." }
}

Read-Phase 'baseline'
Invoke-Overflow 'Expand'
Read-Phase 'effect'
Invoke-Overflow 'Collapse'
Read-Phase 'silence'

# ------------------------------------------------------------------ 4. grade
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (-not $python) { Stop-Lane 3 "NO VERDICT: no python interpreter, so the three readings were taken but not graded." }

& $python (Join-Path $PSScriptRoot 'overflow-assert.py') `
    --out $Out `
    --expectation (Join-Path $PSScriptRoot 'probe-expectation.json') `
    --report (Join-Path $Out 'assert-report.json') | ForEach-Object { Say "assert: $_" }
$assertExit = $LASTEXITCODE
Say "assert exit=$assertExit"

Get-Content $probeLog -ErrorAction SilentlyContinue | ForEach-Object { Say "  probe: $_" }

if ($assertExit -eq 3) { Stop-Lane 3 "NO VERDICT: the grading measured nothing. See the transcript above." }
if ($assertExit -ne 0) { Stop-Lane 1 "FAIL: assert exit $assertExit." }
Stop-Lane 0 ("pass: both SecondaryCommands are absent with the overflow shut, present with their " +
    "on-screen names and ControlType when it is opened from the automation plane, and absent " +
    "again when it is shut. The probe held the foreground at none of the BASELINE samples, and " +
    "at every EFFECT and SILENCE sample - which is the declared activationCost, not a clean " +
    "never-activated run. Opening the overflow activates the window; the at-rest lane is where " +
    "that guarantee still lives.")
