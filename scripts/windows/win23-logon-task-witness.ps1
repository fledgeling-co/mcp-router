<#
.SYNOPSIS
    WIN23 effect witness: the router daemon's logon task, registered for real and read back by
    the Windows task scheduler itself.

.DESCRIPTION
    WHY THIS LANE EXISTS. WIN23 shipped a supervision "mode" that was a switch statement returning
    the sentence describing itself, and a test asserting that sentence contained a substring of
    itself. DEF-074 recorded the gap and named the way out: implement the registration, and add a
    case at the effect-witness rung whose recorder is the Windows task scheduler rather than the
    application's own report. This is that case.

    THE RECORDER IS NOT THE WRITER, and that is the whole design. The registration goes through the
    shipped production path - MCPRouter.Shell.Live's LogonTaskSupervisor driving schtasks.exe with
    the Task Scheduler XML it builds. The read-back goes through Get-ScheduledTask, which is the
    ScheduledTasks module over the Task Scheduler's WMI provider: a different API, a different
    process, and a different vocabulary for the same facts. The XML says RunLevel LeastPrivilege
    and the recorder says RunLevel Limited; nothing this repository wrote translates between them,
    which is exactly what makes the agreement worth something.

    FOUR ARMS, AND TWO OF THEM ARE ABOUT THE INSTRUMENT rather than the product:

      BASELINE   the recorder must report the witness task ABSENT before anything is registered.
                 Without this arm a task left behind by an earlier run - or by a hand experiment -
                 makes every assertion below pass while this run registers nothing at all.
      EFFECT     the recorder must report the task present AND carrying all three of the claims
                 LifecyclePresentation prints to the operator: triggered at logon, un-elevated,
                 restarting on failure.
      REMOVAL    Unregister must make the task go away.
      SILENCE    the recorder must report ABSENT again afterwards. This is the presence control:
                 a recorder that always answered "yes, and here are the properties" would pass
                 BASELINE by accident of ordering and pass EFFECT by construction, and only being
                 required to say "no" at a moment when the answer is no distinguishes a reader
                 from an echo.

    WHAT THIS DOES NOT ESTABLISH, said here rather than left to be inferred from a green: that the
    trigger fires at the next logon, and that a killed daemon is actually restarted. Both need a
    logon and a kill, neither of which this lane performs, and DEF-074 stays open against them.
    What this lane settles is narrower and was previously unmeasured entirely: that the
    registration this product performs produces, in the Windows task scheduler, a task with the
    properties the product's own UI describes.

.PARAMETER TaskName
    Deliberately its own name, never the shipped one. A witness that registered and deleted the
    operator's real daemon task would break the thing it measures.

.PARAMETER Out
    Where the evidence is written. The file is the verdict; this script's stdout is commentary.

.NOTES
    Runs under pwsh 7 rather than Windows PowerShell 5.1, because it loads the net8.0 assembly the
    product ships. It is written to PARSE under 5.1 as well, because scripts/windows/ps-parse-gate.py
    holds every tracked .ps1 to that, and it is deliberately ASCII-only so the cp1252 decoding trap
    that trap guards cannot reach it.

    Exit 0 pass, 1 fail, 3 NO VERDICT - the lane could not run, which is not a pass.
#>
[CmdletBinding()]
param(
    [string] $TaskName = '\MCPRouter\WIN23 Witness (transient)',
    [string] $Out = 'planning/evidence/WIN23/run/witness.json',
    [int]    $Port = 8890,

    # Arming. Registers with RestartOnCrash FALSE and requires EFFECT.restart to BREAK while every
    # other arm holds. Without it the restart assertion is a reading nobody has watched fail, and
    # an assertion nobody has watched fail is indistinguishable from one that cannot. The mode is
    # deliberately narrow: it plants a defect the PRODUCT can actually have - an operator who turns
    # supervision off - rather than a synthetic one, so what it proves is that this lane would
    # notice that setting being ignored.
    [switch] $ProveRed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Arms = @()
$Notes = @()

function Add-Arm {
    param([string] $Id, [string] $What, [bool] $Held, [string] $Detail)
    $script:Arms += [pscustomobject]@{ id = $Id; what = $What; held = $Held; detail = $Detail }
    $mark = if ($Held) { 'HELD' } else { 'BROKE' }
    Write-Host ("  {0,-9} {1,-10} {2}" -f $Id, $mark, $What)
    if ($Detail) { Write-Host ("            {0}" -f $Detail) }
}

function Write-Verdict {
    param([int] $Code, [string] $Verdict, [string] $Reason)
    $outPath = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $RepoRoot $Out }
    $dir = Split-Path -Parent $outPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $doc = [ordered]@{
        lane        = 'win23-logon-task-witness'
        rung        = 'effect-witness'
        subject     = 'MCPRouter.Shell.Live.Lifecycle.LogonTaskSupervisor'
        writer      = 'schtasks.exe /Create /XML, driven by the shipped supervisor'
        recorder    = 'Get-ScheduledTask (ScheduledTasks module over the Task Scheduler WMI provider)'
        recorderIsNotWriter = $true
        taskName    = $TaskName
        verdict     = $Verdict
        reason      = $Reason
        arms        = $Arms
        armsHeld    = @($Arms | Where-Object { $_.held }).Count
        armsTotal   = $Arms.Count
        notMeasured = @(
            'that the trigger fires at the next logon - this lane does not log the user out',
            'that a killed daemon is restarted - this lane does not start or kill one'
        )
        notes       = $Notes
        host        = $env:COMPUTERNAME
        psVersion   = $PSVersionTable.PSVersion.ToString()
    }
    $json = $doc | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ("win23 witness: {0} - {1}" -f $Verdict, $Reason)
    Write-Host ("               wrote {0}" -f $outPath)
    exit $Code
}

# --------------------------------------------------------------------------- the recorder
# Resolved once, and its absence is a NO VERDICT rather than a pass. A lane whose recorder is
# missing and which reports clean is the failure this whole rung exists to prevent.
if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    Write-Verdict 3 'NO VERDICT' ('Get-ScheduledTask is not available on this host, so there is no ' +
        'recorder independent of the writer. A run with no recorder is not a run that passed.')
}

function Read-Effect {
    <#
      The independent read. Returns $null when the scheduler holds no such task, and a flat record
      of the facts the product's description claims when it does. Nothing here touches schtasks.exe
      or any type from the assembly under test.
    #>
    param([string] $Name)

    $leaf = Split-Path -Leaf $Name
    $path = Split-Path -Parent $Name
    if (-not $path.EndsWith('\')) { $path = $path + '\' }

    $task = Get-ScheduledTask -TaskName $leaf -TaskPath $path -ErrorAction SilentlyContinue
    if ($null -eq $task) { return $null }

    $triggerClasses = @()
    foreach ($trigger in @($task.Triggers)) {
        if ($null -ne $trigger -and $null -ne $trigger.CimClass) {
            $triggerClasses += $trigger.CimClass.CimClassName
        }
    }
    $action = @($task.Actions)[0]

    return [pscustomobject]@{
        present         = $true
        state           = [string] $task.State
        triggerClasses  = $triggerClasses
        hasLogonTrigger = ($triggerClasses -contains 'MSFT_TaskLogonTrigger')
        runLevel        = [string] $task.Principal.RunLevel
        logonType       = [string] $task.Principal.LogonType
        restartCount    = [int] $task.Settings.RestartCount
        restartInterval = [string] $task.Settings.RestartInterval
        executionLimit  = [string] $task.Settings.ExecutionTimeLimit
        execute         = if ($null -ne $action) { [string] $action.Execute } else { $null }
        arguments       = if ($null -ne $action) { [string] $action.Arguments } else { $null }
    }
}

# --------------------------------------------------------------------------- the writer
# Built here rather than assumed on disk. A witness that measured a stale dll would report on code
# nobody has now, which is the shape that let a campaign stay green over a build that no longer
# existed.
$LiveProj = Join-Path $RepoRoot 'app\windows\MCPRouter.Shell.Live\MCPRouter.Shell.Live.csproj'
Write-Host 'win23 witness: building the supervisor under test'
$build = & dotnet build $LiveProj -c Debug -v q --nologo 2>&1
if ($LASTEXITCODE -ne 0) {
    $Notes += ($build | Out-String)
    Write-Verdict 3 'NO VERDICT' 'the assembly under test did not build, so nothing was measured.'
}

$OutDir = Join-Path $RepoRoot 'app\windows\MCPRouter.Shell.Live\bin\Debug\net8.0'
$LiveDll = Join-Path $OutDir 'MCPRouter.Shell.Live.dll'
$ModelDll = Join-Path $OutDir 'MCPRouter.Shell.Model.dll'
foreach ($dll in @($ModelDll, $LiveDll)) {
    if (-not (Test-Path $dll)) {
        Write-Verdict 3 'NO VERDICT' ("the build reported success and {0} is not on disk." -f $dll)
    }
    [void][System.Reflection.Assembly]::LoadFrom($dll)
}

# A path chosen to be unmistakable in the recorder's output. If the read-back ever showed a
# different Execute, the assertion would be comparing this run's registration against somebody
# else's task under the same name, and it would say so rather than agree.
$ExePath = Join-Path $RepoRoot 'app\windows\MCPRouter.Shell.Live\win23-witness-daemon.exe'

# ::new() rather than New-Object, and every optional parameter passed explicitly: PowerShell does
# not apply a C# default parameter value, so `New-Object SchtasksCli` finds no constructor at all
# for a type whose only ctor takes one optional argument.
$cli = [MCPRouter.Shell.Live.Lifecycle.SchtasksCli]::new([string] $null)
$supervisor = [MCPRouter.Shell.Live.Lifecycle.LogonTaskSupervisor]::new($cli, $TaskName, [string] $null)
$config = [MCPRouter.Shell.Model.Lifecycle.DaemonLifecycleConfig]::new(
    [MCPRouter.Shell.Model.Lifecycle.DaemonSupervisionKind]::LogonTask,
    $Port, $ExePath, (-not $ProveRed), 60)
if ($ProveRed) {
    $Notes += ('ARMING RUN: registered with RestartOnCrash false. EFFECT.restart is REQUIRED to ' +
        'break and every other arm is required to hold. A run in this mode that reports PASS has ' +
        'shown the restart assertion cannot fail, which is a defect in this lane and not in the ' +
        'product.')
}

Write-Host ''
Write-Host ("win23 witness: task '{0}'" -f $TaskName)
Write-Host  '               writer   MCPRouter.Shell.Live -> schtasks.exe /Create /XML'
Write-Host  '               recorder Get-ScheduledTask -> Task Scheduler WMI provider'
Write-Host ''

$registered = $false
try {
    # ----------------------------------------------------------------- BASELINE
    $before = Read-Effect $TaskName
    if ($null -ne $before) {
        # Cleaned rather than failed: a leftover from an interrupted run is this lane's own debris
        # and not a finding about the product. It IS recorded, because a lane that silently tidies
        # up after itself hides how often it is being interrupted.
        $Notes += ("a task named '{0}' was already registered at start and was removed before " +
                   'the baseline arm. That is leftover from an interrupted run of this lane.') -f $TaskName
        [void] $supervisor.Unregister()
        $before = Read-Effect $TaskName
    }
    Add-Arm 'BASELINE' 'the recorder reports no such task before registration' `
        ($null -eq $before) `
        $(if ($null -eq $before) { 'nothing registered - the arms below measure this run' }
          else { 'a task under this name survived removal; every assertion below would be about it' })

    # ----------------------------------------------------------------- EFFECT
    $result = $supervisor.Register($config)
    $registered = $true
    if (-not $result.Succeeded) {
        $Notes += ('schtasks exit {0}: {1} {2}' -f $result.ExitCode, $result.StandardOutput, $result.StandardError)
        Add-Arm 'EFFECT' 'the scheduler accepted the registration' $false `
            ('schtasks refused it, exit {0}. The message is in notes[].' -f $result.ExitCode)
        Write-Verdict 1 'FAIL' 'the scheduler refused the XML the supervisor built.'
    }

    $after = Read-Effect $TaskName
    if ($null -eq $after) {
        Add-Arm 'EFFECT' 'the recorder reports the task present after registration' $false `
            'schtasks reported success and the independent recorder sees nothing.'
        Write-Verdict 1 'FAIL' 'the writer claimed success and the recorder disagrees.'
    }

    Add-Arm 'EFFECT.present' 'the recorder reports the task present after registration' $true `
        ("state={0}" -f $after.state)

    # The three claims, each read out of the recorder and never out of the config. 'Limited' is the
    # ScheduledTasks module's word for the XML's LeastPrivilege; the two vocabularies meeting here
    # is the point, and nothing in this repository maps between them.
    Add-Arm 'EFFECT.logon' 'the trigger is a logon trigger' $after.hasLogonTrigger `
        ("triggers: {0}" -f ($after.triggerClasses -join ', '))
    Add-Arm 'EFFECT.unelevated' 'the principal runs un-elevated' `
        ($after.runLevel -eq 'Limited') ("RunLevel={0}, LogonType={1}" -f $after.runLevel, $after.logonType)
    Add-Arm 'EFFECT.restart' 'the task restarts on failure' `
        ($after.restartCount -gt 0 -and -not [string]::IsNullOrWhiteSpace($after.restartInterval)) `
        ("RestartCount={0}, RestartInterval={1}" -f $after.restartCount, $after.restartInterval)
    Add-Arm 'EFFECT.action' 'the action is the executable and port this run asked for' `
        ($after.execute -eq $ExePath -and $after.arguments -eq ("--port {0}" -f $Port)) `
        ("Execute={0} Arguments={1}" -f $after.execute, $after.arguments)

    # ----------------------------------------------------------------- REMOVAL and SILENCE
    $removal = $supervisor.Unregister()
    $registered = $false
    Add-Arm 'REMOVAL' 'the supervisor removes what it registered' $removal.Succeeded `
        ("schtasks /Delete exit {0}" -f $removal.ExitCode)

    $gone = Read-Effect $TaskName
    Add-Arm 'SILENCE' 'the recorder reports absence once the task is gone' ($null -eq $gone) `
        $(if ($null -eq $gone) { 'the recorder can say no, so its yes above was a reading' }
          else { 'the recorder still reports the task, so its earlier yes proves nothing' })
}
finally {
    if ($registered) {
        # The lane must not leave a scheduled task behind on a failure path. Best effort, and its
        # failure is recorded rather than thrown, because a cleanup error must not overwrite the
        # verdict the arms already reached.
        try { [void] $supervisor.Unregister() }
        catch { $Notes += ('cleanup failed: ' + $_.Exception.Message) }
    }
}

$broke = @($Arms | Where-Object { -not $_.held })

if ($ProveRed) {
    # The arming verdict is inverted, and it is stricter than "something went red": exactly
    # EFFECT.restart must break. An arm that reddened everything would prove the lane is noisy
    # rather than that it is watching the thing the defect touched.
    $ids = ($broke | ForEach-Object { $_.id }) -join ', '
    if ($ids -eq 'EFFECT.restart') {
        Write-Verdict 0 'PASS (armed)' ('the planted defect - supervision turned off - broke ' +
            'EFFECT.restart and nothing else. The restart assertion is watching the scheduler and ' +
            'not restating the config.')
    }
    Write-Verdict 1 'FAIL (arming)' ("expected exactly EFFECT.restart to break; broke: {0}" -f
        $(if ($ids) { $ids } else { 'nothing - the assertion cannot fail' }))
}

if ($broke.Count -gt 0) {
    Write-Verdict 1 'FAIL' ("{0} of {1} arm(s) broke: {2}" -f $broke.Count, $Arms.Count,
        (($broke | ForEach-Object { $_.id }) -join ', '))
}
$passReason = ("all {0} arm(s) held: the task the supervisor registered is present in the Windows " +
    'task scheduler with a logon trigger, an un-elevated principal and a restart policy, read by ' +
    'an API that did not write it, and absent again once removed.') -f $Arms.Count
Write-Verdict 0 'PASS' $passReason
