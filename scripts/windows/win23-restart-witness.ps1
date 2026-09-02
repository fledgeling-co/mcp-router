<#
.SYNOPSIS
    WIN23 effect witness, second half: a daemon the Windows task scheduler actually starts, actually
    loses, and actually brings back.

.DESCRIPTION
    WHY THIS LANE EXISTS. scripts/windows/win23-logon-task-witness.ps1 measures the REGISTRATION and
    says so in its own notMeasured[]. DEF-081 recorded what was left: the two things the operator is
    actually promised - that the daemon comes up at logon, and that a crashed one comes back - had
    never been watched to happen, and rested on the scheduler honouring a manifest this repository
    had confirmed was present and had never confirmed was honoured.

    THAT TRUST WAS MISPLACED, AND THIS LANE IS HOW WE KNOW. Measured 2026-09-03, four registrations:
    a task carrying RestartOnFailure with a 60-second interval and a count of 3 was started, its
    process was killed, and the scheduler never restarted it - watched for 150 seconds, on the
    unified scheduling engine and the legacy one, for a run started by a trigger and one started on
    demand. The same block DID restart, three times at exactly 60 seconds, a task whose Command
    named a file that does not exist. So RestartOnFailure governs a task that fails to LAUNCH and
    says nothing at all about an action that launched and then died, which is the only case
    "restarts on crash" was ever about. The product now writes a Repetition on the trigger as well,
    and DEF-320 carries the finding.

    WHICH OF THE TWO PROMISES THIS SETTLES, said plainly because the row it closes is about exactly
    that distinction:

      "a crashed daemon comes back"   WITNESSED HERE. A real process is started by the scheduler
                                      from a real trigger, killed by this lane, and observed to
                                      return under a different process id.
      "the daemon comes up at logon"  STILL NOT WITNESSED. Proving it needs a logon, and this lane
                                      must not log the machine out. DEF-081 keeps that half, with
                                      the LogonTrigger's presence and its repetition asserted by the
                                      CLAIM arm below and its FIRING resting on the scheduler's own
                                      contract.

    THE RECORDERS, none of which wrote anything:

      Get-ScheduledTask / Get-ScheduledTaskInfo   the ScheduledTasks module over the Task
                                                  Scheduler's WMI provider. LastRunTime and
                                                  LastTaskResult are the scheduler's account of its
                                                  own runs, in a process that is not the writer.
      Get-CimInstance Win32_Process               the operating system's process table. This is
                                                  what makes "it came back" a different process id
                                                  rather than a report from the thing that came
                                                  back.
      the daemon's own append-only run log        CARRIED AND GRADED BY NOTHING. A process
                                                  reporting its own start is the writer reporting
                                                  on itself. It is in the evidence so a reader can
                                                  see whether it agrees with the two recorders.

    THE ONE SUBSTITUTION, and it is the reason this file is separate from the registration lane.
    A repetition attached to a trigger does not apply to a run started on demand - measured, twice -
    so the live half cannot use Start-ScheduledTask and must use a trigger that fires by itself.
    This lane takes the document the SHIPPED supervisor built and replaces its LogonTrigger element
    with a TimeTrigger a minute out, carrying the product's own Repetition block verbatim. What is
    substituted is the trigger TYPE and nothing else: every Setting, the repetition interval, the
    principal, the action and the instances policy are the product's. The claim that the trigger is
    a LOGON trigger is asserted separately, on the product's unmodified registration, by the CLAIM
    arm.

.PARAMETER ProveRed
    Arming, and the planted defect is a historical one rather than an invented one: the Repetition
    block is stripped from the live document, leaving exactly the RestartOnFailure-only task the
    product registered until 2026-09-03. Exactly LIVE.restarted must break and every other arm must
    hold. A run in this mode that reports PASS has shown the restart assertion cannot fail.

.NOTES
    Runs under pwsh 7, and is written to PARSE under Windows PowerShell 5.1 because
    scripts/windows/ps-parse-gate.py holds every tracked .ps1 to that. ASCII only, for the same
    reason win23-logon-task-witness.ps1 is.

    Takes several minutes: a trigger has to fire, and a repetition interval has to elapse. The
    scheduler's minimum repetition interval is one minute and nothing can make it shorter.

    Exit 0 pass, 1 fail, 3 NO VERDICT - the lane could not run, which is not a pass.
#>
[CmdletBinding()]
param(
    [string] $ClaimTaskName = '\MCPRouter\WIN23 Restart Witness registration (transient)',
    [string] $LiveTaskName  = '\MCPRouter\WIN23 Restart Witness live (transient)',
    [string] $Out = 'planning/evidence/WIN23/run',
    [int]    $Port = 8891,
    [int]    $TriggerWaitSeconds = 180,
    [int]    $RestartWaitSeconds = 210,
    [switch] $ProveRed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutDir = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $RepoRoot $Out }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$Arms = @()
$Notes = @()
$Timeline = @()

function Add-Arm {
    param([string] $Id, [string] $What, [bool] $Held, [string] $Detail)
    $script:Arms += [pscustomobject]@{ id = $Id; what = $What; held = $Held; detail = $Detail }
    $mark = if ($Held) { 'HELD' } else { 'BROKE' }
    Write-Host ("  {0,-16} {1,-6} {2}" -f $Id, $mark, $What)
    if ($Detail) { Write-Host ("                          {0}" -f $Detail) }
}

function Note-Moment {
    param([string] $What, [string] $Detail)
    $script:Timeline += [pscustomobject]@{
        at = (Get-Date).ToUniversalTime().ToString('o'); what = $What; detail = $Detail }
    Write-Host ("  {0}  {1} {2}" -f (Get-Date).ToString('HH:mm:ss'), $What, $Detail)
}

function Write-Verdict {
    param([int] $Code, [string] $Verdict, [string] $Reason, $DaemonLog = $null)
    $doc = [ordered]@{
        lane        = 'win23-restart-witness'
        rung        = 'effect-witness'
        subject     = 'MCPRouter.Shell.Live.Lifecycle.LogonTaskSupervisor, the "restarts on crash" claim'
        writer      = 'schtasks.exe /Create /XML, with the document the shipped supervisor built'
        recorders   = @(
            'Get-ScheduledTaskInfo - the Task Scheduler WMI provider, for LastRunTime and LastTaskResult',
            'Get-CimInstance Win32_Process - the operating system process table, for the process identity'
        )
        recorderIsNotWriter = $true
        arming      = [bool] $ProveRed
        claimTask   = $ClaimTaskName
        liveTask    = $LiveTaskName
        verdict     = $Verdict
        reason      = $Reason
        arms        = $Arms
        armsHeld    = @($Arms | Where-Object { $_.held }).Count
        armsTotal   = $Arms.Count
        timeline    = $Timeline
        writerSelfReport = $DaemonLog
        writerSelfReportIsNotEvidence =
            'the daemon''s own append-only run log. Graded by nothing here: a process reporting its ' +
            'own start is the writer reporting on itself. It is carried so a reader can see whether ' +
            'it agrees with the two recorders that did the grading.'
        substitution =
            'the live task carries a TimeTrigger where the product writes a LogonTrigger, because a ' +
            'trigger repetition does not apply to an on-demand start and this lane must not log the ' +
            'machine out. Every Setting, the repetition interval, the principal, the action and the ' +
            'instances policy are the product''s own document, unmodified.'
        notMeasured = @(
            'that the trigger fires AT LOGON - this lane does not log the user out, and DEF-081 keeps that half',
            'that the daemon under supervision is the router daemon - the payload is app/windows/MCPRouter.Witness.Daemon, a harness binary that starts, records its own start and waits to be killed, because this tree''s router daemon is TypeScript under Node rather than a Windows executable a Task Scheduler action can name'
        )
        notes       = $Notes
        host        = $env:COMPUTERNAME
        psVersion   = $PSVersionTable.PSVersion.ToString()
    }
    $path = Join-Path $OutDir $(if ($ProveRed) { 'restart-witness-armed.json' } else { 'restart-witness.json' })
    [System.IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 6),
        (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ("win23 restart witness: {0} - {1}" -f $Verdict, $Reason)
    Write-Host ("                       wrote {0}" -f $path)
    exit $Code
}

# --------------------------------------------------------------------------- the recorders
# Resolved before anything is registered, and their absence is a NO VERDICT rather than a pass. A
# lane whose recorder is missing and which reports clean is the failure this rung exists to prevent.
foreach ($cmd in @('Get-ScheduledTask', 'Get-ScheduledTaskInfo', 'Get-CimInstance')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Verdict 3 'NO VERDICT' ("{0} is not available on this host, so there is no recorder " -f $cmd +
            'independent of the writer. A run with no recorder is not a run that passed.')
    }
}

function Split-TaskName {
    param([string] $Name)
    $leaf = Split-Path -Leaf $Name
    $path = Split-Path -Parent $Name
    if (-not $path.EndsWith('\')) { $path = $path + '\' }
    return @($path, $leaf)
}

function Read-Task {
    param([string] $Name)
    $parts = Split-TaskName $Name
    return Get-ScheduledTask -TaskPath $parts[0] -TaskName $parts[1] -ErrorAction SilentlyContinue
}

function Read-Info {
    param([string] $Name)
    $parts = Split-TaskName $Name
    return Get-ScheduledTaskInfo -TaskPath $parts[0] -TaskName $parts[1] -ErrorAction SilentlyContinue
}

function Remove-Task {
    param([string] $Name)
    & schtasks /End /TN $Name 2>&1 | Out-Null
    & schtasks /Delete /TN $Name /F 2>&1 | Out-Null
}

# --------------------------------------------------------------------------- the two binaries
# Both are built here rather than assumed on disk. A witness that measured a stale assembly would
# report on code nobody has now, which is the shape that let a campaign stay green over a build that
# no longer existed.
$LiveProj = Join-Path $RepoRoot 'app\windows\MCPRouter.Shell.Live\MCPRouter.Shell.Live.csproj'
$DaemonProj = Join-Path $RepoRoot 'app\windows\MCPRouter.Witness.Daemon\MCPRouter.Witness.Daemon.csproj'
foreach ($proj in @($LiveProj, $DaemonProj)) {
    Write-Host ("win23 restart witness: building {0}" -f (Split-Path -Leaf $proj))
    $build = & dotnet build $proj -c Debug -v q --nologo 2>&1
    if ($LASTEXITCODE -ne 0) {
        $Notes += ($build | Out-String)
        Write-Verdict 3 'NO VERDICT' ("{0} did not build, so nothing was measured." -f (Split-Path -Leaf $proj))
    }
}

$OutBin = Join-Path $RepoRoot 'app\windows\MCPRouter.Shell.Live\bin\Debug\net8.0'
$LiveDll = Join-Path $OutBin 'MCPRouter.Shell.Live.dll'
$ModelDll = Join-Path $OutBin 'MCPRouter.Shell.Model.dll'
foreach ($dll in @($ModelDll, $LiveDll)) {
    if (-not (Test-Path $dll)) {
        Write-Verdict 3 'NO VERDICT' ("the build reported success and {0} is not on disk." -f $dll)
    }
    [void][System.Reflection.Assembly]::LoadFrom($dll)
}

$DaemonExe = Join-Path $RepoRoot 'app\windows\MCPRouter.Witness.Daemon\bin\Debug\net8.0\mcprouter-witness-daemon.exe'
if (-not (Test-Path $DaemonExe)) {
    Write-Verdict 3 'NO VERDICT' ("the daemon build reported success and {0} is not on disk." -f $DaemonExe)
}
$DaemonName = Split-Path -Leaf $DaemonExe
$DaemonLogPath = Join-Path (Split-Path -Parent $DaemonExe) 'witness-daemon-runs.log'

function Read-DaemonProcesses {
    # The process table, not Get-Process: Win32_Process carries ExecutablePath, and matching on the
    # full path is what stops this lane counting somebody else's identically named process.
    return @(Get-CimInstance Win32_Process -Filter ("Name='{0}'" -f $DaemonName) -ErrorAction SilentlyContinue |
             Where-Object { $_.ExecutablePath -eq $DaemonExe })
}

# --------------------------------------------------------------------------- the writer
$cli = [MCPRouter.Shell.Live.Lifecycle.SchtasksCli]::new([string] $null)
$claimSupervisor = [MCPRouter.Shell.Live.Lifecycle.LogonTaskSupervisor]::new($cli, $ClaimTaskName, [string] $null)
$liveSupervisor = [MCPRouter.Shell.Live.Lifecycle.LogonTaskSupervisor]::new($cli, $LiveTaskName, [string] $null)
$config = [MCPRouter.Shell.Model.Lifecycle.DaemonLifecycleConfig]::new(
    [MCPRouter.Shell.Model.Lifecycle.DaemonSupervisionKind]::LogonTask,
    $Port, $DaemonExe, $true, 60)

Write-Host ''
Write-Host  'win23 restart witness: the crash half of the supervision claim'
Write-Host ("                       daemon   {0}" -f $DaemonExe)
Write-Host ("                       writer   MCPRouter.Shell.Live -> schtasks.exe /Create /XML")
Write-Host ("                       recorder Get-ScheduledTaskInfo + Win32_Process")
if ($ProveRed) {
    Write-Host '                       ARMING: the Repetition block is stripped from the live document,'
    Write-Host '                               leaving the RestartOnFailure-only task the product used to write'
    $Notes += ('ARMING RUN: the live task is registered from the product document with its Repetition ' +
        'block removed - the exact registration this product shipped until 2026-09-03. Exactly ' +
        'LIVE.restarted is required to break. A run in this mode that reports PASS has shown the ' +
        'restart assertion cannot fail, which is a defect in this lane and not in the product.')
}
Write-Host ''

Remove-Item $DaemonLogPath -Force -ErrorAction SilentlyContinue
$registeredClaim = $false
$registeredLive = $false

try {
    # ----------------------------------------------------------------- BASELINE
    foreach ($name in @($ClaimTaskName, $LiveTaskName)) {
        if ($null -ne (Read-Task $name)) {
            $Notes += ("a task named '{0}' was already registered at start and was removed before the " -f $name +
                       'baseline arm. That is leftover from an interrupted run of this lane.')
            Remove-Task $name
        }
    }
    $strayDaemons = Read-DaemonProcesses
    foreach ($stray in $strayDaemons) {
        $Notes += ('a witness daemon was already running at start (pid {0}) and was stopped.' -f $stray.ProcessId)
        Stop-Process -Id $stray.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1

    $baselineClean = ($null -eq (Read-Task $ClaimTaskName)) -and ($null -eq (Read-Task $LiveTaskName)) -and
                     (@(Read-DaemonProcesses).Count -eq 0)
    Add-Arm 'BASELINE' 'neither task is registered and no witness daemon is running before this run' `
        $baselineClean `
        $(if ($baselineClean) { 'so every process and every run time below belongs to this run' }
          else { 'something survived cleanup; every arm below would be about it rather than about this run' })
    if (-not $baselineClean) {
        Write-Verdict 1 'FAIL' 'the machine was not clean at the start, so nothing below is attributable.'
    }

    # ----------------------------------------------------------------- CLAIM, on the product's own registration
    # This half registers what the product actually writes - a LogonTrigger, unmodified - and reads
    # it back through the WMI provider. It settles the SHAPE of the promise. The live half below
    # settles whether the shape does anything.
    $claimResult = $claimSupervisor.Register($config)
    $registeredClaim = $true
    if (-not $claimResult.Succeeded) {
        $Notes += ('schtasks exit {0}: {1} {2}' -f $claimResult.ExitCode, $claimResult.StandardOutput, $claimResult.StandardError)
        Add-Arm 'CLAIM.accepted' 'the scheduler accepts the document the supervisor builds' $false `
            ('schtasks refused it, exit {0}. The message is in notes[].' -f $claimResult.ExitCode)
        Write-Verdict 1 'FAIL' 'the scheduler refused the XML the supervisor built.'
    }
    $claimTask = Read-Task $ClaimTaskName
    if ($null -eq $claimTask) {
        Add-Arm 'CLAIM.accepted' 'the recorder reports the task present after registration' $false `
            'schtasks reported success and the independent recorder sees nothing.'
        Write-Verdict 1 'FAIL' 'the writer claimed success and the recorder disagrees.'
    }
    Add-Arm 'CLAIM.accepted' 'the recorder reports the product registration present' $true `
        ("state={0}" -f $claimTask.State)

    # The repetition, read out of the SCHEDULER rather than out of the config that asked for it.
    # This is the arm that would have gone red against the document the product wrote before
    # DEF-320: RestartCount was 3 and there was no repetition anywhere.
    $logonTrigger = @($claimTask.Triggers) |
        Where-Object { $null -ne $_.CimClass -and $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' } |
        Select-Object -First 1
    $repInterval = if ($null -ne $logonTrigger -and $null -ne $logonTrigger.Repetition) {
        [string] $logonTrigger.Repetition.Interval } else { '' }
    Add-Arm 'CLAIM.repetition' 'the logon trigger carries a repetition, which is what restarts a crashed daemon' `
        (-not [string]::IsNullOrWhiteSpace($repInterval)) `
        ("Repetition.Interval={0}; RestartOnFailure count={1}" -f
            $(if ($repInterval) { $repInterval } else { '<none>' }), $claimTask.Settings.RestartCount)
    Add-Arm 'CLAIM.ignorenew' 'the instances policy discards a repetition that fires while the daemon is alive' `
        ([string] $claimTask.Settings.MultipleInstances -eq 'IgnoreNew') `
        ("MultipleInstances={0}" -f $claimTask.Settings.MultipleInstances)

    [void] $claimSupervisor.Unregister()
    $registeredClaim = $false

    # ----------------------------------------------------------------- the live document
    $productXml = $liveSupervisor.BuildTaskXml($config)
    if ($ProveRed) {
        # The planted defect, and it is the product's own history rather than an invention.
        $productXml = [System.Text.RegularExpressions.Regex]::Replace(
            $productXml, '(?s)\s*<Repetition>.*?</Repetition>', '')
        if ($productXml -match '<Repetition>') {
            Write-Verdict 3 'NO VERDICT' 'the arming edit did not remove the repetition, so nothing was armed.'
        }
    }
    $repetitionBlock = ''
    $repMatch = [System.Text.RegularExpressions.Regex]::Match($productXml, '(?s)<Repetition>.*?</Repetition>')
    if ($repMatch.Success) { $repetitionBlock = '      ' + $repMatch.Value + "`n" }

    $startBoundary = (Get-Date).AddSeconds(70).ToString('yyyy-MM-ddTHH:mm:ss')
    $timeTrigger = "    <TimeTrigger>`n      <Enabled>true</Enabled>`n" +
                   ("      <StartBoundary>{0}</StartBoundary>`n" -f $startBoundary) +
                   $repetitionBlock + "    </TimeTrigger>`n"
    $liveXml = [System.Text.RegularExpressions.Regex]::Replace(
        $productXml, '(?s)[ ]*<LogonTrigger>.*?</LogonTrigger>\r?\n', $timeTrigger)
    if ($liveXml -match '<LogonTrigger>') {
        Write-Verdict 3 'NO VERDICT' 'the trigger substitution did not take, so the live task would never fire.'
    }

    $xmlPath = Join-Path ([System.IO.Path]::GetTempPath()) ('win23-restart-' + [guid]::NewGuid().ToString('N') + '.xml')
    [System.IO.File]::WriteAllText($xmlPath, $liveXml, (New-Object System.Text.UnicodeEncoding($false, $true)))
    $created = & schtasks /Create /TN $LiveTaskName /XML $xmlPath /F 2>&1
    $createdRc = $LASTEXITCODE
    Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
    if ($createdRc -ne 0) {
        $Notes += ($created | Out-String)
        Add-Arm 'LIVE.registered' 'the scheduler accepts the live document' $false `
            ("schtasks exit {0}; its output is in notes[]" -f $createdRc)
        Write-Verdict 1 'FAIL' 'the live task could not be registered, so nothing could be started or killed.'
    }
    $registeredLive = $true
    Note-Moment 'live task registered' ("fires at {0}" -f $startBoundary)

    # ----------------------------------------------------------------- LIVE.started
    $firstPid = 0
    $firstRun = $null
    for ($waited = 0; $waited -lt $TriggerWaitSeconds; $waited += 5) {
        Start-Sleep -Seconds 5
        $running = @(Read-DaemonProcesses)
        if ($running.Count -gt 0) { $firstPid = [int] $running[0].ProcessId; break }
    }
    $info = Read-Info $LiveTaskName
    if ($null -ne $info) { $firstRun = $info.LastRunTime }
    Add-Arm 'LIVE.started' 'the scheduler starts the daemon when the trigger fires' ($firstPid -ne 0) `
        ("pid={0}, scheduler LastRunTime={1}" -f $firstPid, $firstRun)
    if ($firstPid -eq 0) {
        Write-Verdict 1 'FAIL' ('the trigger did not produce a running daemon within {0}s, so the ' -f $TriggerWaitSeconds +
            'restart could not be measured. This is not evidence about the restart claim.')
    }
    Note-Moment 'daemon started' ("pid {0}" -f $firstPid)

    # ----------------------------------------------------------------- LIVE.killed
    Stop-Process -Id $firstPid -Force -ErrorAction SilentlyContinue
    $gone = $false
    for ($waited = 0; $waited -lt 30; $waited += 2) {
        Start-Sleep -Seconds 2
        if (@(Read-DaemonProcesses | Where-Object { [int] $_.ProcessId -eq $firstPid }).Count -eq 0) { $gone = $true; break }
    }
    $killedInfo = Read-Info $LiveTaskName
    $killedResult = if ($null -ne $killedInfo) { [long] $killedInfo.LastTaskResult } else { 0 }
    Add-Arm 'LIVE.killed' 'the process table stops reporting the daemon, and the scheduler records the run as failed' `
        ($gone -and $killedResult -ne 0) `
        ("pid {0} gone={1}, scheduler LastTaskResult=0x{2:X8}" -f $firstPid, $gone, $killedResult)
    if (-not $gone) {
        Write-Verdict 1 'FAIL' 'the daemon survived being killed, so there was no crash to recover from.'
    }
    Note-Moment 'daemon killed' ("pid {0}, LastTaskResult=0x{1:X8}" -f $firstPid, $killedResult)

    # ----------------------------------------------------------------- LIVE.restarted
    # THE ARM THAT CARRIES THE ITEM. Two recorders have to agree: a process under a DIFFERENT id
    # exists, and the scheduler's own LastRunTime has moved past the run that died. Either alone
    # would be weaker - a process id could be somebody else's launch, and a run time could advance
    # on a run that failed to start anything.
    $secondPid = 0
    $secondRun = $null
    for ($waited = 0; $waited -lt $RestartWaitSeconds; $waited += 5) {
        Start-Sleep -Seconds 5
        $running = @(Read-DaemonProcesses | Where-Object { [int] $_.ProcessId -ne $firstPid })
        if ($running.Count -gt 0) {
            $secondPid = [int] $running[0].ProcessId
            $laterInfo = Read-Info $LiveTaskName
            if ($null -ne $laterInfo) { $secondRun = $laterInfo.LastRunTime }
            break
        }
    }
    $runAdvanced = ($null -ne $secondRun) -and ($null -ne $firstRun) -and ($secondRun -gt $firstRun)
    Add-Arm 'LIVE.restarted' 'the scheduler brings the daemon back after it dies' `
        (($secondPid -ne 0) -and $runAdvanced) `
        ("first pid={0} at {1}; second pid={2} at {3}; waited up to {4}s" -f
            $firstPid, $firstRun, $(if ($secondPid) { $secondPid } else { '<none>' }),
            $(if ($secondRun) { $secondRun } else { '<none>' }), $RestartWaitSeconds)
    if ($secondPid -ne 0) { Note-Moment 'daemon restarted' ("pid {0}" -f $secondPid) }
    else { Note-Moment 'no restart observed' ("waited {0}s" -f $RestartWaitSeconds) }
}
finally {
    # This lane must not leave a scheduled task or a stray daemon behind on any path. Best effort,
    # and a cleanup failure is recorded rather than thrown, because it must not overwrite the
    # verdict the arms already reached.
    try {
        if ($registeredClaim) { [void] $claimSupervisor.Unregister() }
        if ($registeredLive) { Remove-Task $LiveTaskName }
        foreach ($proc in (Read-DaemonProcesses)) {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    catch { $Notes += ('cleanup failed: ' + $_.Exception.Message) }
}

# ----------------------------------------------------------------------- SILENCE
# The presence control. A recorder that always answered "yes, here is a task and here is a process"
# would pass BASELINE by accident of ordering and pass everything above by construction. Being
# required to say "no" at a moment when the answer is no is what separates a reader from an echo.
Start-Sleep -Seconds 3
$silent = ($null -eq (Read-Task $ClaimTaskName)) -and ($null -eq (Read-Task $LiveTaskName)) -and
          (@(Read-DaemonProcesses).Count -eq 0)
Add-Arm 'SILENCE' 'both recorders report absence once the tasks are removed and the daemon is stopped' `
    $silent `
    $(if ($silent) { 'both recorders can say no, so their yes above was a reading' }
      else { 'a recorder still reports something, so its earlier yes proves nothing' })

$daemonLog = $null
if (Test-Path $DaemonLogPath) { $daemonLog = @(Get-Content $DaemonLogPath -ErrorAction SilentlyContinue) }

$broke = @($Arms | Where-Object { -not $_.held })

if ($ProveRed) {
    $ids = ($broke | ForEach-Object { $_.id }) -join ', '
    if ($ids -eq 'LIVE.restarted') {
        Write-Verdict 0 'PASS (armed)' ('the planted defect - the RestartOnFailure-only document the ' +
            'product wrote until 2026-09-03 - broke LIVE.restarted and nothing else. The restart ' +
            'assertion is watching the scheduler and not restating the config.') $daemonLog
    }
    Write-Verdict 1 'FAIL (arming)' ("expected exactly LIVE.restarted to break; broke: {0}" -f
        $(if ($ids) { $ids } else { 'nothing - the assertion cannot fail' })) $daemonLog
}

if ($broke.Count -gt 0) {
    Write-Verdict 1 'FAIL' ("{0} of {1} arm(s) broke: {2}" -f $broke.Count, $Arms.Count,
        (($broke | ForEach-Object { $_.id }) -join ', ')) $daemonLog
}
Write-Verdict 0 'PASS' (("all {0} arm(s) held: a daemon the Windows task scheduler started was killed " +
    'and the scheduler started it again under a different process id, with the run recorded by ' +
    'Get-ScheduledTaskInfo and the identity recorded by the process table. The logon half of the ' +
    'promise is still unwitnessed and DEF-081 keeps it.') -f $Arms.Count) $daemonLog
