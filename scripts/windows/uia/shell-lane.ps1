<#
.SYNOPSIS
  The Windows shell's UI Automation lane (campaign lane `windows-glass`).

.DESCRIPTION
  WIN20 built the automation plane and proved it — against its own probe window. That measures the
  PLANE, not the product, and WIN20's own report says so in a field called
  `subjectIsNotTheProduct`, whose value is "WIN3 has not landed a drawable Windows shell". WIN3
  landed at 031295c3. This lane is that field's remedy.

  It does four things, and the third is the one that makes it evidence rather than a screenshot:

    1. launches app/windows/MCPRouter.Shell — the real product binary, not a probe
    2. waits for a top-level window owned by that process to appear on the automation plane
    3. for each destination in the shell's own catalogue, SELECTS it through the automation
       plane's SelectionItem pattern and reads back what the tree then contains
    4. writes one dump per destination plus a graded summary

  Step 3 is actuation, not presence. A destination that renders and does nothing passes every
  presence, contrast and screenshot check ever written; what separates a live destination from a
  dead one is that selecting it changes something outside the control that was selected. So each
  destination is graded on three reads taken AFTER its selection — the window title, the caption
  band, and the identity of the board content — and a destination whose reads are identical to
  the previous destination's is reported as a COLLAPSE rather than a pass.

  WHY THIS EXISTS SEPARATELY FROM THE IN-PROCESS SELF-TEST. scripts/windows/run-shell-selftest.ps1
  photographs the XAML tree from inside the app, which is the only channel that can produce pixels
  here. As of 2026-09-02 it captures one destination and never completes (DEF-071), so pixels exist
  for one of ten. This lane needs no pixels and no cooperation from the app beyond the accessibility
  tree every WinUI 3 process publishes by construction, so it can speak for all ten today.

  It never foregrounds the target. Reading a UIA tree is out-of-process and does not activate the
  window, which is the property WIN20's brief predicted and measured, and it is what makes running
  this against the owner's real desktop acceptable.

  Exit 0  every destination that could be measured, was, and none collapsed.
  Exit 1  a destination failed a read or collapsed onto its predecessor.
  Exit 3  NO VERDICT — nothing was measured. Not a pass and not a failure.
#>
param(
    [string] $Out = '',
    [string] $ExePath = '',
    [int]    $TimeoutSeconds = 240,
    # Sweep the catalogue backwards. Not a convenience: three destinations select in the pane and
    # leave the board on the PREVIOUS one, and "this board is dead" and "this board is dead only
    # after that board" are different defects with different fixes. Reversing changes every
    # predecessor at once, which is the cheapest way to tell them apart.
    [switch] $Reverse
)

$ErrorActionPreference = 'Continue'
$env:PYTHONIOENCODING = 'utf-8'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $Out)     { $Out = Join-Path $repoRoot 'planning/evidence/WIN-SHELL/run' }
if (-not $ExePath) {
    $ExePath = Join-Path $repoRoot 'app\windows\MCPRouter.Shell\bin\Debug\net8.0-windows10.0.19041.0\win-x64\MCPRouter.Shell.exe'
}
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force -Path $Out | Out-Null }

# ------------------------------------------------- the harness's own machine state (DEF-087)
# Section 3c drives "Launch router daemon at sign-in" for real, which registers a Windows
# scheduled task, and it reads the shell's settings file back off disk. Both of those are things
# the OPERATOR owns, so the lane points the product at names and paths of its own before it
# launches anything:
#
#   the task name    a lane that registered and deleted the operator's real daemon task would
#                    break the thing it measures. win23-logon-task-witness.ps1 takes the same
#                    precaution for the same reason.
#   the daemon path  deliberately a file that does not exist, so a read-back showing a different
#                    Execute is this lane comparing its own registration against somebody else's
#                    task under the same name, and it says so rather than agreeing.
#   the state dir    so the persistence arm never writes over the settings of the person running
#                    the lane.
#
# All three are read by the SHIPPED code path - MCPROUTER_LOGON_TASK_NAME and
# MCPROUTER_DAEMON_PATH by LogonTaskLaunchAgent, MCPROUTER_SHELL_STATE_DIR by SettingsStore - so
# what is measured is the product's own resolution with the lane's values in it. What this does
# NOT establish is that a real daemon executable resolves on an operator's machine; that is
# recorded on DEF-087 rather than folded into these arms.
$witnessTaskName = '\MCPRouter\WIN-SHELL Settings Witness (transient)'
$witnessDaemon   = Join-Path $repoRoot 'app\windows\MCPRouter.Shell\win-shell-witness-daemon.exe'
$witnessStateDir = Join-Path $Out 'shell-state'
$env:MCPROUTER_LOGON_TASK_NAME = $witnessTaskName
$env:MCPROUTER_DAEMON_PATH     = $witnessDaemon
$env:MCPROUTER_SHELL_STATE_DIR = $witnessStateDir
Remove-Item (Join-Path $witnessStateDir 'shell-settings.json') -ErrorAction SilentlyContinue

$laneLog  = Join-Path $Out 'lane.log'
$laneJson = Join-Path $Out 'lane.json'
Remove-Item $laneJson -ErrorAction SilentlyContinue
Set-Content -Path $laneLog -Value '' -Encoding UTF8

$script:ShellProcessId = 0

function Say($text) {
    $line = "{0} {1}" -f (Get-Date).ToUniversalTime().ToString('o'), $text
    Write-Host $line
    Add-Content -Path $laneLog -Value $line -Encoding UTF8
}

function Stop-Lane([int] $code, [string] $why) {
    if ($script:ShellProcessId -ne 0) {
        Stop-Process -Id $script:ShellProcessId -Force -ErrorAction SilentlyContinue
        Say "shell pid $($script:ShellProcessId) stopped"
    }
    $verdict = if ($code -eq 0) { 'pass' } elseif ($code -eq 3) { 'no-verdict' } else { 'fail' }
    Say $why
    @{
        schema     = 'win-shell.uia-lane/1'
        exitCode   = $code
        verdict    = $verdict
        why        = $why
        subject    = 'MCPRouter.Shell — the Windows client'
        finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -Path $laneJson -Encoding UTF8
    exit $code
}

if (-not (Test-Path $ExePath)) {
    Stop-Lane 3 ("NO VERDICT: the shell is not built at $ExePath. Run scripts/windows/build-shell.ps1. " +
        "A missing binary is a build job, never a finished gap.")
}
Say "shell binary: $ExePath (written $((Get-Item $ExePath).LastWriteTimeUtc.ToString('o')))"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# ------------------------------------------------- 1 and 2. launch, and find it on the plane
# Wrapped in a function because the lane has to be able to do this MORE THAN ONCE. The first run
# of this lane died at the second destination and reported eight `unoracled` — which was honest
# about the instrument and said nothing whatever about those eight boards. A harness that a single
# crashing destination blinds for the rest of the run reports one defect and hides nine unknowns
# behind it, so a crash relaunches and the sweep continues.
function Start-Shell {
    # A stale shell from an earlier run would be found by the ProcessId search below and measured
    # instead of this one, so it is stopped first. probe-lane.ps1 records why this matters for the
    # foreground; here it matters for identity.
    Get-Process 'MCPRouter.Shell' -ErrorAction SilentlyContinue | ForEach-Object {
        Say "  stopping a stale shell, pid=$($_.Id)"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500

    $proc = Start-Process -FilePath $ExePath -PassThru
    $script:ShellProcessId = $proc.Id

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
            Say "  the shell exited before publishing a window"
            return $null
        }
        $root   = [System.Windows.Automation.AutomationElement]::RootElement
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $child  = $walker.GetFirstChild($root)
        while ($null -ne $child) {
            try { if ($child.Current.ProcessId -eq $proc.Id) { return $child } } catch { }
            $child = $walker.GetNextSibling($child)
        }
        Start-Sleep -Milliseconds 500
    }
    Say "  the shell is alive but published no window within $TimeoutSeconds seconds"
    return $null
}

$window = Start-Shell
if ($null -eq $window) {
    Stop-Lane 3 ("NO VERDICT: the shell never reached the automation plane on the first launch, so " +
        "no destination could be measured. That is a fault in the shell or the build rather than a " +
        "finding about any board.")
}
Say "shell pid $script:ShellProcessId is on the automation plane: '$($window.Current.Name)'"

# ------------------------------------------------------------------ 3. drive every destination
# The catalogue is read from the product's own source rather than restated here. A list typed into
# the harness drifts from the one the app ships, and then the lane measures a product that does
# not exist — the same shape as a surface census taken from a contract instead of from the app.
$catalogPath = Join-Path $repoRoot 'app\windows\MCPRouter.Shell.Model\DestinationCatalog.cs'
$destinations = @()
$declared = 0
if (Test-Path $catalogPath) {
    $src = Get-Content $catalogPath -Raw

    # Not every id is a literal: Settings is declared through the `SettingsId` const so that
    # ShellWindow can name it without retyping the string. A reader matching quoted ids alone
    # silently returns nine of ten, and nine measured destinations reported against a shell that
    # has ten is the undercount this whole campaign exists to stop. So resolve the consts first.
    $consts = @{}
    foreach ($c in [regex]::Matches($src, 'const\s+string\s+(\w+)\s*=\s*"([^"]+)"')) {
        $consts[$c.Groups[1].Value] = $c.Groups[2].Value
    }

    $declared = ([regex]::Matches($src, 'new Destination\(')).Count
    foreach ($m in [regex]::Matches($src, 'new Destination\(\s*(?:"([a-z]+)"|(\w+))\s*,\s*"([A-Za-z ]+)"')) {
        $id = $m.Groups[1].Value
        if (-not $id) { $id = $consts[$m.Groups[2].Value] }
        if (-not $id) { continue }
        $destinations += [pscustomobject]@{ Id = $id; Label = $m.Groups[3].Value }
    }
}
if ($destinations.Count -eq 0) {
    Stop-Lane 3 ("NO VERDICT: read zero destinations out of DestinationCatalog.cs. That is the " +
        "instrument failing, not the product passing.")
}
# A reader that resolves SOME of the constructors is worse than one that resolves none, because
# it returns a plausible number. Hold the parse to the file's own constructor count.
if ($destinations.Count -ne $declared) {
    Stop-Lane 3 ("NO VERDICT: DestinationCatalog.cs declares $declared destination(s) and this " +
        "lane's reader resolved $($destinations.Count). The reader is behind the product; fix it " +
        "before trusting any count it prints.")
}
if ($Reverse) {
    [array]::Reverse($destinations)
    Say "SWEEPING IN REVERSE: every destination has a different predecessor than in a forward run"
}
Say "catalogue: $($destinations.Count) destination(s) — $(($destinations | ForEach-Object { $_.Id }) -join ', ')"

$dumper  = Join-Path $PSScriptRoot 'uia-dump.ps1'
$results = @()
$prev    = $null
$failed  = 0

foreach ($d in $destinations) {
    $row = [ordered]@{ id = $d.Id; label = $d.Label }

    # A previous destination may have taken the process down with it. Relaunching here is what
    # turns "eight unoracled behind one crash" into eight real verdicts, and the relaunch is
    # recorded on the row so a reader can never mistake a fresh process for an undisturbed one.
    $row.relaunched = $false
    if (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) {
        Say "  the shell is gone; relaunching before '$($d.Id)'"
        $window = Start-Shell
        $row.relaunched = $true
        if ($null -eq $window) {
            $row.status = 'inconclusive'
            $row.reason = ("the shell could not be relaunched after the previous destination " +
                           "terminated it, so this board was never reached.")
            Say "  $($d.Id): INCONCLUSIVE - relaunch failed"
            $results += [pscustomobject]$row
            $prev = $null
            continue
        }
        $prev = $null   # a fresh process shares no tree with the one that died
    }

    # Find the navigation item by its accessible name, then SELECT it through the plane.
    #
    # Name alone is not enough, and the first run of this lane proved it: four destinations came
    # back "element present, not actuable" because a name search returns the FIRST element
    # carrying that name anywhere in the tree, and the board's own heading, a row label or the
    # window title itself can hold the same word as the pane item. The harness was finding a piece
    # of text and reporting the board unactuable. So ask for the name AND the pattern that makes
    # something selectable; fall back to name alone, and record which one matched, because a
    # fallback that is invisible is a measurement whose subject is unknown.
    # Find the navigation item by its accessible name, then SELECT it through the plane.
    #
    # Name alone is not enough, and the first run of this lane proved it: four destinations came
    # back "element present, not actuable" because a name search returns the FIRST element
    # carrying that name anywhere in the tree, and the board's own heading, a row label or the
    # window title itself can hold the same word as the pane item. The harness was finding a piece
    # of text and reporting the board unactuable. So ask for the name AND the pattern that makes
    # something selectable; fall back to name alone, and record which one matched, because a
    # fallback that is invisible is a measurement whose subject is unknown.
    #
    # AND IT RETRIES, re-finding the element every attempt. The second run still returned three
    # `not actuable` rows, all with "Unsupported Pattern" - against a tree where the dumps show all
    # ten pane items present exactly once, each carrying SelectionItemPattern. A property that
    # reads available and then throws when fetched is a stale element handle: the previous board
    # was still being torn down, and the reference went bad between the find and the call. That is
    # flakiness in this harness, not a property of those boards, and reporting it as a finding
    # about the product would have been a manufactured defect.
    $nameCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $d.Label)
    $selCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::IsSelectionItemPatternAvailableProperty, $true)
    $bothCond = New-Object System.Windows.Automation.AndCondition($nameCond, $selCond)

    $actuated    = $false
    $moved       = $false
    $item        = $null
    $lastError   = ''
    $attempts    = 0
    $actuations  = 0
    $matchedBy   = 'none'
    $titleBefore = ''
    try { $titleBefore = $window.Current.Name } catch { }

    # Actuate until the shell shows an EFFECT, not until the call stops throwing. The previous run
    # is why: three destinations returned a clean Select() on the second attempt and left the
    # window title and the entire control-view tree byte-identical to the board before them. A
    # harness that stops at "the call returned" would have recorded those as actuated and then
    # graded a board that was never opened. So the loop's exit condition is the title moving, the
    # pane item is scrolled into view first in case it was never realised, and the number of
    # actuations it took is recorded - because a destination that needs three is a finding even
    # when the third one works.
    while (-not $moved -and $attempts -lt 3) {
        $attempts++
        $item = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $bothCond)
        $matchedBy = 'name-and-selection-pattern'
        if ($null -eq $item) {
            $item = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $nameCond)
            $matchedBy = 'name-only'
        }
        if ($null -eq $item) {
            $matchedBy = 'none'
            $lastError = "no element carries that accessible name"
            Start-Sleep -Milliseconds 500
            continue
        }

        # A pane item that has never been scrolled into view may not be realised, and an
        # unrealised provider is where "the pattern is available" and "the pattern cannot be
        # fetched" stop contradicting each other.
        try {
            $item.GetCurrentPattern(
                [System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView()
            Start-Sleep -Milliseconds 200
        } catch { }

        try {
            $item.GetCurrentPattern(
                [System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
            $actuated = $true
            $actuations++
        } catch {
            $lastError = $_.Exception.Message
            try {
                $item.GetCurrentPattern(
                    [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                $actuated = $true
                $actuations++
            } catch {
                $lastError = $_.Exception.Message
                Start-Sleep -Milliseconds 400
                continue
            }
        }

        # Poll for the effect rather than sleeping a guessed interval once.
        $waitUntil = (Get-Date).AddSeconds(4)
        while ((Get-Date) -lt $waitUntil) {
            if (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) { break }
            $now = ''
            try { $now = $window.Current.Name } catch { }
            if ($now -eq $d.Label) { $moved = $true; break }
            Start-Sleep -Milliseconds 250
        }

        # Did the PANE ITEM take the selection, whether or not the BOARD followed? This is the read
        # that tells two very different defects apart, and without it the lane can only say "it did
        # not navigate". IsSelected true with an unchanged board means the selection landed and the
        # SelectionChanged path did not carry it - a product defect. IsSelected false means the
        # actuation never took, which is the harness's problem to solve.
        try {
            $row.paneItemSelected = $item.GetCurrentPattern(
                [System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
        } catch {
            $row.paneItemSelected = "unreadable: $($_.Exception.Message)"
        }

        if (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) { break }
    }

    $row.matchedBy   = $matchedBy
    $row.attempts    = $attempts
    $row.actuations  = $actuations
    $row.titleBefore = $titleBefore

    if (-not $actuated -and $matchedBy -eq 'none') {
        $row.selected = $false
        $row.status   = 'unoracled'
        $row.reason   = ("no element on the automation plane carries the accessible name " +
                         "'$($d.Label)' across $attempts attempt(s), so this destination cannot be " +
                         "selected through the plane at all. Neither a pass nor a failure of the " +
                         "board: the harness cannot reach it.")
        Say "  $($d.Id): UNORACLED - no element named '$($d.Label)'"
        $results += [pscustomobject]$row
        continue
    }

    if (-not $actuated) {
        $row.selected = $false
        $row.status   = 'inconclusive'
        $row.reason   = ("the element was found on every one of $attempts attempt(s) and could not " +
                         "be actuated through SelectionItem or Invoke. Last error: $lastError")
        Say "  $($d.Id): INCONCLUSIVE - found but not actuable after $attempts attempt(s)"
        $results += [pscustomobject]$row
        continue
    }
    Start-Sleep -Milliseconds 400

    # THE CRASH READ, and it is a first-class outcome rather than a missing measurement. A board
    # whose selection terminates the process is the most severe result this lane can produce, and
    # the earlier version could only report it as "zero elements" - which reads like an empty
    # board rather than a dead application.
    if (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) {
        $row.selected = $true
        $row.status   = 'fail'
        $row.crashed  = $true
        $row.reason   = ("CRASH: selecting this destination through the automation plane terminated " +
                         "MCPRouter.Shell (pid $script:ShellProcessId). The board was actuated and " +
                         "the process did not survive it.")
        Say "  $($d.Id): FAIL - CRASH, the shell died on selection"
        $failed++
        $results += [pscustomobject]$row
        $prev = $null
        continue
    }

    # The three reads taken AFTER actuation. A destination that renders and does nothing moves
    # none of them.
    $title = ''
    try { $title = $window.Current.Name } catch { }

    $dump = Join-Path $Out ("uia-shell-{0}.json" -f $d.Id)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dumper `
        -ProcessId $script:ShellProcessId -Out $dump -View Control | Out-Null
    $dumpExit = $LASTEXITCODE

    $elements = 0
    $names    = @()
    $boardFailed = $false
    if (Test-Path $dump) {
        try {
            $doc = Get-Content $dump -Raw -Encoding UTF8 | ConvertFrom-Json
            $flat = ($doc | ConvertTo-Json -Depth 40 -Compress)
            $elements = ([regex]::Matches($flat, '"name"\s*:')).Count
            foreach ($m in [regex]::Matches($flat, '"name"\s*:\s*"([^"]{1,60})"')) {
                $names += $m.Groups[1].Value
            }
            # BoardFailure sets AutomationProperties.AutomationId to "board.failure.<id>". Keyed
            # on the automation id rather than on the card's prose, because prose is edited and an
            # oracle that a copy change silently disarms is not an oracle.
            $boardFailed = $flat -match 'board\.failure\.'
        } catch { }
    }

    $fingerprint = (($names | Sort-Object -Unique) -join '|')
    $row.selected    = $actuated
    $row.windowTitle = $title
    $row.elements    = $elements
    $row.dump        = $dump
    $row.dumpExit    = $dumpExit
    $row.fingerprint = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($fingerprint))).Replace('-', '').Substring(0, 16)

    if (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) {
        # The crash can land AFTER the settle window - on the first run it arrived during the tree
        # walk, so the row read "0 named elements", which describes an empty board rather than a
        # dead application. Liveness is therefore read twice: once after actuation, once here.
        $row.status  = 'fail'
        $row.crashed = $true
        $row.reason  = ("CRASH: MCPRouter.Shell terminated while this destination was being read. " +
                        "The board was actuated and the process did not survive it, so the empty " +
                        "tree below is the absence of an application rather than of a board.")
        $failed++
    } elseif ($boardFailed) {
        # THE FAILURE-CARD CHECK, and this lane needed it the moment the product got better at
        # reporting. ShowDestination now catches a board that throws and mounts a BoardFailure
        # card in its place - which is the right product behaviour and was very nearly a false
        # green here: the card sets the window title correctly and publishes its own distinct
        # tree, so the title oracle and the collapse oracle were both satisfied by a board that
        # had not been built. Three destinations went from FAIL to PASS on the strength of it.
        # A harness that grades the error state as a success is worse than no harness.
        $row.status = 'fail'
        $row.boardFailedToBuild = $true
        $row.reason = ("the destination mounted a BoardFailure card rather than its board: the " +
                       "board threw while being built and the shell caught it. The title and the " +
                       "tree both moved, so only the failure card's own automation id " +
                       "distinguishes this from a working board. See shell-startup.log for the " +
                       "exception.")
        $failed++
    } elseif ($elements -eq 0) {
        $row.status = 'fail'
        $row.reason = "the dump held zero named elements, so nothing was measured about this board"
        $failed++
    } elseif ($null -ne $prev -and $prev.fingerprint -eq $row.fingerprint) {
        # THE destination-collapse check. Two destinations publishing one identical tree is the
        # shape where six sidebar items opened one placeholder view and every gate passed.
        $row.status = 'fail'
        $row.reason = ("COLLAPSE: this destination's control-view tree is byte-identical to " +
                       "'$($prev.id)'. Either the board did not mount or both destinations render " +
                       "the same view.")
        $failed++
    } elseif ($title -ne $d.Label) {
        $row.status = 'fail'
        $row.reason = ("the window title reads '$title' after selecting this destination; WIN3 " +
                       "§11 rule 7 requires it to read '$($d.Label)'")
        $failed++
    } else {
        $row.status = 'pass'
    }

    Say ("  {0}: {1} — title '{2}', {3} element(s), fp {4}" -f `
         $d.Id, $row.status.ToUpper(), $title, $elements, $row.fingerprint)
    $obj = [pscustomobject]$row
    $results += $obj
    $prev = $obj
}

# ------------------------------------------------- 3b. the control census on two named surfaces
# WHY THIS EXISTS. The sweep above grades a destination on whether the board CHANGED. It cannot
# tell a board carrying seven sections of working switches from one carrying three inert ones, and
# DEF-076 is exactly that gap: the Settings tree held 60 elements, one of them actuable, while the
# ledger claimed seven sections of Fluent ToggleSwitch controls. So the sweep gets an arm that
# names controls and reads their state.
#
# TWO THINGS MAKE THIS EVIDENCE RATHER THAN A RESTATEMENT.
#
#   It addresses by AutomationId, not by name. A UIA name search returns the first element with
#   that name ANYWHERE in the tree, and this shell's menu bar already holds a "Router" and a
#   "Help". Ids are unique and survive a copy edit.
#
#   The expected ids and labels are READ OUT OF THE PRODUCT'S OWN SOURCE, the same way the
#   destination catalogue above is. A list typed into the harness drifts from the one the app
#   ships, and then the lane measures a product that does not exist. If the reader resolves fewer
#   than the source declares it stops rather than reporting a plausible number.
#
# AND THE TOGGLE TEST IS AN EFFECT TEST. Reading ToggleState back off the switch you just toggled
# proves the control moved, and nothing else - an unbound switch passes that. So the lane toggles
# through the plane and then reads a DIFFERENT element, the board's state readout, which the view
# renders from the model. A switch that fails to write through leaves that line unmoved.

$controls = @()

function Add-ControlRow($id, $status, $detail, $actuates = @(), $recorder = '') {
    # `actuates` is A CONTROL THE SURFACE DECLARES, never the command this lane ran. The census in
    # planning/test-campaign/bin/control-census.py takes its denominator from the surface's own
    # `controls` array, so a row naming "UIA TogglePattern.Toggle()" counts against nothing and
    # reads as a control the registry has never heard of.
    #
    # `recorder` names the thing that read the effect when that thing is NOT this process. An
    # empty recorder means the row was read off the automation tree by this script, which is the
    # default; a named one is what makes the row an effect-witness rather than a UI-state read.
    $row = [ordered]@{ id = $id; status = $status; detail = $detail }
    if ($actuates.Count -gt 0) { $row.actuates = @($actuates) }
    if ($recorder)             { $row.recorder = $recorder }
    $script:controls += [pscustomobject]$row
    if ($status -eq 'fail') { $script:controlFailures++ }
    Say ("  control {0}: {1} - {2}" -f $id, $status.ToUpper(), $detail)
}
$script:controlFailures = 0

function Find-ById($root, [string] $automationId) {
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $automationId)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

# A board that has just been selected is still being built, and an element that is not yet
# realised is absent rather than empty. The first run of this census read every id as missing
# 0.6 s after selecting Settings and the dump taken seconds later held all ten of them - which is
# the harness's own timing, not a finding about the board. So every lookup polls.
function Wait-ById($root, [string] $automationId, [int] $seconds = 10) {
    $until = (Get-Date).AddSeconds($seconds)
    while ($true) {
        $el = Find-ById $root $automationId
        if ($null -ne $el) { return $el }
        if ((Get-Date) -ge $until) { return $null }
        Start-Sleep -Milliseconds 400
    }
}

# What the census can see at all, when it can see none of what it expected. An id list that comes
# back entirely absent has two very different causes - the board did not build, or this client is
# looking at the wrong tree - and without this count they are indistinguishable.
function Count-AddressableElements($root) {
    $cond = New-Object System.Windows.Automation.NotCondition(
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty, '')))
    try {
        return @($root.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants, $cond)).Count
    } catch { return -1 }
}

function Invoke-Destination($label) {
    $nameCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $label)
    $selCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::IsSelectionItemPatternAvailableProperty, $true)
    $both = New-Object System.Windows.Automation.AndCondition($nameCond, $selCond)
    $current = ''
    try { $current = $window.Current.Name } catch { }
    if ($current -eq $label) { return $true }
    for ($i = 0; $i -lt 3; $i++) {
        $el = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $both)
        if ($null -eq $el) { Start-Sleep -Milliseconds 400; continue }
        try {
            $el.GetCurrentPattern(
                [System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        } catch { Start-Sleep -Milliseconds 400; continue }
        $until = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $until) {
            $now = ''
            try { $now = $window.Current.Name } catch { }
            if ($now -eq $label) { return $true }
            Start-Sleep -Milliseconds 250
        }
    }
    return $false
}

if (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) {
    Add-ControlRow 'census' 'unoracled' ('the shell did not survive the destination sweep, so no ' +
        'control could be read. Neither a pass nor a failure of any control.')
} else {

    # --------------------------------------------------------- the product's own declarations
    $settingsSource = Join-Path $repoRoot 'app\windows\MCPRouter.Shell.Model\Settings\SettingsPresentation.cs'
    $expectSections = @()
    $expectToggles  = @()
    if (Test-Path $settingsSource) {
        $src = Get-Content $settingsSource -Raw

        $orderBlock = [regex]::Match($src, 'SectionOrder\s*=\s*new\[\]\s*\{(.*?)\};',
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
        foreach ($m in [regex]::Matches($orderBlock.Groups[1].Value, 'SettingsSection\.(\w+)')) {
            $expectSections += ('settings.section.' + $m.Groups[1].Value.ToLowerInvariant())
        }

        $keysBlock = [regex]::Match($src, 'ToggleKeys\s*=\s*new\[\]\s*\{(.*?)\};',
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $labelBlock = [regex]::Match($src, 'ToggleLabel\(string key\)(.*?)\n    \}',
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $labels = @{}
        foreach ($m in [regex]::Matches($labelBlock.Groups[1].Value, '"(\w+)"\s*=>\s*"([^"]+)"')) {
            $labels[$m.Groups[1].Value] = $m.Groups[2].Value
        }
        foreach ($m in [regex]::Matches($keysBlock.Groups[1].Value, '"(\w+)"')) {
            $key = $m.Groups[1].Value
            $expectToggles += [pscustomobject]@{
                Key   = $key
                Id    = 'settings.toggle.' + $key
                Label = $labels[$key]
            }
        }
    }

    if ($expectSections.Count -eq 0 -or $expectToggles.Count -eq 0) {
        Add-ControlRow 'settings.reader' 'unoracled' ('read zero sections or zero toggle keys out ' +
            'of SettingsPresentation.cs. That is this reader failing, not the board passing.')
    } elseif (@($expectToggles | Where-Object { -not $_.Label }).Count -gt 0) {
        Add-ControlRow 'settings.reader' 'unoracled' ('a toggle key resolved no label out of ' +
            'SettingsPresentation.cs, so the names this lane would assert are not the product''s.')
    } else {
        Say ("settings census expects $($expectSections.Count) section(s) and " +
             "$($expectToggles.Count) toggle(s), read out of SettingsPresentation.cs")

        if (-not (Invoke-Destination 'Settings')) {
            Add-ControlRow 'settings.board' 'unoracled' ('Settings could not be re-actuated after ' +
                'the sweep, so its controls were never reached.')
        } else {
            Start-Sleep -Milliseconds 600

            # ------------------------------------------------------------- the seven sections
            $foundSections = @()
            foreach ($id in $expectSections) {
                if ($null -ne (Wait-ById $window $id 10)) { $foundSections += $id }
            }
            if ($foundSections.Count -eq $expectSections.Count) {
                Add-ControlRow 'settings.sections' 'pass' ("all $($expectSections.Count) declared " +
                    "section(s) publish an addressable container: $($foundSections -join ', ')")
            } else {
                $missing = @($expectSections | Where-Object { $foundSections -notcontains $_ })
                $addressable = Count-AddressableElements $window
                Add-ControlRow 'settings.sections' 'fail' ("$($foundSections.Count) of " +
                    "$($expectSections.Count) declared section(s) reached the automation plane. " +
                    "Absent: $($missing -join ', '). This client can see $addressable element(s) " +
                    "carrying any automation id at all under the window.")
            }

            # ------------------------------------------- each toggle: named, and its state read
            foreach ($t in $expectToggles) {
                $el = Wait-ById $window $t.Id 10
                if ($null -eq $el) {
                    Add-ControlRow $t.Id 'fail' ("no element on the automation plane carries this " +
                        "automation id, so the toggle is unaddressable.")
                    continue
                }
                $publishedName = ''
                try { $publishedName = $el.Current.Name } catch { }
                if ($publishedName -ne $t.Label) {
                    Add-ControlRow $t.Id 'fail' ("publishes the accessible name '$publishedName'; " +
                        "SettingsPresentation declares '$($t.Label)'.")
                    continue
                }
                $state = $null
                try {
                    $state = $el.GetCurrentPattern(
                        [System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
                } catch {
                    Add-ControlRow $t.Id 'fail' ("publishes the name '$publishedName' and no " +
                        "readable toggle state: $($_.Exception.Message)")
                    continue
                }
                Add-ControlRow $t.Id 'pass' ("named '$publishedName', toggle state readable as " +
                    "'$state'")
            }

            # ------------------------------------------------------------ THE EFFECT TEST
            # Toggle the first switch through the plane, then read a DIFFERENT element - the
            # board's state readout, rendered from the model. This is what separates a bound
            # control from an inert one, and it is the only half of DEF-076's fix that a
            # markup check cannot make.
            $subject = $expectToggles[0]
            $switch  = Wait-ById $window $subject.Id 10
            $readout = Wait-ById $window 'settings.state.summary' 10
            if ($null -eq $switch) {
                Add-ControlRow 'settings.effect' 'fail' ('the switch under test is unaddressable, ' +
                    'so no effect could be attempted.')
            } elseif ($null -eq $readout) {
                Add-ControlRow 'settings.effect' 'fail' ('the board publishes no state readout at ' +
                    'settings.state.summary, so a toggle has nothing outside itself to move.')
            } else {
                $before = ''
                try { $before = $readout.Current.Name } catch { }
                $toggled = $false
                try {
                    $switch.GetCurrentPattern(
                        [System.Windows.Automation.TogglePattern]::Pattern).Toggle()
                    $toggled = $true
                } catch { }

                $after = $before
                if ($toggled) {
                    $until = (Get-Date).AddSeconds(4)
                    while ((Get-Date) -lt $until) {
                        $readout = Find-ById $window 'settings.state.summary'
                        if ($null -ne $readout) {
                            try { $after = $readout.Current.Name } catch { }
                        }
                        if ($after -ne $before) { break }
                        Start-Sleep -Milliseconds 250
                    }
                }

                if (-not $toggled) {
                    Add-ControlRow 'settings.effect' 'fail' ('the switch carries TogglePattern and ' +
                        'Toggle() threw, so it could not be actuated through the plane.')
                } elseif ($after -eq $before) {
                    Add-ControlRow 'settings.effect' 'fail' ("INERT: toggling " +
                        "'$($subject.Label)' through the automation plane left the board's state " +
                        "readout at '$before'. The switch moved and the model did not.")
                } else {
                    Add-ControlRow 'settings.effect' 'pass' ("toggling '$($subject.Label)' through " +
                        "the plane moved the board's state readout from '$before' to '$after' - an " +
                        "effect outside the control that was actuated.") @($subject.Label)
                    # Put it back, so the dump committed as evidence shows the board at rest.
                    try {
                        $switch.GetCurrentPattern(
                            [System.Windows.Automation.TogglePattern]::Pattern).Toggle()
                    } catch { }
                    Start-Sleep -Milliseconds 400
                }
            }

            # Re-dump Settings, so the committed evidence is the board these rows describe.
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dumper `
                -ProcessId $script:ShellProcessId -Out (Join-Path $Out 'uia-shell-settings.json') `
                -View Control | Out-Null

            # ============================================================ 3c. OUTSIDE THE PROCESS
            # DEF-087 and DEF-088. Everything above this line is one process reading another
            # process's accessibility tree, which is a real out-of-process read and still only ever
            # a read of the SHELL. A toggle that moves, updates a model and updates a readout
            # satisfies all of it while nothing on the machine changes - which is exactly what the
            # board did, and what a census structurally cannot see.
            #
            # These arms leave the shell entirely. Each names its own recorder, and no recorder
            # here is the writer:
            #
            #   the task     written by the product through schtasks.exe /Create /XML; read back by
            #                Get-ScheduledTask, the ScheduledTasks module over the Task Scheduler's
            #                WMI provider. A different API, a different process and a different
            #                VOCABULARY - the XML says RunLevel LeastPrivilege and the recorder
            #                says Limited, and nothing in this repository translates between them.
            #   the store    written by the product into shell-settings.json; read back by this
            #                script off the disk, never by asking the app what it saved.
            #   the clipboard written by the product through a DataPackage; read back by a
            #                SEPARATE PowerShell process, after this lane has seeded it with a
            #                sentinel so a clipboard that already held the endpoint cannot pass.

            function Read-WitnessTask {
                # The independent read. Null when the scheduler holds no such task. Nothing here
                # touches schtasks.exe or any type from the assembly that wrote it.
                param([string] $Name)
                $leaf = Split-Path -Leaf $Name
                $path = Split-Path -Parent $Name
                if (-not $path.EndsWith('\')) { $path = $path + '\' }
                $task = Get-ScheduledTask -TaskName $leaf -TaskPath $path -ErrorAction SilentlyContinue
                if ($null -eq $task) { return $null }
                $classes = @()
                foreach ($trigger in @($task.Triggers)) {
                    if ($null -ne $trigger -and $null -ne $trigger.CimClass) {
                        $classes += $trigger.CimClass.CimClassName
                    }
                }
                $action = @($task.Actions)[0]
                return [pscustomobject]@{
                    state           = [string] $task.State
                    hasLogonTrigger = ($classes -contains 'MSFT_TaskLogonTrigger')
                    runLevel        = [string] $task.Principal.RunLevel
                    execute         = if ($null -ne $action) { [string] $action.Execute } else { '' }
                }
            }

            function Set-ToggleThroughPlane {
                # Drive a switch to a named position through the plane, and report whether the
                # PLANE now reads it there. Reading the switch back is not the effect test - the
                # arms below are - but a switch that would not move at all has to be told apart
                # from one that moved and reached nothing.
                param($Root, [string] $AutomationId, [bool] $On)
                $el = Wait-ById $Root $AutomationId 10
                if ($null -eq $el) { return 'unaddressable' }
                try {
                    $pattern = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
                    $want = if ($On) { 'On' } else { 'Off' }
                    for ($i = 0; $i -lt 3; $i++) {
                        if ([string] $pattern.Current.ToggleState -eq $want) { return 'ok' }
                        $pattern.Toggle()
                        Start-Sleep -Milliseconds 600
                        $el = Find-ById $Root $AutomationId
                        if ($null -eq $el) { return 'lost' }
                        $pattern = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
                    }
                    return ("stuck at " + [string] $pattern.Current.ToggleState)
                } catch {
                    return ("threw: " + $_.Exception.Message)
                }
            }

            $launchId = 'settings.toggle.LaunchAtLogin'

            # -------------------------------------------------------------------- BASELINE
            # Without this arm a task left behind by an interrupted run makes every assertion
            # below pass while this run registers nothing at all.
            $leftover = Read-WitnessTask $witnessTaskName
            if ($null -ne $leftover) {
                Say "  a witness task survived an earlier run; deleting it before the baseline"
                & schtasks.exe /Delete /TN $witnessTaskName /F 2>&1 | Out-Null
                $leftover = Read-WitnessTask $witnessTaskName
            }
            Add-ControlRow 'settings.launchAtLogin.baseline' `
                $(if ($null -eq $leftover) { 'pass' } else { 'fail' }) `
                $(if ($null -eq $leftover) {
                    "Get-ScheduledTask reports no task at '$witnessTaskName' before the switch is " +
                    "driven, so the arms below measure THIS run's registration."
                } else {
                    "a task at '$witnessTaskName' survived deletion, so every assertion below would " +
                    "be about it rather than about this run."
                }) @('Launch router daemon at sign-in') `
                'Get-ScheduledTask (ScheduledTasks module over the Task Scheduler WMI provider)'

            # -------------------------------------------------------------------- EFFECT
            $drove = Set-ToggleThroughPlane $window $launchId $true
            Start-Sleep -Milliseconds 800
            $registered = Read-WitnessTask $witnessTaskName
            if ($drove -ne 'ok') {
                Add-ControlRow 'settings.launchAtLogin.effect' 'fail' `
                    ("the switch could not be driven to On through the plane: $drove") `
                    @('Launch router daemon at sign-in') `
                    'Get-ScheduledTask (ScheduledTasks module over the Task Scheduler WMI provider)'
            } elseif ($null -eq $registered) {
                Add-ControlRow 'settings.launchAtLogin.effect' 'fail' `
                    ("INERT BEYOND THE PROCESS: the switch reads On through the plane and " +
                     "Get-ScheduledTask reports no task at '$witnessTaskName'. The control moved " +
                     "and the machine did not.") `
                    @('Launch router daemon at sign-in') `
                    'Get-ScheduledTask (ScheduledTasks module over the Task Scheduler WMI provider)'
            } else {
                $claims = @()
                if (-not $registered.hasLogonTrigger) { $claims += 'no logon trigger' }
                # 'Limited' is the ScheduledTasks module's word for the XML's LeastPrivilege. The
                # two vocabularies meeting here is the point.
                if ($registered.runLevel -ne 'Limited') { $claims += "RunLevel=$($registered.runLevel)" }
                if ($registered.execute -ne $witnessDaemon) { $claims += "Execute=$($registered.execute)" }
                Add-ControlRow 'settings.launchAtLogin.effect' `
                    $(if ($claims.Count -eq 0) { 'pass' } else { 'fail' }) `
                    $(if ($claims.Count -eq 0) {
                        "driving the switch to On through the automation plane registered " +
                        "'$witnessTaskName' in the Windows task scheduler: state=" +
                        "$($registered.state), logon trigger present, RunLevel=$($registered.runLevel) " +
                        "(the recorder's word for the XML's LeastPrivilege), Execute=" +
                        "$($registered.execute). Read by an API that did not write it."
                    } else {
                        "the task was registered and does not carry what the board's own row " +
                        "claims: $($claims -join '; ')"
                    }) @('Launch router daemon at sign-in') `
                    'Get-ScheduledTask (ScheduledTasks module over the Task Scheduler WMI provider)'
            }

            # -------------------------------------------------------------------- PERSISTENCE
            # The store, read off the disk by this script rather than by asking the app what it
            # saved, and then the shell CLOSED AND RELAUNCHED and the switch read back.
            $storeFile = Join-Path $witnessStateDir 'shell-settings.json'
            $stored = $null
            if (Test-Path $storeFile) {
                try { $stored = Get-Content $storeFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
            }
            Add-ControlRow 'settings.persistence.store' `
                $(if ($null -ne $stored -and $stored.LaunchAtLogin -eq $true) { 'pass' } else { 'fail' }) `
                $(if ($null -eq $stored) {
                    "nothing readable at $storeFile after the switch was driven, so the setting " +
                    "reached no durable store."
                } elseif ($stored.LaunchAtLogin -ne $true) {
                    "$storeFile holds LaunchAtLogin=$($stored.LaunchAtLogin) after the switch was " +
                    "driven to On."
                } else {
                    "$storeFile holds LaunchAtLogin=true, read off the disk by this script. The " +
                    "file is the recorder; the shell is not asked what it saved."
                }) @('Launch router daemon at sign-in') 'a read of the settings file by this script'

            Say "  closing the shell to measure whether the setting survives it"
            Stop-Process -Id $script:ShellProcessId -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 1200
            $window = Start-Shell
            if ($null -eq $window) {
                Add-ControlRow 'settings.persistence' 'unoracled' `
                    ('the shell could not be relaunched, so whether the setting survived a restart ' +
                     'was never read. Not a pass and not a failure of persistence.') `
                    @('Launch router daemon at sign-in')
            } elseif (-not (Invoke-Destination 'Settings')) {
                Add-ControlRow 'settings.persistence' 'unoracled' `
                    ('the relaunched shell could not be navigated to Settings, so the switch was ' +
                     'never read back.') @('Launch router daemon at sign-in')
            } else {
                Start-Sleep -Milliseconds 800
                $reloaded = Wait-ById $window $launchId 15
                $backState = 'unaddressable'
                if ($null -ne $reloaded) {
                    try {
                        $backState = [string] $reloaded.GetCurrentPattern(
                            [System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
                    } catch { $backState = "unreadable: $($_.Exception.Message)" }
                }
                Add-ControlRow 'settings.persistence' `
                    $(if ($backState -eq 'On') { 'pass' } else { 'fail' }) `
                    $(if ($backState -eq 'On') {
                        "the shell was terminated and launched again as a new process, and the " +
                        "switch reads On in the new one. Closing the shell no longer forgets the " +
                        "setting."
                    } else {
                        "the switch reads '$backState' in a freshly launched shell after being " +
                        "driven to On in the previous one, so the setting did not survive the " +
                        "process."
                    }) @('Launch router daemon at sign-in') `
                    'a second MCPRouter.Shell process, launched after the first was terminated'
            }

            # -------------------------------------------------------------------- COPY (DEF-088)
            if ($null -ne $window) {
                $sentinel = 'mcprouter-lane-sentinel-' + [guid]::NewGuid().ToString('N')
                & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -Command `
                    "Set-Clipboard -Value '$sentinel'" | Out-Null
                $endpointEl = Wait-ById $window 'settings.state.endpoint' 10
                $shown = ''
                if ($null -ne $endpointEl) { try { $shown = $endpointEl.Current.Name } catch { } }

                $copyButton = Wait-ById $window 'settings.action.copyEndpoint' 10
                $invoked = $false
                if ($null -ne $copyButton) {
                    try {
                        $copyButton.GetCurrentPattern(
                            [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                        $invoked = $true
                    } catch { }
                }
                Start-Sleep -Milliseconds 900

                # A DIFFERENT PROCESS reads it. Get-Clipboard in this process would still be a
                # different process from the shell, but running it out of a fresh STA host is what
                # the arm claims and it costs nothing to actually do.
                $clip = (& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -Command `
                    'Get-Clipboard -Raw' 2>$null | Out-String).Trim()

                if (-not $invoked) {
                    Add-ControlRow 'settings.copyEndpoint' 'fail' `
                        ('the Copy button is addressable and InvokePattern.Invoke() did not take, ' +
                         'so nothing could be copied.') @('Copy the loopback endpoint') `
                        'Get-Clipboard in a separate PowerShell process'
                } elseif ($clip -eq $sentinel) {
                    Add-ControlRow 'settings.copyEndpoint' 'fail' `
                        ("INERT: the button was invoked through the plane and the clipboard still " +
                         "holds the sentinel this lane put there. Nothing was copied.") `
                        @('Copy the loopback endpoint') `
                        'Get-Clipboard in a separate PowerShell process'
                } elseif ($shown -and $clip -ne $shown) {
                    Add-ControlRow 'settings.copyEndpoint' 'fail' `
                        ("the clipboard changed to '$clip' and the board displays '$shown', so the " +
                         "button copied something other than the endpoint beside it.") `
                        @('Copy the loopback endpoint') `
                        'Get-Clipboard in a separate PowerShell process'
                } elseif ($clip -notmatch '^http://127\.0\.0\.1:\d+$') {
                    Add-ControlRow 'settings.copyEndpoint' 'fail' `
                        ("the clipboard holds '$clip', which is not a loopback endpoint.") `
                        @('Copy the loopback endpoint') `
                        'Get-Clipboard in a separate PowerShell process'
                } else {
                    Add-ControlRow 'settings.copyEndpoint' 'pass' `
                        ("the clipboard held this lane's sentinel before the button was invoked and " +
                         "holds '$clip' after, read out of a separate PowerShell process. It " +
                         "matches the endpoint the board displays at settings.state.endpoint.") `
                        @('Copy the loopback endpoint') `
                        'Get-Clipboard in a separate PowerShell process'
                }
            }

            # -------------------------------------------------------------------- SILENCE
            # The presence control. A recorder that always answered "yes, and here are the
            # properties" would pass BASELINE by accident of ordering and EFFECT by construction;
            # only being required to say no at a moment when the answer is no separates a reader
            # from an echo. It is also the arm that makes turning the setting OFF mean something,
            # which is the half a user is most likely to be lied to about.
            $droveOff = 'no window'
            if ($null -ne $window) {
                $droveOff = Set-ToggleThroughPlane $window $launchId $false
                Start-Sleep -Milliseconds 800
            }
            $gone = Read-WitnessTask $witnessTaskName
            Add-ControlRow 'settings.launchAtLogin.silence' `
                $(if ($droveOff -eq 'ok' -and $null -eq $gone) { 'pass' }
                  elseif ($droveOff -ne 'ok') { 'unoracled' } else { 'fail' }) `
                $(if ($droveOff -ne 'ok') {
                    "the switch could not be driven back to Off through the plane ($droveOff), so " +
                    "removal was never attempted."
                } elseif ($null -eq $gone) {
                    "driving the switch back to Off removed '$witnessTaskName': Get-ScheduledTask " +
                    "reports absence again, so its yes above was a reading rather than an echo."
                } else {
                    "the switch reads Off and Get-ScheduledTask still reports the task present " +
                    "(state=$($gone.state)). Turning the setting off told the user something untrue."
                }) @('Launch router daemon at sign-in') `
                'Get-ScheduledTask (ScheduledTasks module over the Task Scheduler WMI provider)'

            # Never leave a scheduled task behind, whatever the arms concluded.
            if ($null -ne (Read-WitnessTask $witnessTaskName)) {
                Say "  cleaning up the witness task after the arms"
                & schtasks.exe /Delete /TN $witnessTaskName /F 2>&1 | Out-Null
            }
        }
    }

    # ------------------------------------------------------ DEF-075: the Discover detail dialog
    # The dialog is behind a store row, and the store rows are behind a registry search. On a host
    # where that search returns nothing the dialog is UNREACHABLE - which is reported as unoracled
    # rather than passed, because a check that could not run and a check that found nothing are the
    # same green. The structural rung on this surface is
    # MCPRouter.Shell.Tests/ViewAutomationSurfaceTests.
    # A shell that died during the settings census would otherwise skip this whole surface in
    # silence, which reads as "nothing to report" rather than "never measured". Relaunch, and if
    # that fails say so on a row.
    if (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) {
        Say "  the shell is gone; relaunching before the Discover detail census"
        $window = Start-Shell
    }
    if ($null -eq $window -or -not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) {
        Add-ControlRow 'discover.detail' 'unoracled' ('the shell was not running and could not be ' +
            'relaunched, so the detail dialog was never reached.')
    } else {
        $navLabels = @($destinations | ForEach-Object { $_.Label })
        if (-not (Invoke-Destination 'Discover')) {
            Add-ControlRow 'discover.detail' 'unoracled' ('Discover could not be re-actuated, so ' +
                'the detail dialog was never reached.')
        } else {
            $itemCond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::ListItem)
            $row = $null
            $until = (Get-Date).AddSeconds(45)
            while ((Get-Date) -lt $until -and $null -eq $row) {
                $items = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $itemCond)
                foreach ($candidate in $items) {
                    $n = ''
                    try { $n = $candidate.Current.Name } catch { }
                    if ($n -and $navLabels -notcontains $n) { $row = $candidate; break }
                }
                if ($null -eq $row) { Start-Sleep -Milliseconds 1500 }
            }

            if ($null -eq $row) {
                Add-ControlRow 'discover.detail' 'unoracled' ('the Discover board published no ' +
                    'store row within 45 s - the registry search returned nothing on this host - ' +
                    'so the detail dialog could not be opened. Not a finding about the dialog: ' +
                    'the harness cannot reach it. Its declared surface is checked at the ' +
                    'structural rung by MCPRouter.Shell.Tests/ViewAutomationSurfaceTests.')
            } else {
                $rowName = ''
                try { $rowName = $row.Current.Name } catch { }
                $opened = $false
                foreach ($attempt in 'invoke', 'select') {
                    try {
                        if ($attempt -eq 'invoke') {
                            $row.GetCurrentPattern(
                                [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                        } else {
                            $row.GetCurrentPattern(
                                [System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
                        }
                    } catch { continue }
                    $wait = (Get-Date).AddSeconds(6)
                    while ((Get-Date) -lt $wait) {
                        if ($null -ne (Find-ById $window 'discover.detail.root')) { $opened = $true; break }
                        Start-Sleep -Milliseconds 300
                    }
                    if ($opened) { break }
                }

                if (-not $opened) {
                    Add-ControlRow 'discover.detail' 'unoracled' ("the store row '$rowName' was " +
                        'found and neither Invoke nor Select opened the detail dialog on the ' +
                        'automation plane, so its controls were never reached.')
                } else {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dumper `
                        -ProcessId $script:ShellProcessId `
                        -Out (Join-Path $Out 'uia-shell-discover-detail.json') -View Control | Out-Null

                    $expectDetail = @(
                        'discover.detail.root',
                        'discover.detail.name',
                        'discover.detail.provenance',
                        'discover.detail.description',
                        'discover.detail.statement.headline',
                        'discover.detail.statement.body',
                        'discover.detail.statement.derivation',
                        'discover.detail.argv')
                    $missingDetail = @()
                    $unnamed = @()
                    foreach ($id in $expectDetail) {
                        $el = Wait-ById $window $id 5
                        if ($null -eq $el) { $missingDetail += $id; continue }
                        $n = ''
                        try { $n = $el.Current.Name } catch { }
                        if (-not $n) { $unnamed += $id }
                    }
                    if ($missingDetail.Count -gt 0) {
                        Add-ControlRow 'discover.detail' 'fail' ("opened from the row '$rowName'; " +
                            "these ids are absent from the tree: $($missingDetail -join ', ')")
                    } elseif ($unnamed.Count -gt 0) {
                        Add-ControlRow 'discover.detail' 'fail' ("opened from the row '$rowName'; " +
                            "these controls publish no accessible name: $($unnamed -join ', ')")
                    } else {
                        Add-ControlRow 'discover.detail' 'pass' ("opened from the row '$rowName'; " +
                            "all $($expectDetail.Count) checked control(s) are addressable by id " +
                            "and publish a name.")
                    }
                }
            }
        }
    }
}

$failed += $script:controlFailures

# ------------------------------------------------------------------ 4. grade
$measured  = @($results | Where-Object { $_.status -eq 'pass' -or $_.status -eq 'fail' }).Count
$passed    = @($results | Where-Object { $_.status -eq 'pass' }).Count
$unoracled = @($results | Where-Object { $_.status -eq 'unoracled' }).Count
$inconc    = @($results | Where-Object { $_.status -eq 'inconclusive' }).Count
$crashed   = @($results | Where-Object { $_.crashed }).Count

$report = [ordered]@{
    schema        = 'win-shell.uia-assert/1'
    subject       = 'MCPRouter.Shell - the Windows client, driven through the automation plane'
    capturedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    exePath       = $ExePath
    processId     = $script:ShellProcessId
    destinations  = $destinations.Count
    measured      = $measured
    passed        = $passed
    failed        = $failed
    crashed       = $crashed
    unoracled     = $unoracled
    inconclusive  = $inconc
    controls      = $controls
    controlsFailed = $script:controlFailures
    results       = $results
}
$reportPath = Join-Path $Out 'assert-report.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8
Say "wrote $reportPath"
Say ("destinations {0} · measured {1} · passed {2} · FAILED {3} · unoracled {4} · inconclusive {5}" -f `
     $destinations.Count, $measured, $passed, $failed, $unoracled, $inconc)
Say ("controls checked {0} · FAILED {1}" -f $controls.Count, $script:controlFailures)

if ($measured -eq 0) {
    Stop-Lane 3 ("NO VERDICT: not one destination could be actuated and read. A lane that measured " +
        "nothing is not a lane that passed.")
}
if ($failed -gt 0) {
    Stop-Lane 1 "$failed destination(s) failed against the real shell on the automation plane."
}
Stop-Lane 0 ("pass: $passed of $($destinations.Count) destination(s) were actuated through the " +
    "automation plane and read back distinct, correctly-titled trees, out of process, without the " +
    "target ever being foregrounded. $unoracled unreachable and $inconc unactuable are reported, " +
    "not counted as passes.")
