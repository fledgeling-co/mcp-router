<#
.SYNOPSIS
  The Windows verification lane (WIN18).

.DESCRIPTION
  This repository's Makefile is not available here. Every one of its verification targets shells
  out to xcodebuild, and make, swift, swiftlint, swiftformat and xcodebuild are all absent on
  Windows, so `make lint` and `make test` cannot run and must never be reported green.

  This lane is what CAN be checked on Windows. It is deliberately not a substitute for the macOS
  lane and it says so, out loud, at the end of every run.

  Exit 0  every check that could run, passed.
  Exit 1  something that could run, failed.

  A check that cannot run on Windows is printed NOT-RUN with its reason and does NOT count as a
  pass. Not-run is not failure and it is not success; it is the thing this project refuses to let
  a green tick swallow.
#>

$ErrorActionPreference = 'Continue'   # native tools write progress to stderr; see CLAUDE.md
$env:PYTHONIOENCODING = 'utf-8'       # repo gates die under cp1252 without this

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

$failed  = New-Object System.Collections.Generic.List[string]
$passed  = New-Object System.Collections.Generic.List[string]
$notrun  = New-Object System.Collections.Generic.List[string]

function Invoke-Check {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ("  {0,-44} " -f $Name) -NoNewline
    $out = ""
    try   { $out = (& $Body | Out-String); $rc = $LASTEXITCODE }
    catch { $rc = 1; Write-Host "EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red }
    if ($null -eq $rc) { $rc = 1 }

    # This repository distinguishes three outcomes, not two. A gate that says NOT A PASS,
    # NO VERDICT or CONTROL FAILED is telling you it measured nothing - which is neither a
    # pass nor a failure, and filing it as either loses the fact the gate exists to state.
    if ($out -match 'NOT A PASS|NO VERDICT|CONTROL[- ]FAILED|could not run') {
        Write-Host ("NO VERDICT (exit {0}) - it measured nothing" -f $rc) -ForegroundColor DarkYellow
        $notrun.Add("$Name - the gate reported no verdict (exit $rc)")
    }
    elseif ($rc -eq 0) { Write-Host "pass" -ForegroundColor Green; $passed.Add($Name) }
    else               { Write-Host "FAIL (exit $rc)" -ForegroundColor Red; $failed.Add($Name) }
}

function Skip-Check {
    param([string]$Name, [string]$Why)
    Write-Host ("  {0,-44} NOT-RUN - {1}" -f $Name, $Why) -ForegroundColor DarkYellow
    $notrun.Add("$Name - $Why")
}

# python3.exe on this machine is an 87-byte stub: Git Bash tolerates it, PowerShell gets
# ApplicationFailedException / NativeCommandFailed and an EMPTY $LASTEXITCODE, so every gate
# read as failed while all of them actually passed. Resolve the real interpreter once.
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (-not $python) { Write-Host "no python interpreter found" -ForegroundColor Red; exit 1 }

Write-Host "`nWindows verification lane" -ForegroundColor Cyan
Write-Host "  repo: $root`n"

# ---------------------------------------------------------------- the router (TypeScript)
Write-Host "TypeScript router" -ForegroundColor Cyan
if (Test-Path (Join-Path $root 'node_modules')) {
    Invoke-Check 'router typecheck (tsc --noEmit)' {
        & npx --no-install tsc --noEmit -p tsconfig.json
    }
} else {
    Skip-Check 'router typecheck' 'node_modules absent - run npm install first'
}

# ---------------------------------------------------------------- the Windows client
Write-Host "`nWindows client" -ForegroundColor Cyan
$msbuild = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
$projects = @(Get-ChildItem -Path $root -Recurse -Filter '*.csproj' -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '\\(node_modules|\.worktrees|bin|obj)\\' })
if ($projects.Count -eq 0) {
    Skip-Check 'client build' 'no .csproj yet - WIN3 has not landed the shell'
} elseif (-not (Test-Path $msbuild)) {
    Skip-Check 'client build' 'Visual Studio MSBuild.exe not found'
} else {
    foreach ($p in $projects) {
        # dotnet build CANNOT build WinUI here: it resolves MSBuildExtensionsPath to the .NET SDK,
        # which carries no AppxPackage tasks, and fails MSB4062 however complete VS is.
        Invoke-Check ("build {0}" -f $p.Name) {
            & $msbuild $p.FullName -t:Restore,Build -v:q -nologo 2>&1 | Out-Host
            $LASTEXITCODE
        }
    }
}

# ---------------------------------------------------------------- the portable repo gates
Write-Host "`nPortable gates" -ForegroundColor Cyan
$gates = @(
    'planning/brief-target-gate.py',
    'planning/pin-class-gate.py',
    'planning/shipped-brief-gate.py',
    'planning/evidence-citation-gate.py',
    'planning/py39-annotation-gate.py',
    'planning/scope-invariance-gate.py',
    'planning/registry-drop-gate.py',
    'planning/instrument-census.py'
)
foreach ($g in $gates) {
    if (-not (Test-Path (Join-Path $root $g))) { Skip-Check $g 'file absent'; continue }
    Invoke-Check $g { & $python (Join-Path $root $g) 2>$null }
}

# Gates whose control arm shells to a .sh member or a macOS binary. They correctly refuse to
# report a verdict here, and this lane records that refusal rather than dressing it as a pass.
Skip-Check 'planning/null-run-gate.py'       'its control shells to no-raw-design-values.sh (bash member)'
Skip-Check 'planning/sweep-control-gate.py'  'control arm invokes a script Windows cannot execute'
Skip-Check 'planning/carrier-parity-gate.py' 'census depends on the macOS build'

# ---------------------------------------------------------------- the honest disclaimer
Write-Host "`n" ("-" * 72)
Write-Host "What this lane does NOT cover" -ForegroundColor Yellow
@(
 'the Swift macOS app and its 2329 tests - xcodebuild is absent and cannot run on Windows',
 'the iOS app, its simulator lanes and every glass/capture lane',
 'swiftlint and swiftformat over 793 Swift files',
 'the parity harness against the TypeScript reference (needs the built macOS binary)',
 'mock-fidelity, acceptance lanes and surface-reconcile - all xcodebuild-gated',
 'campaign.py / strict-check / reckon - they measure an app that cannot be launched here'
) | ForEach-Object { Write-Host "  - $_" }
Write-Host "A green run here is NOT a green repository." -ForegroundColor Yellow

Write-Host "`n" ("-" * 72)
Write-Host ("passed {0}   failed {1}   not-run {2}" -f $passed.Count, $failed.Count, $notrun.Count)
if ($notrun.Count) {
    Write-Host "not-run (neither pass nor failure):" -ForegroundColor DarkYellow
    $notrun | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkYellow }
}
if ($failed.Count) {
    Write-Host "failed:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
exit 0
