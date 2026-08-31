<#
.SYNOPSIS
  Runs the shell's in-process self-test and reports what it observed.

.DESCRIPTION
  The self-test cannot be launched directly from an agent or SSH session on this machine, and the
  reason is measured rather than assumed:

    * That session is Session 0 on a non-interactive window station (Service-0x0-...). A WinUI
      process started from it dies with 0xC000027B - a stowed E_INVALIDARG out of
      Microsoft.UI.Xaml.dll - BEFORE the App constructor runs. There is no window and no log.
    * A scheduled task created with /it runs in the interactive session, and the app does reach
      OnLaunched and activate its window there. That is the only channel found that hosts it.
    * That task's own window station still enumerates zero top-level windows, so an external
      screenshot is not available from it either. Hence an IN-PROCESS capture: the app
      photographs its own XAML tree and writes the PNGs itself.

  Exit 0  the self-test ran and reported no failures.
  Exit 1  the self-test ran and reported failures - read selftest.json.
  Exit 2  the self-test could not be run here. NOT a pass and NOT a failure.
#>
param(
    [string] $OutDir = (Join-Path $env:LOCALAPPDATA 'mcp-router-win3-selftest'),
    [int]    $TimeoutSec = 180
)

$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe = Join-Path $root 'app\windows\MCPRouter.Shell\bin\Debug\net8.0-windows10.0.19041.0\win-x64\MCPRouter.Shell.exe'

if (-not (Test-Path $exe)) {
    Write-Host "NOT-RUN: the shell is not built. Run scripts/windows/build-shell.ps1 first." -ForegroundColor DarkYellow
    exit 2
}

if ((Get-Process -Id $PID).SessionId -eq 0) {
    Write-Host "this session is Session 0, so the app cannot be hosted here - going through an interactive task" -ForegroundColor DarkYellow
}

Remove-Item -Recurse -Force $OutDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# schtasks caps /tr at 261 characters and does not expand a long path, so the invocation goes into
# a wrapper next to the output rather than onto the command line.
$wrapper = Join-Path $OutDir 'run.cmd'
"@echo off`r`n`"$exe`" --selftest `"$OutDir`"" | Out-File -FilePath $wrapper -Encoding ascii

$taskName = 'MCPRouter_WIN3_SelfTest'
& schtasks.exe @('/create', '/tn', $taskName, '/tr', $wrapper, '/sc', 'once', '/st', '00:00', '/it', '/f') | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "NOT-RUN: could not create the interactive task (exit $LASTEXITCODE)." -ForegroundColor DarkYellow
    exit 2
}

& schtasks.exe @('/run', '/tn', $taskName) | Out-Null
$report = Join-Path $OutDir 'selftest.json'
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline -and -not (Test-Path $report)) { Start-Sleep -Seconds 2 }

& schtasks.exe @('/delete', '/tn', $taskName, '/f') | Out-Null

if (-not (Test-Path $report)) {
    # A missing report is NOT a pass. It says the app never got far enough to write one, and the
    # startup log beside the executable is the only place that says how far it did get.
    Write-Host "NOT-RUN: no selftest.json after $TimeoutSec s." -ForegroundColor DarkYellow
    $startupLog = Join-Path (Split-Path $exe) 'shell-startup.log'
    if (Test-Path $startupLog) {
        Write-Host "--- shell-startup.log ---"
        Get-Content $startupLog | Select-Object -Last 20
    } else {
        Write-Host "and no shell-startup.log either, so the process died before App's constructor."
    }
    exit 2
}

$json = Get-Content $report -Raw | ConvertFrom-Json
$pngs = @(Get-ChildItem $OutDir -Filter '*.png' -ErrorAction SilentlyContinue)

Write-Host ""
Write-Host "self-test report: $report"
Write-Host ("  destinations walked : {0}" -f @($json.observations | Where-Object { $_.kind -eq 'destination' }).Count)
Write-Host ("  appearances forced  : {0}" -f @($json.observations | Where-Object { $_.kind -eq 'appearance' }).Count)
Write-Host ("  captures on disk    : {0}" -f $pngs.Count)
Write-Host ("  system theme        : {0}" -f $json.systemTheme)
Write-Host ("  rasterization scale : {0}" -f $json.rasterizationScale)
Write-Host ("  commands on surface : {0}" -f $json.commands)
Write-Host ""
Write-Host "what these captures do NOT hold:" -ForegroundColor DarkYellow
Write-Host ("  " + $json.whatThisHolds) -ForegroundColor DarkYellow

if ($json.failures.Count -gt 0) {
    Write-Host ""
    Write-Host "failures:" -ForegroundColor Red
    $json.failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host ""
Write-Host "no failures reported" -ForegroundColor Green
exit 0
