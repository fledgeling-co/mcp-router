<#
.SYNOPSIS
    DEF-079 effect witness: each of the shell's three top-level unhandled-exception handlers is
    made to fire on purpose, and the line it wrote is read back out of shell-startup.log by a
    different process.

.DESCRIPTION
    WHY THIS LANE EXISTS. DEF-079 is not a broken handler. It is a handler nobody has seen fire.
    Sixteen launches on 2026-09-02 wrote not one `unhandled:` line, including eight that terminated
    at 0xC000027B, which is by definition an unhandled exception; the two extra handlers added in
    response - AppDomain.CurrentDomain.UnhandledException and TaskScheduler.UnobservedTaskException
    - were registered and then never observed catching anything, because every exception since has
    been caught at a site that logs it directly. Registration is a claim. This lane is the
    measurement, and without it DEF-079 could only be closed on the strength of the same claim it
    was raised about.

    HOW IT MEASURES. The shell accepts `--fault <kind>`, compiled out outside DEBUG and inert
    unless passed, which takes exactly one deliberate escape route:

      ui          thrown on the UI thread, synchronously,
                  inside XAML's own dispatch of OnLaunched -> Microsoft.UI.Xaml.Application.UnhandledException
      appdomain   thrown on a non-UI foreground thread     -> AppDomain.CurrentDomain.UnhandledException
      task        a faulted task nobody awaits, then a
                  collection and WaitForPendingFinalizers  -> TaskScheduler.UnobservedTaskException
      dispatcher  thrown from a DispatcherQueue callback   -> NOTHING, measured. Ungraded probe; DEF-085

    Each of the first three handlers writes a line naming itself, and this script requires that
    specific line. The fourth is run and reported and graded by nothing, because on this host it
    reaches no handler at all: the process disappears having written `fault: injecting` and nothing
    after it, which is the silence DEF-079 was raised about, arriving by a second route. That is
    DEF-085's, and a lane whose verdict flipped when somebody fixed DEF-085 would stop meaning what
    its name says.

    THE RECORDER IS NOT THE WRITER. The lines are written by handlers running inside the shell
    process, through Microsoft.UI.Xaml and the CLR. They are read here out of a file on disk, by
    PowerShell, in a different process, after the writing process has exited. Nothing in this
    repository sits between the two. The shell's own `handlers:` line, which says which handlers it
    attached, is carried as `writerSelfReport` and is graded by nothing.

    THE PRESENCE CONTROL. Every arm reads a REGION of the log - the bytes appended after this
    script recorded the file's length - so a line left by an earlier run can never satisfy one. The
    BASELINE arm is a launch with no `--fault` at all, and requires its region to hold `launched`
    and no `unhandled:` line: it proves the flag is inert when absent, and that the lines the EFFECT
    arms find were produced by the injection rather than by ordinary startup.

    WHAT IS NOT MEASURED, said here rather than left to a green: a real stowed exception at
    0xC000027B below the managed dispatch boundary. The injected UI-thread fault is an ordinary
    managed exception inside XAML dispatch, which is the route the XAML handler exists for; it does
    not reproduce the CoreMessagingXP failure DEF-079 was found through, and nothing on this host
    can. notMeasured[] carries it and DEF-086 was filed for it.

.PARAMETER ProveRed
    Arming. Launches the run for one handler with `--fault-unregister <handler>` as well, so that
    handler is genuinely never attached - a defect this product can have - and requires exactly that
    arm to break while BASELINE and the other two EFFECT arms hold.

.PARAMETER ArmHandler
    Which handler -ProveRed leaves unregistered. Defaults to `task`, the one route whose fault does
    not terminate the process, so an arming run cannot leave a Windows Error Reporting dialog on a
    station this lane cannot see.

.NOTES
    Exit 0 pass, 1 fail, 3 NO VERDICT.
#>
[CmdletBinding()]
param(
    [string] $Out = 'planning/evidence/WIN-SHELL/run',
    [string] $ExePath = '',
    [int]    $PerRunTimeoutSeconds = 90,
    [ValidateSet('xaml', 'appdomain', 'task')]
    [string] $ArmHandler = 'task',
    [switch] $ProveRed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutDir = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $RepoRoot $Out }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$Arms = @()
$Notes = @()
$Runs = @()

function Add-Arm {
    param([string] $Id, [string] $What, [bool] $Held, [string] $Detail)
    $script:Arms += [pscustomobject]@{ id = $Id; what = $What; held = $Held; detail = $Detail }
    $mark = if ($Held) { 'HELD' } else { 'BROKE' }
    Write-Host ("  {0,-18} {1,-6} {2}" -f $Id, $mark, $What)
    if ($Detail) { Write-Host ("                            {0}" -f $Detail) }
}

function Write-Verdict {
    param([int] $Code, [string] $Verdict, [string] $Reason)
    $doc = [ordered]@{
        lane        = 'win-shell-unhandled-witness'
        rung        = 'effect-witness'
        defect      = 'DEF-079'
        subject     = 'MCPRouter.Shell.App top-level unhandled-exception handlers'
        writer      = 'the three handlers, running inside the shell process'
        recorder    = 'shell-startup.log on disk, read by PowerShell in a different process after the writer exited'
        recorderIsNotWriter = $true
        arming      = [bool] $ProveRed
        armedHandler = $(if ($ProveRed) { $ArmHandler } else { $null })
        verdict     = $Verdict
        reason      = $Reason
        arms        = $Arms
        armsHeld    = @($Arms | Where-Object { $_.held }).Count
        armsTotal   = $Arms.Count
        runs        = $Runs
        writerSelfReportIsNotEvidence =
            'each run''s `handlers:` line is the shell reporting which handlers it attached. It is ' +
            'carried in runs[] and graded by nothing: a process reporting its own effect is the ' +
            'shape of claim DEF-079 is about. What is graded is the line each handler wrote.'
        notMeasured = @(
            'a real stowed exception at 0xC000027B below the managed dispatch boundary - the route DEF-079 was found through. The injected UI fault is an ordinary managed exception in XAML dispatch; nothing on this host can raise the other (DEF-086)',
            'a throw from a DispatcherQueue callback: run here as an UNGRADED probe because it reaches no handler at all, which is DEF-085 rather than a fault in the three handlers this lane grades. notes[] records what the probe saw on this run',
            'that a handler fires in a RELEASE build - the injection is compiled out outside DEBUG, so this lane grades the Debug binary only',
            'that the log survives a process kill mid-write - StartupLog appends synchronously per line, which is assumed rather than witnessed here'
        )
        notes       = $Notes
        host        = $env:COMPUTERNAME
        psVersion   = $PSVersionTable.PSVersion.ToString()
    }
    $path = Join-Path $OutDir $(if ($ProveRed) { 'unhandled-witness-armed.json' } else { 'unhandled-witness.json' })
    [System.IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 6),
        (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ("win-shell unhandled witness: {0} - {1}" -f $Verdict, $Reason)
    Write-Host ("               wrote {0}" -f $path)
    exit $Code
}

# --------------------------------------------------------------------------- the writer
if (-not $ExePath) {
    $ExePath = Join-Path $RepoRoot 'app\windows\MCPRouter.Shell\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\MCPRouter.Shell.exe'
}
if (-not (Test-Path $ExePath)) {
    Write-Verdict 3 'NO VERDICT' ("the shell binary is not on disk at {0}. Build it with the " +
        'Visual Studio MSBuild - dotnet build cannot build WinUI here - and run this again.' -f $ExePath)
}
$LogPath = Join-Path (Split-Path -Parent $ExePath) 'shell-startup.log'

# The station bridge, same as win22-toast-witness.ps1 uses. From session 0 a WinUI process dies at
# 0xC000027B before the App constructor runs, so no handler would ever be attached and this lane
# would report three dead handlers where there is a window-station problem.
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
$Station = $sb.ToString()

function Get-LogLength {
    if (-not (Test-Path $LogPath)) { return 0 }
    try { return (Get-Item $LogPath).Length } catch { return 0 }
}

function Read-LogRegion {
    param([long] $Offset)
    if (-not (Test-Path $LogPath)) { return '' }
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        try {
            $stream = [System.IO.File]::Open($LogPath, 'Open', 'Read', 'ReadWrite')
            try {
                if ($stream.Length -le $Offset) { return '' }
                [void] $stream.Seek($Offset, 'Begin')
                $buffer = New-Object byte[] ($stream.Length - $Offset)
                [void] $stream.Read($buffer, 0, $buffer.Length)
                return [System.Text.Encoding]::UTF8.GetString($buffer)
            } finally { $stream.Dispose() }
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    return ''
}

function Stop-Shell {
    Get-Process -Name 'MCPRouter.Shell' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Invoke-ShellRun {
    <#
      One launch, and the bytes it appended to the log. The offset is taken before the launch, so
      nothing an earlier run wrote can be read as this one's.
    #>
    param(
        [string]   $Label,
        [string[]] $Arguments,
        [string]   $SettleOn,
        [int]      $SettleSeconds = 5
    )
    Stop-Shell
    $offset = Get-LogLength
    $taskName = 'MCPRouter-DEF079-' + $Label

    Write-Host ("  run '{0}': {1}" -f $Label, $($Arguments -join ' '))
    if ($Station -eq 'WinSta0') {
        Start-Process -FilePath $ExePath -ArgumentList $Arguments | Out-Null
    } else {
        $quoted = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $command = "`"$ExePath`" $quoted"
        & schtasks.exe /Create /TN $taskName /TR $command /SC ONCE /ST 00:00 /IT /F | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ label = $Label; region = ''; reachedInjection = $false
                                      failure = "could not register the interactive task (schtasks exit $LASTEXITCODE)" }
        }
        # schtasks /Run prints "Attempted to run" either way, so its exit code is not evidence.
        # The bytes in the log are the only signal that the shell got as far as running.
        & schtasks.exe /Run /TN $taskName | Out-Null
    }

    $deadline = (Get-Date).AddSeconds($PerRunTimeoutSeconds)
    $region = ''
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $region = Read-LogRegion $offset
        if ($SettleOn -and $region -match $SettleOn) { break }
    }
    # A last look after a settle: a handler writing its line a moment after the match, and the
    # baseline run which has nothing to match on, both land here.
    Start-Sleep -Seconds $SettleSeconds
    $region = Read-LogRegion $offset

    Stop-Shell
    if ($Station -ne 'WinSta0') {
        & schtasks.exe /Delete /TN $taskName /F | Out-Null
    }

    $self = ''
    foreach ($line in ($region -split "`r?`n")) {
        if ($line -match 'handlers:') { $self = $line.Trim() }
    }
    $result = [pscustomobject]@{
        label            = $Label
        arguments        = ($Arguments -join ' ')
        offset           = $offset
        bytes            = $region.Length
        reachedLaunch    = [bool] ($region -match 'launched,')
        reachedInjection = [bool] ($region -match 'fault: injecting')
        writerSelfReport = $self
        region           = $region.Trim()
        failure          = $null
    }
    $script:Runs += $result
    return $result
}

Write-Host ''
Write-Host  'win-shell unhandled witness: DEF-079, the three top-level handlers'
Write-Host ("               exe      {0}" -f $ExePath)
Write-Host ("               log      {0}" -f $LogPath)
Write-Host ("               station  {0}" -f $Station)
if ($ProveRed) {
    Write-Host ("               ARMING   --fault-unregister {0} on that handler's run only" -f $ArmHandler)
}
Write-Host  '               writer   the handlers, inside the shell process'
Write-Host  '               recorder the log file, read here after that process exited'
Write-Host ''

# --------------------------------------------------------------------------- BASELINE
# A launch with no --fault at all. Two claims in one arm: the flag is inert when absent, and no
# `unhandled:` line appears in an ordinary run - so a line an EFFECT arm finds was produced by the
# injection rather than by startup, and could not have been left behind by an earlier run either,
# because every arm reads only the bytes appended after its own launch.
$baseline = Invoke-ShellRun -Label 'baseline' -Arguments @() -SettleOn 'launched,' -SettleSeconds 8
if (-not $baseline.reachedLaunch) {
    Write-Verdict 3 'NO VERDICT' ("the shell wrote no `launched` line within {0}s on the control " +
        'run, so it never started and nothing below was measured. Region was {1} byte(s).' -f
        $PerRunTimeoutSeconds, $baseline.bytes)
}
$baselineClean = -not ($baseline.region -match 'unhandled:')
Add-Arm 'BASELINE' 'a launch with no --fault writes no `unhandled:` line' $baselineClean `
    $(if ($baselineClean) { 'the flag is inert when absent, and the EFFECT lines below are the injection''s' }
      else { 'an ordinary launch already logs an `unhandled:` line, so every EFFECT arm below would pass over nothing' })

# --------------------------------------------------------------------------- EFFECT
$cases = @(
    [pscustomobject]@{ arm = 'EFFECT.xaml';      kind = 'ui';        handler = 'xaml'
                       pattern = 'unhandled:\s*\[xaml\]'
                       what = 'Application.UnhandledException wrote its line for a UI-thread throw' }
    [pscustomobject]@{ arm = 'EFFECT.appdomain'; kind = 'appdomain'; handler = 'appdomain'
                       pattern = 'unhandled:\s*\[appdomain'
                       what = 'AppDomain.CurrentDomain.UnhandledException wrote its line for a non-UI throw' }
    [pscustomobject]@{ arm = 'EFFECT.task';      kind = 'task';      handler = 'task'
                       pattern = 'unhandled:\s*\[unobserved-task\]'
                       what = 'TaskScheduler.UnobservedTaskException wrote its line for a faulted task nobody awaits' }
)

foreach ($case in $cases) {
    $arguments = @('--fault', $case.kind)
    $armedHere = $ProveRed -and ($ArmHandler -eq $case.handler)
    if ($armedHere) { $arguments += @('--fault-unregister', $case.handler) }

    $run = Invoke-ShellRun -Label $case.kind -Arguments $arguments -SettleOn $case.pattern
    if ($null -ne $run.failure) {
        Write-Verdict 3 'NO VERDICT' ("run '{0}' could not be launched: {1}" -f $case.kind, $run.failure)
    }
    if (-not $run.reachedInjection) {
        # Said as NO VERDICT rather than as a broken arm. A run that never reached the injection
        # tells us nothing about the handler, and calling it a failure would report a launch
        # problem as a dead handler - which is the inversion DEF-079 is about.
        Write-Verdict 3 'NO VERDICT' ("run '{0}' never logged `fault: injecting`, so no fault was " +
            'raised and this arm measured nothing. Region was {1} byte(s).' -f $case.kind, $run.bytes)
    }
    $held = [bool] ($run.region -match $case.pattern)
    $detail = if ($held) {
        (($run.region -split "`r?`n" | Where-Object { $_ -match $case.pattern } | Select-Object -First 1)).Trim()
    } elseif ($armedHere) {
        'ARMED: this handler was never attached, and nothing wrote its line'
    } else {
        'the fault was injected and no line naming this handler was appended'
    }
    Add-Arm $case.arm $case.what $held $detail
}

# --------------------------------------------------------------------- an ungraded probe
# NOT an arm, and deliberately not one. `--fault dispatcher` throws on the same UI thread from a
# callback posted to the DispatcherQueue, and on this host that reaches NO handler at all: the
# process disappears having written `fault: injecting` and nothing after it, which is precisely the
# silence DEF-079 was raised about. It is carried here as a probe rather than as a failing arm
# because it is a second defect (DEF-085) rather than a fault in the three handlers this lane
# grades, and because a lane whose verdict flips on somebody fixing a different defect is a lane
# that stops meaning what it says.
$probe = Invoke-ShellRun -Label 'dispatcher' -Arguments @('--fault', 'dispatcher') -SettleOn 'unhandled:'
$probeCaught = [bool] ($probe.region -match 'unhandled:')
$Notes += ('ungraded probe, --fault dispatcher: a throw from a DispatcherQueue callback on the UI ' +
    'thread was caught by {0}. DEF-085 carries it.') -f
    $(if ($probeCaught) { 'a handler, which the arms above do not require' }
      else { 'NO handler - the process vanished after `fault: injecting` with nothing appended' })
Write-Host ("  {0,-18} {1,-6} {2}" -f 'PROBE.dispatcher', $(if ($probeCaught) { 'caught' } else { 'silent' }),
    'a DispatcherQueue callback throw (ungraded, DEF-085)')

# --------------------------------------------------------------------------- the verdict
$broke = @($Arms | Where-Object { -not $_.held })
$brokeIds = ($broke | ForEach-Object { $_.id }) -join ', '

if ($ProveRed) {
    $expected = 'EFFECT.' + $(if ($ArmHandler -eq 'xaml') { 'xaml' } elseif ($ArmHandler -eq 'appdomain') { 'appdomain' } else { 'task' })
    $onlyExpectedBroke = ($broke.Count -eq 1) -and ($broke[0].id -eq $expected)
    if ($onlyExpectedBroke) {
        Write-Verdict 0 'PASS (armed)' (("left the {0} handler unregistered and {1} broke while " +
            'BASELINE and the other two EFFECT arms held. So each arm reads the line its own ' +
            'handler wrote, and none of them is satisfied by another handler''s.') -f $ArmHandler, $expected)
    }
    Write-Verdict 1 'FAIL (arming)' ("expected {0} alone to break; broke: {1}" -f $expected,
        $(if ($brokeIds) { $brokeIds } else { 'nothing - unregistering a handler changed no arm, so the arms are not reading what they claim' }))
}

if ($broke.Count -gt 0) {
    Write-Verdict 1 'FAIL' ("{0} of {1} arm(s) broke: {2}" -f $broke.Count, $Arms.Count, $brokeIds)
}
$reason = ('all {0} arm(s) held: a control launch wrote no `unhandled:` line, and each of the ' +
    'three top-level handlers was then made to fire on purpose and was observed writing the line ' +
    'naming it, read out of the log by a process that did not write it. The 0xC000027B stowed ' +
    'exception DEF-079 was found through is NOT reproduced here and notMeasured[] says so.') -f $Arms.Count
Write-Verdict 0 'PASS' $reason
