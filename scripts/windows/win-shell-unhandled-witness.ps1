<#
.SYNOPSIS
    DEF-079 and DEF-085 effect witness: each of the four routes an exception can take out of this
    shell is made to fire on purpose, and the line the handler or guard wrote is read back out of
    shell-startup.log by a different process.

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
      dispatcher  thrown from a DispatcherQueue callback   -> the guard at the posting site, DEF-085

    Each route writes a line naming itself, and this script requires that specific line.

    THE FOURTH ARM MOVED, and this is why. It ran here as an UNGRADED PROBE while DEF-085 was open:
    a throw from a DispatcherQueue callback reached NO handler at all - the process disappeared
    having written `fault: injecting` and nothing after it, in the same binary and the same run in
    which the other three each wrote their handler's line - and grading it then would have made this
    lane's verdict depend on a different defect being fixed. DEF-085 is now fixed: the shell posts
    through GuardedDispatch.TryEnqueueGuarded, which catches at the site that owns the callback,
    writes `unhandled: [dispatcher site=<who>]` through StartupLog and deliberately degrades rather
    than taking the window down. So the route now has something of this product's own to grade, the
    probe is a fourth EFFECT arm, and the silence it used to report is what -ProveRed reproduces on
    purpose.

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

    THE STOWED EXCEPTION, which this lane once said it could not raise. DEF-086 recorded that a
    real 0xC000027B could not be produced on demand. It can, and this lane produces one every time
    it is armed on `dispatcher`: an UNGUARDED throw from a DispatcherQueue callback terminates the
    process with `Exception code: 0xc000027b`, `Faulting module name: CoreMessagingXP.dll`, at the
    same fault offset as the Skills crash of 2026-09-02 that DEF-077 and DEF-079 were found
    through. So every run here also reads the Windows Application log for a WER Application Error
    1000 raised by MCPRouter.Shell.exe inside that run's own window, and carries it in runs[] as
    `werCrash`. The recorder is again not the writer: WER is written by the operating system after
    the process is gone, and read here through a different API than the log.

    That is what settles DEF-086 in the negative: on the armed run the process fail-fasts at
    0xC000027B and NO `unhandled:` line is written, so Microsoft.UI.Xaml.Application.UnhandledException
    does not see this class. It is why DEF-085's remedy is a guard at the posting site rather than
    another top-level handler.

    WHAT IS STILL NOT MEASURED: that the ORIGINAL Skills crash took this identical path. The
    identity here is the exception code, the faulting module and the fault offset, which is strong
    and is not the same as a stack. notMeasured[] carries it.

.PARAMETER ProveRed
    Arming. Launches the run for one handler with `--fault-unregister <handler>` as well, so that
    handler is genuinely never attached - a defect this product can have - and requires exactly that
    arm to break while BASELINE and the other EFFECT arms hold. `dispatcher` is the one value that
    unregisters nothing: it posts the same callback with NO guard around it, which is precisely the
    state DEF-085 recorded, and the arm then breaks because nothing writes a line.

.PARAMETER ArmHandler
    Which handler -ProveRed leaves unregistered - `xaml`, `appdomain`, `task` or `dispatcher`.
    Defaults to `task`, the one route whose fault does not terminate the process, so an arming run
    cannot leave a Windows Error Reporting dialog on a station this lane cannot see. `dispatcher`
    arming DOES terminate the process, the same way the unguarded callback did before DEF-085 was
    fixed, which is the point of it.

.NOTES
    Exit 0 pass, 1 fail, 3 NO VERDICT.
#>
[CmdletBinding()]
param(
    [string] $Out = 'planning/evidence/WIN-SHELL/run',
    [string] $ExePath = '',
    [int]    $PerRunTimeoutSeconds = 90,
    [ValidateSet('xaml', 'appdomain', 'task', 'dispatcher')]
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
        defect      = 'DEF-079, DEF-085'
        subject     = 'MCPRouter.Shell.App top-level unhandled-exception handlers, and the DEF-085 dispatcher guard'
        writer      = 'the three handlers and the dispatcher guard, running inside the shell process'
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
            'that an UNGUARDED DispatcherQueue callback still reaches no handler - the DEF-085 finding is not re-measured on a normal run. -ProveRed dispatcher is where that state is reproduced, and EFFECT.dispatcher grades the guard rather than the framework',
            'that the ORIGINAL Skills crash of 2026-09-02 took the same path as the stowed exception this lane now raises when armed on dispatcher. What matches is the exception code, the faulting module and the fault offset in WER; nothing here compares stacks (DEF-086)',
            'that a handler fires in a RELEASE build - the injection is compiled out outside DEBUG, so this lane grades the Debug binary only',
            'that the log survives a process kill mid-write - StartupLog appends synchronously per line, which is assumed rather than witnessed here'
        )
        notes       = $Notes
        host        = $env:COMPUTERNAME
        psVersion   = $PSVersionTable.PSVersion.ToString()
    }
    # One file per arming subject, so a dispatcher arming cannot overwrite the record of a task
    # arming. `task` keeps the original name because CASE-0342 cites that path.
    $armedName = if ($ArmHandler -eq 'task') { 'unhandled-witness-armed.json' }
                 else { "unhandled-witness-armed-$ArmHandler.json" }
    $path = Join-Path $OutDir $(if ($ProveRed) { $armedName } else { 'unhandled-witness.json' })
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

function Get-WerCrash {
    <#
      The operating system's own record of a process that died, read after it died. Application
      Error 1000 carries the exception code, the faulting module and the fault offset, which is
      what makes a 0xC000027B stowed exception nameable rather than inferred from a process that
      simply vanished (DEF-086).
    #>
    param([datetime] $Since)
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName = 'Application'; Id = 1000; StartTime = $Since
            } -MaxEvents 20 -ErrorAction Stop |
                Where-Object { $_.Message -match 'MCPRouter\.Shell\.exe' }
            $event = @($events) | Select-Object -First 1
            if ($null -ne $event) {
                $text = $event.Message
                $code = if ($text -match 'Exception code:\s*(\S+)') { $Matches[1] } else { '' }
                $module = if ($text -match 'Faulting module name:\s*([^,]+)') { $Matches[1] } else { '' }
                $offset = if ($text -match 'Fault offset:\s*(\S+)') { $Matches[1] } else { '' }
                return [pscustomobject]@{
                    when          = $event.TimeCreated.ToString('o')
                    exceptionCode = $code
                    module        = $module
                    faultOffset   = $offset
                    isStowed      = ($code -eq '0xc000027b')
                    readBy        = 'Get-WinEvent over the Windows Application log, after the process exited'
                }
            }
        } catch {
            # Get-WinEvent THROWS when a filter matches nothing, so an empty result and a broken
            # read arrive the same way. Told apart here, because "no crash" is a finding and "the
            # log could not be read" is the absence of one.
            if ($_.Exception.Message -match 'No events were found') {
                return [pscustomobject]@{ when = ''; exceptionCode = ''; module = ''; faultOffset = ''
                                          isStowed = $false
                                          readBy = 'the Application log was read and holds no Application Error for this run - the process did not crash' }
            }
            return [pscustomobject]@{ when = ''; exceptionCode = ''; module = ''; faultOffset = ''
                                      isStowed = $false
                                      readBy = "the Application log could not be read: $($_.Exception.Message)" }
        }
        Start-Sleep -Seconds 2
    }
    return $null
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
    $runStart = (Get-Date).AddSeconds(-2)
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
        werCrash         = (Get-WerCrash -Since $runStart)
        failure          = $null
    }
    $script:Runs += $result
    return $result
}

Write-Host ''
Write-Host  'win-shell unhandled witness: DEF-079 three top-level handlers, DEF-085 dispatcher guard'
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
    # Promoted from an ungraded probe when DEF-085 was fixed. It grades a guard rather than a
    # framework handler, and it is the only arm whose subject is code this repository owns.
    [pscustomobject]@{ arm = 'EFFECT.dispatcher'; kind = 'dispatcher'; handler = 'dispatcher'
                       pattern = 'unhandled:\s*\[dispatcher'
                       what = 'the DEF-085 guard wrote its line for a throw inside a DispatcherQueue callback' }
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
    } elseif ($armedHere -and $case.handler -eq 'dispatcher') {
        'ARMED: the callback was posted with no guard, and nothing wrote its line - DEF-085 as found'
    } elseif ($armedHere) {
        'ARMED: this handler was never attached, and nothing wrote its line'
    } else {
        'the fault was injected and no line naming this handler was appended'
    }
    Add-Arm $case.arm $case.what $held $detail
}

# --------------------------------------------- what WER says about the dispatcher run
# Recorded rather than graded, and deliberately so: an arm here would break on the -ProveRed
# dispatcher run as well as EFFECT.dispatcher, and the arming contract is that EXACTLY one arm
# breaks. The values are in runs[].werCrash either way.
$dispatcherRun = @($Runs | Where-Object { $_.label -eq 'dispatcher' }) | Select-Object -First 1
if ($null -ne $dispatcherRun -and $null -ne $dispatcherRun.werCrash) {
    $Notes += if ($dispatcherRun.werCrash.isStowed) {
        ('WER, read out of the Windows Application log after the process was gone: the dispatcher ' +
         'run ended in Application Error 1000, exception code {0}, faulting module {1}, fault ' +
         'offset {2}. That is a REAL STATUS_STOWED_EXCEPTION raised on demand, which DEF-086 said ' +
         'this repository could not do.') -f $dispatcherRun.werCrash.exceptionCode,
            $dispatcherRun.werCrash.module, $dispatcherRun.werCrash.faultOffset
    } else {
        'WER, read out of the Windows Application log after the process was gone: the dispatcher ' +
        'run left NO Application Error. The guard caught the throw, so the process did not ' +
        'fail-fast at 0xC000027B the way the unguarded callback does - which is a second effect ' +
        'of DEF-085''s fix, recorded by the operating system rather than by the shell.'
    }
}

# ------------------------------------------------------- where the fourth arm came from
$Notes += ('EFFECT.dispatcher was an ungraded probe until DEF-085 was fixed: the route reached no ' +
    'handler and the process vanished after `fault: injecting` with nothing appended. It is graded ' +
    'now because the shell guards its own posting sites, so the line it requires is written by this ' +
    'product rather than by the framework. -ProveRed dispatcher removes that guard and reproduces ' +
    'the silence.')

# --------------------------------------------------------------------------- the verdict
$broke = @($Arms | Where-Object { -not $_.held })
$brokeIds = ($broke | ForEach-Object { $_.id }) -join ', '

if ($ProveRed) {
    $expected = 'EFFECT.' + $ArmHandler
    $onlyExpectedBroke = ($broke.Count -eq 1) -and ($broke[0].id -eq $expected)
    if ($onlyExpectedBroke) {
        $how = if ($ArmHandler -eq 'dispatcher') { 'posted the callback with no guard around it' }
               else { "left the $ArmHandler handler unregistered" }
        Write-Verdict 0 'PASS (armed)' (('{0} and {1} broke while BASELINE and the other EFFECT ' +
            'arms held. So each arm reads the line its own handler or guard wrote, and none of ' +
            'them is satisfied by another''s.') -f $how, $expected)
    }
    Write-Verdict 1 'FAIL (arming)' ("expected {0} alone to break; broke: {1}" -f $expected,
        $(if ($brokeIds) { $brokeIds } else { 'nothing - unregistering a handler changed no arm, so the arms are not reading what they claim' }))
}

if ($broke.Count -gt 0) {
    Write-Verdict 1 'FAIL' ("{0} of {1} arm(s) broke: {2}" -f $broke.Count, $Arms.Count, $brokeIds)
}
$reason = ('all {0} arm(s) held: a control launch wrote no `unhandled:` line, and each of the ' +
    'three top-level handlers and the DEF-085 dispatcher guard was then made to fire on purpose ' +
    'and was observed writing the line naming it, read out of the log by a process that did not ' +
    'write it. On this run the dispatcher throw was GUARDED, so WER holds no Application Error ' +
    'for it; the 0xC000027B stowed exception DEF-079 was found through is what -ProveRed ' +
    'dispatcher raises instead, and notes[] carries what WER said either way.') -f $Arms.Count
Write-Verdict 0 'PASS' $reason
