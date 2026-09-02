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
# The sweep-control gate runs every declared control under a per-control budget. Its 120s
# default is a macOS measurement. On this clone the shell that gate resolves is Cygwin bash and
# eight fleet runners share the box, and the two bash-heavy selftests in its registry measured
# 5m22s (no-telemetry-egress-selftest.sh - 3 of 3 arms held, exit 0) and 2m30s
# (acceptance-lanes-selftest.sh - 13 of 13 arms held, exit 0) on 2026-08-31. Both controls are
# healthy; neither approaches 120s, and timing them out reddens this lane while answering
# nothing about whether a control is rotted - an always-red that erodes. The budget is a
# condition of the run, so this lane states its own rather than inheriting a machine's: the
# gate's default is untouched, and every control must still pass inside whatever budget is set.
$env:SWEEP_CONTROL_TIMEOUT = '600'      # headroom over the 5m22s measured under load

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

$failed  = New-Object System.Collections.Generic.List[string]
$passed  = New-Object System.Collections.Generic.List[string]
$notrun  = New-Object System.Collections.Generic.List[string]

function Invoke-Check {
    param([string]$Name, [scriptblock]$Body, [int[]]$NoVerdictCodes = @())
    Write-Host ("  {0,-52} " -f $Name) -NoNewline
    try   { & $Body | Out-Null; $rc = $LASTEXITCODE }
    catch { $rc = 1; Write-Host "EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red }
    if ($null -eq $rc) { $rc = 1 }

    # Three outcomes, keyed on the EXIT CODES the gates reserve - never on their prose.
    #
    # The first version of this scanned stdout for "NOT A PASS", "NO VERDICT" and
    # "CONTROL FAILED", and it did so BEFORE testing the exit code. WIN18's verifier proved
    # that a gate exiting 1 whose narrative merely contains one of those phrases was filed
    # no-verdict, and no-verdict does not reach exit 1 - so a real finding-failure was
    # swallowed and the harness went green. It was live, not hypothetical: carrier-parity-gate
    # prints the ordinary English "a stated backlog and not a pass" while exiting 1, and
    # sweep-control-gate QUOTES another gate's "NO VERDICT" inside a FAIL line.
    #
    # A gate that wants to say it measured nothing says so in its exit code. Those codes are
    # documented per gate below; anything else non-zero is a failure.
    if ($rc -eq 0) { Write-Host "pass" -ForegroundColor Green; $passed.Add($Name) }
    elseif ($NoVerdictCodes -contains $rc) {
        Write-Host ("NO VERDICT (exit {0}) - it measured nothing" -f $rc) -ForegroundColor DarkYellow
        $notrun.Add("$Name - the gate reserves exit $rc for 'measured nothing'")
    }
    else { Write-Host "FAIL (exit $rc)" -ForegroundColor Red; $failed.Add($Name) }
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
    # WIN17's platform layer has 37 checks and, until WIN17's verifier said so, they ran only
    # when a human typed the command - no gate, no target, and not here, on the lane built to be
    # that path. An oracle enrolled in nothing is evidence nobody will re-run.
    if (Test-Path (Join-Path $root 'scripts/e2e-platform.mjs')) {
        if (Test-Path (Join-Path $root 'dist/index.js')) {
            Invoke-Check 'platform e2e (scripts/e2e-platform.mjs)' {
                & node (Join-Path $root 'scripts/e2e-platform.mjs')
            }
        } else {
            Skip-Check 'platform e2e' 'dist/ absent - run npx tsc -p tsconfig.json first'
        }
    }
} else {
    Skip-Check 'router typecheck' 'node_modules absent - run npm install first'
    Skip-Check 'platform e2e' 'node_modules absent'
}

# ---------------------------------------------------------------- the Windows client
Write-Host "`nWindows client" -ForegroundColor Cyan
$msbuild = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
# The exclusion is matched against the path RELATIVE to $root, not the absolute one. Absolute
# matching broke the check in the one place it is used most: every ship-feature runner verifies
# from inside .worktrees/<ID>, where $root itself contains "\.worktrees\", so every project in the
# tree was filtered out and the lane printed "no .csproj yet - WIN3 has not landed the shell" while
# looking straight at one. A skip that reads like a fact about the repository is worse than a
# failure, because nobody goes and checks it.
$prefix = $root.TrimEnd('\', '/') + '\'
$projects = @(Get-ChildItem -Path $root -Recurse -Filter '*.csproj' -ErrorAction SilentlyContinue |
              Where-Object {
                  $rel = $_.FullName
                  if ($rel.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                      $rel = $rel.Substring($prefix.Length)
                  }
                  $rel -notmatch '(^|\\)(node_modules|\.worktrees|bin|obj)\\'
              })
if ($projects.Count -eq 0) {
    Skip-Check 'client build' 'no .csproj yet - WIN3 has not landed the shell'
} elseif (-not (Test-Path $msbuild)) {
    Skip-Check 'client build' 'Visual Studio MSBuild.exe not found'
} else {
    foreach ($p in $projects) {
        # dotnet build CANNOT build WinUI here: it resolves MSBuildExtensionsPath to the .NET SDK,
        # which carries no AppxPackage tasks, and fails MSB4062 however complete VS is.
        #
        # RESTORE AND BUILD ARE TWO INVOCATIONS, and that is not tidiness. `-t:Restore,Build` in a
        # single MSBuild call evaluates the project ONCE, before restore has written
        # obj/*.nuget.g.props - so the Microsoft.WindowsAppSDK targets that carry the XAML markup
        # compiler are never imported, no App.g.i.cs is generated, and the build fails
        #     CSC : error CS5001: Program does not contain a static 'Main' method
        # which names a missing entry point and is actually a missing markup pass. Measured on
        # WIN20's probe, 2026-08-30: from clean, one invocation exits 1 and two exit 0, every time.
        Invoke-Check ("restore {0}" -f $p.Name) {
            & $msbuild $p.FullName -t:Restore -v:q -nologo 2>&1 | Out-Host
            $LASTEXITCODE
        }
        Invoke-Check ("build {0}" -f $p.Name) {
            & $msbuild $p.FullName -t:Build -v:q -nologo 2>&1 | Out-Host
            $LASTEXITCODE
        }
    }
}


# The shell's structural gates. They are plain net8.0 with no WinUI reference, on purpose: they
# read DESIGN.md §13 and the design of record and hold the shell's catalogue to both, and they
# need no display to do it - which matters on a machine whose agent session cannot host a window.
$shellTests = Join-Path $root 'app\windows\MCPRouter.Shell.Tests\MCPRouter.Shell.Tests.csproj'
if (Test-Path $shellTests) {
    Invoke-Check 'shell model tests (dotnet test)' {
        & dotnet test $shellTests --nologo -v:q 2>&1 | Out-Host
        $LASTEXITCODE
    }
} else {
    Skip-Check 'shell model tests' 'MCPRouter.Shell.Tests is absent'
}

# The shell's in-process self-test needs an interactive session and this lane may not be in one.
# It is NOT enrolled as a pass/fail check here, because its "could not run" and its "passed" would
# be the same green from outside. Run scripts/windows/run-shell-selftest.ps1 and read its exit
# code: 0 ran clean, 1 ran and found failures, 2 could not run.
Skip-Check 'shell self-test (captures)' 'needs an interactive session - run scripts/windows/run-shell-selftest.ps1'

# ---------------------------------------------------------------- WIN20's automation plane
# The campaign's Windows oracle. It needs a drawn window and the interactive window station, so it
# is NOT run inline here: an agent shell on this machine sits in session 0, where a WinUI process
# cannot start and a UIA walk returns an empty list rather than an error. The lane refuses that
# station itself; this block records the command and its three outcomes rather than pretending to
# have taken them.
Write-Host "`nWindows automation plane (WIN20)" -ForegroundColor Cyan
$uiaSelftest = Join-Path $root 'scripts/windows/uia/uia-selftest.py'
$uiaDump     = Join-Path $root 'planning/evidence/WIN20/run/uia-control-view.json'
if (-not (Test-Path $uiaSelftest)) {
    Skip-Check 'uia assertions, armed' 'scripts/windows/uia/uia-selftest.py absent'
} elseif (-not (Test-Path $uiaDump)) {
    Skip-Check 'uia assertions, armed' 'no captured dump - run scripts/windows/uia/run-probe-lane.ps1 first'
} else {
    # Portable: it arms the graded assertions against a dump already on disk, so it needs no
    # window and runs anywhere. Exit 3 is its reserved "measured nothing", and it is classified
    # here by EXIT CODE rather than by scanning its prose - this file's own history is the reason
    # (a gate exiting 1 whose narrative merely contained "NO VERDICT" was filed no-verdict, and a
    # real failure went green).
    Write-Host ("  {0,-44} " -f 'uia assertions, armed') -NoNewline
    & $python $uiaSelftest --dump $uiaDump 2>$null | Out-Null
    $uiaRc = $LASTEXITCODE
    if ($uiaRc -eq 0) {
        Write-Host "pass" -ForegroundColor Green
        $passed.Add('uia assertions, armed')
    } elseif ($uiaRc -eq 3) {
        Write-Host "NO VERDICT (exit 3) - it measured nothing" -ForegroundColor DarkYellow
        $notrun.Add('uia assertions, armed - the gate reserves exit 3 for "measured nothing"')
    } else {
        Write-Host ("FAIL (exit {0})" -f $uiaRc) -ForegroundColor Red
        $failed.Add('uia assertions, armed')
    }
}
Skip-Check 'uia live lane (run-probe-lane.ps1)' 'needs WinSta0; run it directly and read planning/evidence/WIN20/run/lane.json'

# The shell destination lane. It actuates all ten NavigationView destinations against the real
# MCPRouter.Shell binary and reads the tree AFTER each actuation, so it needs a drawn window and
# WinSta0 exactly as the probe lane does. Recorded rather than run, for the same reason: from
# session 0 its "could not start the app" and its "every board opened" would be the same green.
# It is named here because until now this file did not know the lane existed, and a verifier that
# does not name a lane is a verifier nobody consults before deciding coverage.
Skip-Check 'shell destination lane (run-shell-lane.ps1)' 'needs WinSta0; run it directly and read planning/evidence/WIN-SHELL/run/assert-report.json'

# ---------------------------------------------------------------- WIN23's supervision effect
# The one Windows lane here that mutates the machine, and it is enrolled rather than recorded
# because it can run from any station and it cleans up after itself. It registers a scheduled task
# under a name of its own - never the shipped one - drives it through the product's own supervisor,
# reads the result back through Get-ScheduledTask (a different API from the schtasks.exe that wrote
# it), and deletes it. WIN23 shipped a supervision "mode" that was a switch statement returning the
# sentence describing itself; this is the check that would notice that shape returning.
#
# Graded by EXIT CODE and never by its prose, for the reason recorded in the WIN20 block above.
Write-Host "`nWindows daemon supervision (WIN23)" -ForegroundColor Cyan
$win23Witness = Join-Path $root 'scripts/windows/win23-logon-task-witness.ps1'
$pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue)
if (-not (Test-Path $win23Witness)) {
    Skip-Check 'logon task effect witness' 'scripts/windows/win23-logon-task-witness.ps1 absent'
} elseif ($null -eq $pwshExe) {
    # NOT a pass. The lane loads the net8.0 assembly the product ships, which Windows PowerShell 5.1
    # cannot do, so without pwsh there is no measurement rather than a clean one.
    Skip-Check 'logon task effect witness' 'pwsh (PowerShell 7) is absent; the lane loads a net8.0 assembly'
} else {
    Write-Host ("  {0,-44} " -f 'logon task effect witness') -NoNewline
    & $pwshExe.Source -NoProfile -File $win23Witness 2>&1 | Out-Null
    $w23 = $LASTEXITCODE
    if ($w23 -eq 0) {
        Write-Host "pass" -ForegroundColor Green
        $passed.Add('logon task effect witness')
    } elseif ($w23 -eq 3) {
        Write-Host "NO VERDICT (exit 3) - it measured nothing" -ForegroundColor DarkYellow
        $notrun.Add('logon task effect witness - the lane reserves exit 3 for "could not run"')
    } else {
        Write-Host ("FAIL (exit {0})" -f $w23) -ForegroundColor Red
        $failed.Add('logon task effect witness')
    }
}

# ---------------------------------------------------------------- the portable repo gates
Write-Host "`nPortable gates" -ForegroundColor Cyan

# THE ONE ENVIRONMENT DECLARATION THIS LANE MAKES, and it is a budget rather than a behaviour.
# planning/sweep-control-gate.py runs each declared control under SWEEP_CONTROL_TIMEOUT, defaulting
# to 120s - the macOS measurement, and its own comment says so and says the variable exists because
# the budget is a property of the machine. On this Windows clone it is not enough: bash process
# spawn here costs almost all of the wall clock (measured 2026-09-02, nothing else running:
# no-telemetry-egress-selftest.sh exit 0 in 161s, acceptance-lanes-selftest.sh exit 0 in 119s;
# measured 2026-08-31 under eight fleet runners, 5m22s and 2m30s). BOTH CONTROLS HOLD. What the
# 120s default produced was two findings reading 'its declared control does not pass', which is the
# gate reporting the host's shell as a rotted control - a false finding, and the direction that
# gets a gate switched off.
#
# 600 rather than unbounded: a control that genuinely hangs must still be caught, and the finding
# text prints the budget it failed, so a run under this declaration cannot be mistaken for a run
# under the default.
$env:SWEEP_CONTROL_TIMEOUT = '600'
#
# ALL 24 python members of `make lint`, with the Makefile's own flags. The first version ran
# EIGHT of them and named none of the rest. WIN18's verifier ran the other thirteen: eight would
# have passed for free, and THREE were red on genuine findings - two of those against files this
# fleet itself authored. A lane that selects the gates it runs, and does not say which it left
# out, reports its own selection rather than the repository.
#
# `NoVerdict` lists the exit codes each gate RESERVES for "I measured nothing". Anything else
# non-zero is a failure. Nothing is decided by reading a gate's prose.
$gates = @(
    @{ Cmd = 'planning/reader-accounting.py' },
    @{ Cmd = 'planning/null-run-gate.py' },
    @{ Cmd = 'planning/py39-annotation-gate.py' },
    @{ Cmd = 'planning/citation-gate.py' },
    @{ Cmd = 'planning/sweep-control-gate.py';                       NoVerdict = @(4) },
    @{ Cmd = 'planning/scope-invariance-gate.py'; Args = @('--quiet') },
    @{ Cmd = 'planning/instrument-census.py' },
    @{ Cmd = 'planning/runnable-path-gate.py' },
    @{ Cmd = 'planning/registry-drop-gate.py';                       NoVerdict = @(2) },
    @{ Cmd = 'planning/evidence-citation-gate.py' },
    @{ Cmd = 'planning/foreign-path-gate.py';     Args = @('--quiet'); NoVerdict = @(2) },
    @{ Cmd = 'planning/target-resolution-gate.py'; Args = @('--quiet') },
    @{ Cmd = 'planning/pin-class-gate.py';                           NoVerdict = @(2) },
    @{ Cmd = 'planning/shipped-brief-gate.py';                       NoVerdict = @(3) },
    @{ Cmd = 'planning/brief-target-gate.py';     Args = @('--quiet') },
    @{ Cmd = 'planning/carrier-parity-gate.py';                      NoVerdict = @(2) },
    @{ Cmd = 'planning/test-campaign/bin/capture-manifest.py' },
    @{ Cmd = 'planning/test-campaign/bin/raster-claim-gate.py';      NoVerdict = @(4) },
    @{ Cmd = 'planning/test-campaign/bin/forced-state-assert.py'; Args = @('--control') },
    @{ Cmd = 'planning/test-campaign/bin/effect-class-census.py'; Args = @('--control') },
    @{ Cmd = 'planning/test-campaign/bin/effect-class-census.py' },
    @{ Cmd = 'planning/test-campaign/bin/blind-vocabulary-arm.py' },
    @{ Cmd = 'planning/test-campaign/bin/vocab-differential.py';  Args = @('--control') },
    @{ Cmd = 'planning/test-campaign/bin/vocab-differential.py' }
)
foreach ($g in $gates) {
    $path = Join-Path $root $g.Cmd
    $argv = @(); if ($g.ContainsKey('Args')) { $argv = $g.Args }
    $label = $g.Cmd + $(if ($argv.Count) { ' ' + ($argv -join ' ') } else { '' })
    if (-not (Test-Path $path)) { Skip-Check $label 'file absent'; continue }
    $nv = @(); if ($g.ContainsKey('NoVerdict')) { $nv = $g.NoVerdict }
    Invoke-Check $label { & $python $path @argv 2>$null } $nv
}

# Nothing is hardcoded as unrunnable any more. The three that were - null-run-gate,
# sweep-control-gate and carrier-parity-gate - were each claimed to need bash or a macOS build,
# and WIN18's verifier measured all three RUNNING here: the first exits 0, and the other two
# exit 1 on real findings, one of which names planning/goals/win-gates.py. WIN18's own commit had
# added Windows portability to exactly those three files and the lane then declared them
# unreachable. A skip asserts a fact about the machine; if it is not measured it is a guess, and
# a guess that suppresses a red gate is the most expensive kind.

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
