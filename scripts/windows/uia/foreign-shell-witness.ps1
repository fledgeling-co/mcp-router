<#
.SYNOPSIS
  DEF-402's arm: does the shell lane kill a shell that is not its subject?

.DESCRIPTION
  The lane stops stale shells before it launches its own, so the ProcessId search that follows
  finds the process it just started rather than one left over. Until 2026-09-03 it did that with
  `Get-Process 'MCPRouter.Shell'`, which names every process of that name on the MACHINE - so two
  runners in a fleet wave, running this lane from two worktrees at once, terminated each other's
  shell partway through the sweep. The victim reported a destination CRASH at whichever destination
  it happened to be reading, with no unhandled-exception line in shell-startup.log and no Windows
  Error Reporting record, because nothing had faulted: the process was killed.

  This arm makes that visible without needing two runners. It puts a process named
  `MCPRouter.Shell` at a path that is NOT the lane's, runs the lane, and reads whether that process
  is still alive afterwards.

    RED    the foreign process is gone: the lane killed something it did not start and does not
           measure, which is the defect.
    GREEN  the foreign process survives.

  TWO THINGS ABOUT THE STAND-IN, BOTH MEASURED RATHER THAN CHOSEN FOR CONVENIENCE.

  IT IS A RENAMED `ping.exe`. What is under test is the lane's SELECTION - it reads a process's
  Name and its Path and nothing else - so the stand-in has to be a process with that name at
  another path, and needs to be nothing else besides. A real second copy of the shell was tried
  first and is the wrong instrument: started from a non-interactive session it has no window
  station, draws nothing, and exits on its own within seconds often enough that the arm reported
  NO VERDICT rather than a reading. An arm whose subject dies by itself cannot say who killed it.

  IT IS STARTED THROUGH AN INTERACTIVE SCHEDULED TASK, the same bridge run-shell-lane.ps1 uses.
  Started directly from an agent shell it lands in session 0, and `Stop-Process` from the lane's
  own task in session 1 then fails SILENTLY - the lane logged "stopping a stale shell, pid=..."
  three times against a process that outlived all three, and the arm passed while proving nothing.
  The defect being reproduced is two runners in ONE interactive session, so the stand-in has to be
  in that session too.

  Exit 0  the foreign process survived the lane.
  Exit 1  it did not - the lane kills outside its own subject.
  Exit 3  NO VERDICT: the stand-in could not be created, would not start, or was not reachable.
#>
param(
    [string] $ExePath = '',
    [string] $ForeignRoot = ''
)

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $ExePath) {
    $ExePath = Join-Path $repoRoot 'app\windows\MCPRouter.Shell\bin\Debug\net8.0-windows10.0.19041.0\win-x64\MCPRouter.Shell.exe'
}
if (-not (Test-Path $ExePath)) {
    Write-Host "NO VERDICT: no shell at $ExePath. Run scripts/windows/build-shell.ps1."
    exit 3
}
if (-not $ForeignRoot) {
    $ForeignRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'mcpr-foreign-shell'
}

$standIn = Join-Path $env:SystemRoot 'System32\ping.exe'
if (-not (Test-Path $standIn)) {
    Write-Host "NO VERDICT: no ping.exe at $standIn to stand in with."
    exit 3
}

New-Item -ItemType Directory -Force -Path $ForeignRoot | Out-Null
$foreignExe = [System.IO.Path]::GetFullPath((Join-Path $ForeignRoot 'MCPRouter.Shell.exe'))
Copy-Item -Path $standIn -Destination $foreignExe -Force
if (-not (Test-Path $foreignExe)) {
    Write-Host "NO VERDICT: the stand-in did not land at $foreignExe"
    exit 3
}

function Find-Foreign {
    Get-Process 'MCPRouter.Shell' -ErrorAction SilentlyContinue | Where-Object {
        $p = $null
        try { $p = $_.Path } catch { }
        $p -eq $foreignExe
    }
}

# 900 pings is long enough to outlive a whole lane run several times over, so an early exit is the
# lane's doing rather than the stand-in's.
$taskName = 'MCPRouter-WINSHELL-ForeignShellWitness'
& schtasks.exe /Create /TN $taskName /TR "`"$foreignExe`" -n 900 127.0.0.1" `
    /SC ONCE /ST 00:00 /IT /F | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "NO VERDICT: could not register the stand-in's interactive task (schtasks exit $LASTEXITCODE)."
    exit 3
}
& schtasks.exe /Run /TN $taskName | Out-Null

$until = (Get-Date).AddSeconds(30)
$foreign = $null
while ((Get-Date) -lt $until) {
    $foreign = Find-Foreign | Select-Object -First 1
    if ($null -ne $foreign) { break }
    Start-Sleep -Milliseconds 500
}
& schtasks.exe /Delete /TN $taskName /F | Out-Null

if ($null -eq $foreign) {
    Write-Host "NO VERDICT: the stand-in never appeared as a process within 30s; nothing to measure."
    exit 3
}
$foreignPid = $foreign.Id
Write-Host "foreign process pid $foreignPid named MCPRouter.Shell, at $foreignExe, is running in the interactive session"

& (Join-Path $PSScriptRoot 'run-shell-lane.ps1') | Out-Null
$laneExit = $LASTEXITCODE
Write-Host "lane exit $laneExit"

$alive = $null -ne (Get-Process -Id $foreignPid -ErrorAction SilentlyContinue)
Stop-Process -Id $foreignPid -Force -ErrorAction SilentlyContinue

# WHO ELSE WAS ON THE MACHINE. Read before the verdict, because this arm runs inside the very
# situation it describes: in a fleet wave another runner's lane is live in the same interactive
# session, and a lane still carrying the machine-wide kill will take this stand-in whatever this
# lane does. The lane's own transcript records the decision it made about each foreign process; a
# stand-in that died after this lane logged that it was LEAVING it was killed by something else,
# and that is not a reading about this lane. It is NO VERDICT rather than a pass, because the
# sentence that would make it a pass is this lane's account of its own behaviour.
$laneLog = Join-Path $repoRoot 'planning/evidence/WIN-SHELL/run/lane.log'
$spared = $false
$others = @()
if (Test-Path $laneLog) {
    foreach ($line in (Get-Content $laneLog -ErrorAction SilentlyContinue)) {
        if ($line -match 'leaving a shell that is not this lane''s subject.*at (.+)$') {
            $seen = $Matches[1].Trim()
            if ($seen -eq $foreignExe) { $spared = $true } else { $others += $seen }
        }
    }
}
$others = @($others | Sort-Object -Unique)
foreach ($o in $others) {
    Write-Host "note: another MCPRouter.Shell was live during this run, at $o"
}

if ($alive) {
    Write-Host "PASS  the foreign process (pid $foreignPid) named MCPRouter.Shell, at"
    Write-Host "      $foreignExe,"
    Write-Host "      is still running after the lane. The lane stopped only shells at its own"
    Write-Host "      ExePath, so a second runner's shell survives a wave. The lane's own verdict"
    Write-Host "      on this run: exit $laneExit."
    exit 0
}

if ($spared) {
    Write-Host "NO VERDICT  the foreign process (pid $foreignPid) is gone, but this lane's own"
    Write-Host "            transcript says it LEFT it alone, and $($others.Count) other"
    Write-Host "            MCPRouter.Shell process(es) from other worktrees were live during the"
    Write-Host "            run. Something else killed it - most likely another runner's lane still"
    Write-Host "            carrying the machine-wide kill this arm exists for. Not a pass: the only"
    Write-Host "            sentence that would make it one is this lane's account of itself. Re-run"
    Write-Host "            when no other lane is live."
    exit 3
}

Write-Host "FAIL  the foreign process (pid $foreignPid) was terminated by the lane. It was named"
Write-Host "      MCPRouter.Shell at"
Write-Host "      $foreignExe,"
Write-Host "      which is not the lane's subject and which the lane never measured. This is"
Write-Host "      DEF-402: in a fleet wave the process killed is another runner's shell, and the"
Write-Host "      victim reports it as a destination crash it did not have."
exit 1
