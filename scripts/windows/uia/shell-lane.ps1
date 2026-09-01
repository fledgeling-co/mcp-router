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
    results       = $results
}
$reportPath = Join-Path $Out 'assert-report.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8
Say "wrote $reportPath"
Say ("destinations {0} · measured {1} · passed {2} · FAILED {3} · unoracled {4} · inconclusive {5}" -f `
     $destinations.Count, $measured, $passed, $failed, $unoracled, $inconc)

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
