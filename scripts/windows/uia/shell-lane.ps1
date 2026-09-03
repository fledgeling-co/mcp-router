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

$script:RouterProcessId = 0

function Stop-Lane([int] $code, [string] $why) {
    if ($script:ShellProcessId -ne 0) {
        Stop-Process -Id $script:ShellProcessId -Force -ErrorAction SilentlyContinue
        Say "shell pid $($script:ShellProcessId) stopped"
    }
    if ($script:RouterProcessId -ne 0) {
        Stop-Process -Id $script:RouterProcessId -Force -ErrorAction SilentlyContinue
        Say "lane router pid $($script:RouterProcessId) stopped"
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

# ------------------------------------------------- the lane's OWN router (DEF-102)
# Section 3e drives "Remove server..." for real, and a removal is not a thing to try out on
# somebody's machine: the router deletes the entry from servers.json, reloads, and tells every
# attached agent its tool list changed. So the lane brings its own router, on its own port, over
# its own home, holding two servers that exist for no other purpose.
#
# MCP_ROUTER_HOME is set BEFORE the shell is launched because the shell resolves the control
# endpoint and the control token from it at startup; setting it afterwards would leave the board
# polling the operator's router while this script measured its own. The port is taken from the
# OS - bind to 0, read what was assigned, release - rather than picked, because a hardcoded one
# either collides with the operator's real router or silently measures it.
$routerHome = Join-Path $Out 'router-home'
$routerEntry = Join-Path $repoRoot 'dist\index.js'
$laneServerAlpha = 'lane-witness-alpha'
$laneServerBeta  = 'lane-witness-beta'
# DEF-302's pair, separate from DEF-102's above because that section removes both of its own before
# the Cleanup arms run. Neither is ever called, which is exactly what puts them on the Cleanup
# board: its rows are the router's never-called servers now, not sample data.
$laneCleanupGamma = 'lane-cleanup-gamma'
$laneCleanupDelta = 'lane-cleanup-delta'
$env:MCP_ROUTER_HOME = $routerHome
New-Item -ItemType Directory -Force -Path $routerHome | Out-Null
Remove-Item (Join-Path $routerHome 'control.token') -ErrorAction SilentlyContinue

$probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$probe.Start()
$routerPort = ([System.Net.IPEndPoint] $probe.LocalEndpoint).Port
$probe.Stop()
$routerBase = "http://127.0.0.1:$routerPort"

# `cmd /c exit` is a command that exists on every Windows and does nothing. The router adopts a
# stdio server from its declaration and does not spawn the child until something calls a tool, so
# these two never run; what they are is two names in a list this lane can watch appear and go.
@{
    port       = $routerPort
    mcpServers = @{
        $laneServerAlpha  = @{ command = 'cmd'; args = @('/c', 'exit') }
        $laneServerBeta   = @{ command = 'cmd'; args = @('/c', 'exit') }
        $laneCleanupGamma = @{ command = 'cmd'; args = @('/c', 'exit') }
        $laneCleanupDelta = @{ command = 'cmd'; args = @('/c', 'exit') }
    }
} | ConvertTo-Json -Depth 6 |
    ForEach-Object {
        # NOT Set-Content -Encoding UTF8. Windows PowerShell 5.1 writes a BOM under that name, and
        # node's JSON.parse rejects a leading U+FEFF - measured here, and the router died at
        # startup with `Unexpected token, "{" is not valid JSON` while every symptom pointed at the
        # config's contents. WriteAllText writes UTF-8 with no BOM.
        [System.IO.File]::WriteAllText((Join-Path $routerHome 'servers.json'), $_)
    }

# The reader for every DEF-102 arm below. It is the ROUTER's account of its own server list, taken
# over the loopback control API by this script - a different process from the one that pressed the
# button, and one with no view of the dialog at all. What the app says it asked is not evidence
# here; what the router lists is.
function Read-RouterServers {
    try {
        $answer = Invoke-RestMethod -Uri "$routerBase/servers" -TimeoutSec 5 -ErrorAction Stop
        # `,@(...)` rather than `@(...)`. PowerShell unrolls a returned collection, and an EMPTY
        # one unrolls to nothing at all - so a router that had answered correctly with an empty
        # list came back as $null, indistinguishable from a router that never answered. Measured
        # here on the last removal, where the list is legitimately empty: the silence arm reported
        # `unoracled` over a removal the router's own log shows it had performed.
        return ,@(@($answer.servers) | ForEach-Object { [string] $_.name })
    } catch {
        return $null
    }
}

$routerLog = Join-Path $Out 'lane-router.log'
$nodeExe = Get-Command node -ErrorAction SilentlyContinue
$routerUp = $false
if ($null -eq $nodeExe) {
    Say "no node on PATH; the lane's router will not be started (DEF-102 arms report unoracled)"
} elseif (-not (Test-Path $routerEntry)) {
    Say "no built router at $routerEntry; run 'npx tsc -p tsconfig.json' (DEF-102 arms report unoracled)"
} else {
    $routerProc = Start-Process -FilePath $nodeExe.Source -ArgumentList @($routerEntry) `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $routerLog -RedirectStandardError "$routerLog.err"
    $script:RouterProcessId = $routerProc.Id
    Say "lane router: pid $($routerProc.Id) on $routerBase, home $routerHome"
    $until = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $until) {
        if ($null -ne (Read-RouterServers)) { $routerUp = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $routerUp) {
        Say "  the lane's router never answered /servers within 40s; see $routerLog"
    } else {
        Say "  the lane's router answers /servers: $((Read-RouterServers) -join ', ')"
    }
}

if (-not (Test-Path $ExePath)) {
    Stop-Lane 3 ("NO VERDICT: the shell is not built at $ExePath. Run scripts/windows/build-shell.ps1. " +
        "A missing binary is a build job, never a finished gap.")
}
Say "shell binary: $ExePath (written $((Get-Item $ExePath).LastWriteTimeUtc.ToString('o')))"

# ------------------------------------------------- 0. is this binary the tree it is being read against?
# MEASURED 2026-09-03, and this lane fabricated twelve failures before the check existed. The
# integration pass built the merged shell with `MSBuild -p:Platform=x64`, which writes
# bin\x64\Debug\...; this lane reads bin\Debug\..., which nothing had written for twelve hours.
# Every control both runners had added came back "unaddressable" - a coherent, specific, entirely
# false report, indistinguishable from a real regression except by the exe's timestamp.
#
# That is BRIEF-a-stale-build-can-fabricate-a-failure-and-as-easily-a-pass, in this lane, on the
# day it was scheduled. The 'as easily a pass' half is the reason this stops the run rather than
# warning: a stale binary that still HAPPENS to satisfy every arm publishes a green about a build
# nobody is shipping, and nothing downstream can tell that green from an earned one.
#
# NO VERDICT rather than FAIL. A stale build is not a defect in the product; it is the lane being
# unable to speak about the product at all, and exit 3 is what this lane reserves for that.
# The comparand is the newest of the product's OWN assemblies beside the exe, not the exe.
# MCPRouter.Shell.exe is the apphost: an incremental build that changes only
# MCPRouter.Shell.Model relinks that project's dll, copies it here, and leaves the apphost
# untouched. Measured 2026-09-03: after a clean, successful build-shell.ps1 the exe still
# carried a timestamp seven minutes older than the source, and a guard reading the exe alone
# refused a tree that was in fact current. A guard that cries wolf gets switched off, which
# ends in the same place as one that fails open.
$builtFiles = @(Get-Item $ExePath) + @(Get-ChildItem -Path (Split-Path -Parent $ExePath) -Filter 'MCPRouter.*.dll' -File -ErrorAction SilentlyContinue)
$exeWritten = ($builtFiles | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
$sourceRoot = Join-Path $repoRoot 'app\windows'
# -notlike over two literal fragments rather than a regex, deliberately. The first version of this
# guard used -notmatch with an escaped pattern, PowerShell rejected the pattern at runtime, the
# exception left $newerSource empty, and the guard printed 'shell binary is current' over a source
# file that was demonstrably newer. A broken filter returns nothing and nothing reads exactly like
# 'no finding' - which is the failure this whole rung exists to prevent, reproduced inside the
# check written to prevent it. The enumeration is now counted, and a count of zero FILES is itself
# refused: this tree has hundreds, so zero means the walk failed rather than that nothing changed.
$srcFiles = @(Get-ChildItem -Path $sourceRoot -Recurse -File -Include *.cs,*.xaml,*.csproj -ErrorAction SilentlyContinue |
    Where-Object { ($_.FullName -notlike '*in\*') -and ($_.FullName -notlike '*\obj\*') })
if ($srcFiles.Count -eq 0) {
    Stop-Lane 3 ("NO VERDICT: the freshness walk over $sourceRoot found NO source files at all. " +
        "That is the walk failing, not the tree being empty, and a guard that cannot see the source " +
        "cannot say the binary is current.")
}
$newerSource = @($srcFiles | Where-Object { $_.LastWriteTimeUtc -gt $exeWritten } |
    Sort-Object LastWriteTimeUtc -Descending)
if ($newerSource.Count -gt 0) {
    $lead = ($newerSource | Select-Object -First 3 | ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1) }) -join ', '
    Stop-Lane 3 ("NO VERDICT: the shell binary is OLDER than the source it would be read against - " +
        "$($newerSource.Count) of $($srcFiles.Count) tracked file(s) under app\windows have changed " +
        "since the newest of its $($builtFiles.Count) build output(s) was written " +
        "($($exeWritten.ToString('o'))). Newest source: $lead. Run " +
        "scripts/windows/build-shell.ps1 and try again. Note that MSBuild -p:Platform=x64 writes " +
        "bin\x64\Debug while this lane reads bin\Debug, which is how a twelve-hour-old binary once " +
        "produced twelve specific, coherent and entirely false failures here.")
}
Say ("shell binary is current: none of $($srcFiles.Count) tracked source file(s) under app\windows is newer than it")

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
        # A WinUI process publishes MORE THAN ONE top-level window, and taking the first one that
        # matches the pid is how this lane once measured a tooltip.
        #
        # Measured 2026-09-02 while arming the DEF-089 arm: the run bound to a
        # Microsoft.UI.Content.PopupWindowSiteBridge - the host for a tooltip that happened to be
        # up when the search ran - and from then on every read was scoped to that popup's subtree.
        # The window title read as the empty string, no element carried the name of any
        # destination and no element carried the automation id "Nav", so eight destinations came
        # back `unoracled` and three rows failed. The dump taken in the same second, which walks
        # by process id rather than through this handle, holds a complete and healthy tree with
        # all ten pane items in it. Every one of those rows was a statement about the harness's
        # handle and none of them was about the product.
        #
        # So the shell's own window is identified by its class, and a run that cannot find that
        # class keeps waiting rather than settling for whichever window answered first.
        $root   = [System.Windows.Automation.AutomationElement]::RootElement
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $child  = $walker.GetFirstChild($root)
        while ($null -ne $child) {
            try {
                if ($child.Current.ProcessId -eq $proc.Id -and
                    $child.Current.ClassName -eq 'WinUIDesktopWin32WindowClass') {
                    Say ("  bound to the shell's own window: class " +
                         "'$($child.Current.ClassName)', title '$($child.Current.Name)'")
                    return $child
                }
            } catch { }
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
# A dialog's buttons are named, not identified: ContentDialog builds them from PrimaryButtonText
# and CloseButtonText and stamps no automation id on either. Finding them by name is therefore not
# a shortcut around an id - there is no id to use - and the names come from ServersCopy, which is
# the same file the dialog is built from.
function Wait-ByName($root, [string] $name, [int] $seconds = 8) {
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $until = (Get-Date).AddSeconds($seconds)
    while ($true) {
        $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
        if ($null -ne $el) { return $el }
        if ((Get-Date) -ge $until) { return $null }
        Start-Sleep -Milliseconds 400
    }
}

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

            # ------------------------------------------------- DEF-101: the notification-area icon
            # THE RECORDER IS NOT THE WRITER, and here that is the whole exercise. DEF-101 was a
            # switch with nothing behind it, and the tempting fix - place an icon and read it back
            # through the handle that placed it - is the same defect wearing a proof. So the icon is
            # registered by GUID, which is a name another program can hold, and every read below is
            # a separate powershell.exe calling Shell_NotifyIconGetRect. That API is answered by the
            # shell's notification area. Neither this script nor that process ever asks the app.
            #
            # WHY THE BASELINE IS DRIVEN RATHER THAN OBSERVED. The shell places the icon at launch
            # from the stored setting, whose default is on, so by the time this section runs the
            # icon is already there. An arm that read "present" first and "present" again would be
            # measuring nothing. Driving the switch OFF first is what makes the baseline mean
            # something: the shell's own NIM_DELETE clears the record under that GUID - including a
            # record a killed earlier run left behind - so a later "present" cannot be somebody
            # else's leftover.
            $iconProbe = Join-Path $PSScriptRoot 'notification-icon-probe.ps1'
            $iconRecorder = 'Shell_NotifyIconGetRect in a separate powershell.exe process'
            $ambientId = 'settings.toggle.ShowAmbientIcon'

            function Read-NotificationIcon {
                # $null means the question could not be asked at all, which is neither yes nor no.
                $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $iconProbe 2>$null |
                    Out-String
                if (-not $raw.Trim()) { return $null }
                try { $answer = $raw | ConvertFrom-Json } catch { return $null }
                if (-not $answer.asked) { return $null }
                return $answer
            }

            # -------------------------------------------------------------------- BASELINE
            $droveIconOff = Set-ToggleThroughPlane $window $ambientId $false
            Start-Sleep -Milliseconds 900
            $iconBefore = Read-NotificationIcon
            Add-ControlRow 'settings.ambientIcon.baseline' `
                $(if ($null -eq $iconBefore) { 'unoracled' }
                  elseif ($droveIconOff -ne 'ok') { 'unoracled' }
                  elseif (-not $iconBefore.found) { 'pass' } else { 'fail' }) `
                $(if ($null -eq $iconBefore) {
                    "Shell_NotifyIconGetRect could not be called at all, so nothing was read about " +
                    "the notification area. Not a pass and not a failure."
                } elseif ($droveIconOff -ne 'ok') {
                    "the switch could not be driven to Off through the plane ($droveIconOff), so " +
                    "the baseline was never established."
                } elseif (-not $iconBefore.found) {
                    "with the switch driven Off, a separate process asks the shell for the icon at " +
                    "$($iconBefore.guid) and is told there is none (HRESULT $($iconBefore.hresult)). " +
                    "The recorder is capable of saying no, and any yes below is this run's."
                } else {
                    "the switch reads Off and the notification area still holds the icon at " +
                    "$($iconBefore.guid), so the arms below would be about a leftover."
                }) @('Show status in notification area') $iconRecorder

            # -------------------------------------------------------------------- EFFECT
            $droveIconOn = Set-ToggleThroughPlane $window $ambientId $true
            Start-Sleep -Milliseconds 1200
            $iconAfter = Read-NotificationIcon
            Add-ControlRow 'settings.ambientIcon.effect' `
                $(if ($null -eq $iconAfter) { 'unoracled' }
                  elseif ($droveIconOn -ne 'ok') { 'fail' }
                  elseif ($iconAfter.found) { 'pass' } else { 'fail' }) `
                $(if ($null -eq $iconAfter) {
                    "Shell_NotifyIconGetRect could not be called, so whether the icon appeared was " +
                    "never read."
                } elseif ($droveIconOn -ne 'ok') {
                    "the switch could not be driven to On through the plane: $droveIconOn"
                } elseif ($iconAfter.found) {
                    "driving the switch to On through the automation plane put an icon in the " +
                    "Windows notification area at $($iconAfter.guid): a separate process asked the " +
                    "shell for its rectangle and got $($iconAfter.rect.left),$($iconAfter.rect.top) " +
                    "to $($iconAfter.rect.right),$($iconAfter.rect.bottom) (HRESULT " +
                    "$($iconAfter.hresult)). Read by an API this application never called."
                } else {
                    "INERT BEYOND THE PROCESS: the switch reads On through the plane and the " +
                    "notification area reports no icon at $($iconAfter.guid) (HRESULT " +
                    "$($iconAfter.hresult)). The control moved and the shell heard nothing."
                }) @('Show status in notification area') $iconRecorder

            # -------------------------------------------------------------------- SILENCE
            $droveIconBack = Set-ToggleThroughPlane $window $ambientId $false
            Start-Sleep -Milliseconds 1200
            $iconGone = Read-NotificationIcon
            Add-ControlRow 'settings.ambientIcon.silence' `
                $(if ($null -eq $iconGone) { 'unoracled' }
                  elseif ($droveIconBack -ne 'ok') { 'unoracled' }
                  elseif (-not $iconGone.found) { 'pass' } else { 'fail' }) `
                $(if ($null -eq $iconGone) {
                    "Shell_NotifyIconGetRect could not be called, so removal was never read."
                } elseif ($droveIconBack -ne 'ok') {
                    "the switch could not be driven back to Off through the plane " +
                    "($droveIconBack), so removal was never attempted."
                } elseif (-not $iconGone.found) {
                    "driving the switch back to Off took the icon out of the notification area: " +
                    "the same reader that found it a moment ago now answers HRESULT " +
                    "$($iconGone.hresult). Its yes above was a reading rather than an echo, and " +
                    "turning the setting off tells the user something true."
                } else {
                    "the switch reads Off and the notification area still holds the icon. Turning " +
                    "the setting off told the user something untrue."
                }) @('Show status in notification area') $iconRecorder
        }
    }

    # ------------------------------------------------------- DEF-102: the destructive confirmation
    # "Require confirmation on destructive operations" was a switch no board consulted, over a build
    # with no destructive path in it at all. Both halves landed together: the Servers board can now
    # ask the router to remove a server - the one irreversible verb this app sends - and it reads
    # the setting at the moment the button is pressed. The label was narrowed with it, from a class
    # of operations the build does not have to the one it does.
    #
    # WHAT THE ARMS BELOW REFUSE TO ACCEPT AS EVIDENCE. Not that a dialog appeared: a dialog is the
    # app's account of having asked. Not that the row vanished from the table: the table is drawn by
    # the same process. What is graded is the ROUTER's own list of servers, taken over the control
    # API by this script. The EFFECT arm is a removal that was DECLINED, and the router still
    # holding the server is the only thing that can tell a gate from a decoration.
    $confirmId = 'settings.toggle.RequireConfirmationOnDestructive'
    $routerRecorder = "the router's own /servers listing, read over the control API by this script"

    if (-not $routerUp) {
        foreach ($arm in @('baseline', 'effect', 'silence')) {
            Add-ControlRow "settings.requireConfirmation.$arm" 'unoracled' `
                ("the lane's own router was never started (no node, no dist/index.js, or it did not " +
                 "answer), so no removal was attempted and nothing was read back from it. Not a " +
                 "pass and not a failure.") @('Confirm before removing a server') $routerRecorder
        }
    } elseif (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) {
        foreach ($arm in @('baseline', 'effect', 'silence')) {
            Add-ControlRow "settings.requireConfirmation.$arm" 'unoracled' `
                ('the shell was not running, so the removal path was never driven.') `
                @('Confirm before removing a server') $routerRecorder
        }
    } else {
        # A helper rather than three copies: select the row, press Remove, and say what the surface
        # did - whether a confirmation was raised, and which way it was answered.
        function Invoke-RemoveThroughPlane {
            param($Root, [string] $Server, [string] $Answer)
            $row = Wait-ById $Root ('servers.row.' + $Server) 15
            if ($null -eq $row) { return "no row for $Server" }
            try {
                $row.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            } catch { return "the row would not invoke: $($_.Exception.Message)" }
            Start-Sleep -Milliseconds 500

            $remove = Wait-ById $Root 'servers.action.remove' 10
            if ($null -eq $remove) { return 'the Remove button is unaddressable' }
            try {
                if (-not $remove.Current.IsEnabled) { return 'the Remove button is disabled' }
                $remove.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            } catch { return "the Remove button would not invoke: $($_.Exception.Message)" }
            Start-Sleep -Milliseconds 700

            $wanted = if ($Answer -eq 'commit') { 'Remove permanently' } else { 'Keep it' }
            $button = Wait-ByName $Root $wanted 6
            if ($null -eq $button) { return 'no confirmation was raised' }
            try {
                $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            } catch { return "the '$wanted' button would not invoke: $($_.Exception.Message)" }
            Start-Sleep -Milliseconds 1200
            return "confirmed:$Answer"
        }

        # Driving this pair means moving between two boards: the switch lives on Settings and the
        # button on Servers. The first version of this section drove the switch while the Servers
        # board was up - where it is not in the tree at all - and all three arms reported
        # `unaddressable`, which is a statement about where this script was looking and not about
        # the product. Every drive now navigates to Settings first and back afterwards.
        function Set-ConfirmSetting {
            param($Root, [bool] $On)
            if (-not (Invoke-Destination 'Settings')) { return 'Settings could not be actuated' }
            Start-Sleep -Milliseconds 800
            return (Set-ToggleThroughPlane $Root $confirmId $On)
        }

        $listedAtStart = Read-RouterServers

        # -------------------------------------------------------------------- BASELINE
        Add-ControlRow 'settings.requireConfirmation.baseline' `
            $(if ($null -eq $listedAtStart) { 'unoracled' }
              elseif (($listedAtStart -contains $laneServerAlpha) -and
                      ($listedAtStart -contains $laneServerBeta)) { 'pass' } else { 'fail' }) `
            $(if ($null -eq $listedAtStart) {
                "the router stopped answering /servers before anything was driven."
            } elseif (($listedAtStart -contains $laneServerAlpha) -and
                      ($listedAtStart -contains $laneServerBeta)) {
                "the router lists both servers this lane declared - " +
                "$($listedAtStart -join ', ') - before any removal is attempted, so the arms below " +
                "measure removals rather than absences that were already there."
            } else {
                "the router lists $($listedAtStart -join ', '), which does not hold both of this " +
                "lane's servers, so a later absence would prove nothing."
            }) @('Confirm before removing a server') $routerRecorder

        # -------------------------------------------------------------------- EFFECT
        # The setting ON, the removal DECLINED, and the server read back out of the router. This is
        # the arm the row exists for: a confirmation that is merely displayed and then ignored looks
        # exactly like one that gates, right up until the moment somebody presses Keep it.
        $droveConfirmOn = Set-ConfirmSetting $window $true
        $onServers = $false
        if ($droveConfirmOn -eq 'ok') {
            $onServers = Invoke-Destination 'Servers'
            Start-Sleep -Milliseconds 1500
        }
        $declined = 'not attempted'
        $afterDecline = $null
        if ($onServers) {
            $declined = Invoke-RemoveThroughPlane $window $laneServerAlpha 'decline'
            $afterDecline = Read-RouterServers
        }
        Add-ControlRow 'settings.requireConfirmation.effect' `
            $(if ($droveConfirmOn -ne 'ok' -or -not $onServers) { 'unoracled' }
              elseif ($declined -ne 'confirmed:decline') { 'fail' }
              elseif ($null -eq $afterDecline) { 'unoracled' }
              elseif ($afterDecline -contains $laneServerAlpha) { 'pass' } else { 'fail' }) `
            $(if ($droveConfirmOn -ne 'ok') {
                "the confirmation switch could not be driven to On through the plane " +
                "($droveConfirmOn), so no removal was attempted."
            } elseif (-not $onServers) {
                "the Servers destination could not be actuated, so the removal path was never reached."
            } elseif ($declined -ne 'confirmed:decline') {
                "with the setting On, pressing Remove did not produce a confirmation this lane " +
                "could decline: $declined. A destructive button that acts without asking is the " +
                "defect this setting is supposed to prevent."
            } elseif ($null -eq $afterDecline) {
                "the router stopped answering after the removal was declined, so what it holds was " +
                "never read."
            } elseif ($afterDecline -contains $laneServerAlpha) {
                "with the setting On, Remove raised a confirmation, this lane pressed 'Keep it', " +
                "and the router still lists $laneServerAlpha (now: $($afterDecline -join ', ')). " +
                "The refusal is read out of the router, not out of the dialog: the app's account of " +
                "having asked is not evidence that it obeyed the answer."
            } else {
                "the confirmation was declined and the router no longer lists $laneServerAlpha " +
                "(now: $($afterDecline -join ', ')). The dialog was a decoration over an operation " +
                "that had already been decided."
            }) @('Confirm before removing a server') $routerRecorder

        # A confirmation that can only ever refuse is not a gate either, so the same path is driven
        # once more and ACCEPTED. Its own row, because "declining stops it" and "accepting lets it
        # through" are two facts and folding them into one green loses whichever failed.
        $committed = 'not attempted'
        $afterCommit = $null
        if ($onServers) {
            $committed = Invoke-RemoveThroughPlane $window $laneServerAlpha 'commit'
            $afterCommit = Read-RouterServers
        }
        Add-ControlRow 'settings.requireConfirmation.accepted' `
            $(if ($droveConfirmOn -ne 'ok' -or -not $onServers) { 'unoracled' }
              elseif ($committed -ne 'confirmed:commit') { 'fail' }
              elseif ($null -eq $afterCommit) { 'unoracled' }
              elseif ($afterCommit -notcontains $laneServerAlpha) { 'pass' } else { 'fail' }) `
            $(if ($droveConfirmOn -ne 'ok' -or -not $onServers) {
                "the setting or the board was not reachable, so acceptance was never driven."
            } elseif ($committed -ne 'confirmed:commit') {
                "the confirmation could not be accepted through the plane: $committed"
            } elseif ($null -eq $afterCommit) {
                "the router stopped answering after the removal was accepted."
            } elseif ($afterCommit -notcontains $laneServerAlpha) {
                "pressing 'Remove permanently' removed $laneServerAlpha from the ROUTER - it now " +
                "lists $(if ($afterCommit.Count) { $afterCommit -join ', ' } else { 'nothing' }). " +
                "The gate opens as well as closes."
            } else {
                "the confirmation was accepted and the router still lists $laneServerAlpha, so the " +
                "button asks a question whose yes it does not act on."
            }) @('Confirm before removing a server') $routerRecorder

        # -------------------------------------------------------------------- SILENCE
        # The setting OFF. The recorder has to be able to report the operation going through
        # UNASKED, or its yes above was never a reading of the setting - it would pass identically
        # over a board that always confirms and never consults anything.
        $droveConfirmOff = Set-ConfirmSetting $window $false
        $onServersAgain = $false
        if ($droveConfirmOff -eq 'ok') {
            $onServersAgain = Invoke-Destination 'Servers'
            Start-Sleep -Milliseconds 1500
        }
        $unasked = 'not attempted'
        $afterSilence = $null
        if ($onServersAgain) {
            $unasked = Invoke-RemoveThroughPlane $window $laneServerBeta 'decline'
            $afterSilence = Read-RouterServers
        }
        Add-ControlRow 'settings.requireConfirmation.silence' `
            $(if ($droveConfirmOff -ne 'ok' -or -not $onServersAgain) { 'unoracled' }
              elseif ($unasked -ne 'no confirmation was raised') { 'fail' }
              elseif ($null -eq $afterSilence) { 'unoracled' }
              elseif ($afterSilence -notcontains $laneServerBeta) { 'pass' } else { 'fail' }) `
            $(if ($droveConfirmOff -ne 'ok' -or -not $onServersAgain) {
                "the setting could not be driven to Off ($droveConfirmOff), or the board was " +
                "unreachable, so the " +
                "unconfirmed path was never driven."
            } elseif ($unasked -ne 'no confirmation was raised') {
                "with the setting Off, pressing Remove still produced a confirmation ($unasked). " +
                "The switch is not being read: turning it off removes no prompt."
            } elseif ($null -eq $afterSilence) {
                "the router stopped answering, so the unconfirmed removal was never read back."
            } elseif ($afterSilence -notcontains $laneServerBeta) {
                "with the setting Off, Remove raised no confirmation at all and the router no " +
                "longer lists $laneServerBeta (now: " +
                "$(if ($afterSilence.Count) { $afterSilence -join ', ' } else { 'nothing' })). The " +
                "prompt above was the setting being obeyed rather than a dialog this board always " +
                "shows."
            } else {
                "no confirmation was raised and the router still lists $laneServerBeta, so the " +
                "button did nothing at all with the setting off."
            }) @('Confirm before removing a server') $routerRecorder
    }


    # ------------------------------------------------- DEF-302: the Cleanup board's own destructive control
    # The Servers board's Remove was the first destructive control in this product and DEF-102 gave
    # it a gate. The Cleanup board carried a SECOND one - `Remove selected...` - whose entire body
    # was the comment `// Removal dialog logic`, over rows invented by
    # `CleanupBoardModel.PopulateSampleData`. So an operator who turned "Confirm before removing a
    # server" on had covered the Remove that worked and not the Remove that did not, and the board
    # was offering to remove servers that were not theirs.
    #
    # These four arms are wc2's, over this board, and they refuse the same things as evidence. Not
    # that a dialog appeared: that is the app's account of having asked. Not that the row left the
    # table: the table is drawn by the process that pressed the button. What is graded is the
    # ROUTER's own list of servers, read over the control API by this script.
    #
    # Two servers of this lane's own, separate from DEF-102's pair, because that section removes
    # both of its own before this one runs.
    $cleanupRecorder = "the router's own /servers listing, read over the control API by this script"

    if (-not $routerUp) {
        foreach ($arm in @('baseline', 'effect', 'accepted', 'silence')) {
            Add-ControlRow "cleanup.requireConfirmation.$arm" 'unoracled' `
                ("the lane's own router was never started (no node, no dist/index.js, or it did not " +
                 "answer), so no removal was attempted from the Cleanup board and nothing was read " +
                 "back. Not a pass and not a failure.") @('Remove selected…') $cleanupRecorder
        }
    } elseif (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) {
        foreach ($arm in @('baseline', 'effect', 'accepted', 'silence')) {
            Add-ControlRow "cleanup.requireConfirmation.$arm" 'unoracled' `
                ('the shell was not running, so the Cleanup board removal path was never driven.') `
                @('Remove selected…') $cleanupRecorder
        }
    } else {
        # Tick one row, press Remove selected, and answer the confirmation - or report that there
        # was none to answer. The row is addressed by AutomationId (`cleanup.row.<name>`), never by
        # its accessible name: a name search returns the first match anywhere in the tree.
        function Invoke-CleanupRemoveThroughPlane {
            param($Root, [string] $Server, [string] $Answer)
            $box = Wait-ById $Root ('cleanup.row.' + $Server) 20
            if ($null -eq $box) { return "no row for $Server" }
            try {
                $toggle = $box.GetCurrentPattern(
                    [System.Windows.Automation.TogglePattern]::Pattern)
                $guard = 0
                while ($toggle.Current.ToggleState -ne
                       [System.Windows.Automation.ToggleState]::On -and $guard -lt 3) {
                    $toggle.Toggle()
                    Start-Sleep -Milliseconds 300
                    $guard++
                }
                if ($toggle.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) {
                    return "the row for $Server would not tick"
                }
            } catch { return "the row for $Server would not toggle: $($_.Exception.Message)" }
            Start-Sleep -Milliseconds 400

            $remove = Wait-ById $Root 'cleanup.action.removeSelected' 10
            if ($null -eq $remove) { return 'the Remove selected button is unaddressable' }
            try {
                if (-not $remove.Current.IsEnabled) {
                    return 'the Remove selected button is disabled with a row ticked'
                }
                $remove.GetCurrentPattern(
                    [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            } catch {
                return "the Remove selected button would not invoke: $($_.Exception.Message)"
            }
            Start-Sleep -Milliseconds 700

            # One row is ticked, so the cancel label is the singular one the board composes.
            $wanted = if ($Answer -eq 'commit') { 'Remove permanently' } else { 'Keep it' }
            $button = Wait-ByName $Root $wanted 6
            if ($null -eq $button) { return 'no confirmation was raised' }
            try {
                $button.GetCurrentPattern(
                    [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            } catch { return "the '$wanted' button would not invoke: $($_.Exception.Message)" }
            Start-Sleep -Milliseconds 1500
            return "confirmed:$Answer"
        }

        $cleanupAtStart = Read-RouterServers

        # -------------------------------------------------------------------- BASELINE
        Add-ControlRow 'cleanup.requireConfirmation.baseline' `
            $(if ($null -eq $cleanupAtStart) { 'unoracled' }
              elseif (($cleanupAtStart -contains $laneCleanupGamma) -and
                      ($cleanupAtStart -contains $laneCleanupDelta)) { 'pass' } else { 'fail' }) `
            $(if ($null -eq $cleanupAtStart) {
                "the router stopped answering /servers before the Cleanup arms were driven."
            } elseif (($cleanupAtStart -contains $laneCleanupGamma) -and
                      ($cleanupAtStart -contains $laneCleanupDelta)) {
                "the router lists both servers this lane declared for the Cleanup board - " +
                "$($cleanupAtStart -join ', ') - before any removal is attempted from it, so the " +
                "arms below measure removals rather than absences that were already there. " +
                "Neither has ever been called, which is what puts them on this board at all: the " +
                "rows come from the router's own usage figures now, not from sample data."
            } else {
                "the router lists $($cleanupAtStart -join ', '), which does not hold both of the " +
                "Cleanup lane's servers, so a later absence would prove nothing."
            }) @('Remove selected…') $cleanupRecorder

        # -------------------------------------------------------------------- EFFECT
        # Setting ON, removal DECLINED, and the server read back out of the router. A confirmation
        # that is displayed and then ignored looks exactly like one that gates, right up until
        # somebody presses Keep it.
        $droveCleanupOn = Set-ConfirmSetting $window $true
        $onCleanup = $false
        if ($droveCleanupOn -eq 'ok') {
            $onCleanup = Invoke-Destination 'Cleanup'
            Start-Sleep -Milliseconds 1800
        }
        $cleanupDeclined = 'not attempted'
        $afterCleanupDecline = $null
        if ($onCleanup) {
            $cleanupDeclined = Invoke-CleanupRemoveThroughPlane $window $laneCleanupGamma 'decline'
            $afterCleanupDecline = Read-RouterServers
        }
        Add-ControlRow 'cleanup.requireConfirmation.effect' `
            $(if ($droveCleanupOn -ne 'ok' -or -not $onCleanup) { 'unoracled' }
              elseif ($cleanupDeclined -ne 'confirmed:decline') { 'fail' }
              elseif ($null -eq $afterCleanupDecline) { 'unoracled' }
              elseif ($afterCleanupDecline -contains $laneCleanupGamma) { 'pass' } else { 'fail' }) `
            $(if ($droveCleanupOn -ne 'ok') {
                "the confirmation switch could not be driven to On through the plane " +
                "($droveCleanupOn), so no removal was attempted from the Cleanup board."
            } elseif (-not $onCleanup) {
                "the Cleanup destination could not be actuated, so its removal path was never reached."
            } elseif ($cleanupDeclined -ne 'confirmed:decline') {
                "with the setting On, pressing Remove selected did not produce a confirmation this " +
                "lane could decline: $cleanupDeclined. This is the state DEF-302 was filed in - a " +
                "destructive button that asks nothing - and it is what this arm exists to catch."
            } elseif ($null -eq $afterCleanupDecline) {
                "the router stopped answering after the Cleanup removal was declined."
            } elseif ($afterCleanupDecline -contains $laneCleanupGamma) {
                "with the setting On, the Cleanup board's Remove selected raised a confirmation, " +
                "this lane pressed 'Keep it', and the router still lists $laneCleanupGamma (now: " +
                "$($afterCleanupDecline -join ', ')). The refusal is read out of the ROUTER, not " +
                "out of the dialog: the app's account of having asked is not evidence that it " +
                "obeyed the answer."
            } else {
                "the confirmation was declined and the router no longer lists $laneCleanupGamma " +
                "(now: $($afterCleanupDecline -join ', ')). The dialog was a decoration over an " +
                "operation that had already been decided."
            }) @('Remove selected…') $cleanupRecorder

        # A gate that can only refuse is not a gate. Its own row, because "declining stops it" and
        # "accepting lets it through" are two facts and one green would lose whichever failed.
        $cleanupCommitted = 'not attempted'
        $afterCleanupCommit = $null
        if ($onCleanup) {
            $cleanupCommitted = Invoke-CleanupRemoveThroughPlane $window $laneCleanupGamma 'commit'
            $afterCleanupCommit = Read-RouterServers
        }
        Add-ControlRow 'cleanup.requireConfirmation.accepted' `
            $(if ($droveCleanupOn -ne 'ok' -or -not $onCleanup) { 'unoracled' }
              elseif ($cleanupCommitted -ne 'confirmed:commit') { 'fail' }
              elseif ($null -eq $afterCleanupCommit) { 'unoracled' }
              elseif ($afterCleanupCommit -notcontains $laneCleanupGamma) { 'pass' } else { 'fail' }) `
            $(if ($droveCleanupOn -ne 'ok' -or -not $onCleanup) {
                "the setting or the board was not reachable, so acceptance was never driven from " +
                "the Cleanup board."
            } elseif ($cleanupCommitted -ne 'confirmed:commit') {
                "the confirmation could not be accepted through the plane: $cleanupCommitted"
            } elseif ($null -eq $afterCleanupCommit) {
                "the router stopped answering after the Cleanup removal was accepted."
            } elseif ($afterCleanupCommit -notcontains $laneCleanupGamma) {
                "pressing 'Remove permanently' on the Cleanup board removed $laneCleanupGamma from " +
                "the ROUTER - it now lists " +
                "$(if ($afterCleanupCommit.Count) { $afterCleanupCommit -join ', ' } else { 'nothing' }). " +
                "The board's button reaches the router at all, which is the half of DEF-302 no " +
                "dialog check could establish."
            } else {
                "the confirmation was accepted and the router still lists $laneCleanupGamma, so the " +
                "Cleanup board asks a question whose yes it does not act on."
            }) @('Remove selected…') $cleanupRecorder

        # -------------------------------------------------------------------- SILENCE
        # Setting OFF. The recorder has to be able to report the removal going through UNASKED, or
        # its yes above was never a reading of the setting: it would pass identically over a board
        # that always confirms and consults nothing.
        $droveCleanupOff = Set-ConfirmSetting $window $false
        $onCleanupAgain = $false
        if ($droveCleanupOff -eq 'ok') {
            $onCleanupAgain = Invoke-Destination 'Cleanup'
            Start-Sleep -Milliseconds 1800
        }
        $cleanupUnasked = 'not attempted'
        $afterCleanupSilence = $null
        if ($onCleanupAgain) {
            $cleanupUnasked = Invoke-CleanupRemoveThroughPlane $window $laneCleanupDelta 'decline'
            $afterCleanupSilence = Read-RouterServers
        }
        Add-ControlRow 'cleanup.requireConfirmation.silence' `
            $(if ($droveCleanupOff -ne 'ok' -or -not $onCleanupAgain) { 'unoracled' }
              elseif ($cleanupUnasked -ne 'no confirmation was raised') { 'fail' }
              elseif ($null -eq $afterCleanupSilence) { 'unoracled' }
              elseif ($afterCleanupSilence -notcontains $laneCleanupDelta) { 'pass' } else { 'fail' }) `
            $(if ($droveCleanupOff -ne 'ok' -or -not $onCleanupAgain) {
                "the setting could not be driven to Off ($droveCleanupOff), or the Cleanup board " +
                "was unreachable, so the unconfirmed path was never driven."
            } elseif ($cleanupUnasked -ne 'no confirmation was raised') {
                "with the setting Off, the Cleanup board's Remove selected still produced a " +
                "confirmation ($cleanupUnasked). The switch is not being read here: turning it off " +
                "removes no prompt, so the prompt above was this board's habit rather than the " +
                "setting."
            } elseif ($null -eq $afterCleanupSilence) {
                "the router stopped answering, so the unconfirmed Cleanup removal was never read back."
            } elseif ($afterCleanupSilence -notcontains $laneCleanupDelta) {
                "with the setting Off, Remove selected raised no confirmation at all and the router " +
                "no longer lists $laneCleanupDelta (now: " +
                "$(if ($afterCleanupSilence.Count) { $afterCleanupSilence -join ', ' } else { 'nothing' })). " +
                "The prompt above was THIS SETTING being obeyed by THIS board, rather than a dialog " +
                "the Cleanup board always shows."
            } else {
                "no confirmation was raised and the router still lists $laneCleanupDelta, so the " +
                "Cleanup board's button did nothing at all with the setting off."
            }) @('Remove selected…') $cleanupRecorder
    }

    # ------------------------------------------------------- DEF-084: the Discover store rows
    # WHAT THIS ARM ASSERTS, AND WHY IT IS NOT "the name is non-empty". Every row on this board
    # already published a non-empty name: "MCPRouter.Shell.Views.DiscoverRow", the item type's
    # ToString(), which is what a ListViewItem falls back to when nothing names the container. A
    # non-empty check would have passed on the defect. So the two properties asserted here are the
    # two that actually failed - that no row's name is the type name, and that no two rows in a
    # band share one.
    #
    # It is scoped to a band by automation id rather than sweeping every ListItem under the
    # window: the navigation items are ListItems too, and the previous census had to take
    # "whichever list item was not a navigation label", which is a description of how a row was
    # picked rather than of which row it was. Both bands are read, on their own rows.
    #
    # Where the registry search returns nothing - no network on this host - this arm reports
    # `unoracled`, never a pass. A check that could not run and a check that found nothing are the
    # same green otherwise. The structural rung is
    # MCPRouter.Shell.Tests/ViewAutomationSurfaceTests.
    if (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) {
        Add-ControlRow 'discover.rows' 'unoracled' ('the shell was not running, so no store row ' +
            'was read in either band.')
    } elseif (-not (Invoke-Destination 'Discover')) {
        Add-ControlRow 'discover.rows' 'unoracled' ('Discover could not be actuated, so its store ' +
            'rows were never reached in either band.')
    } else {
        # Both bands, not one. The recently-changed band and the most-used band render through the
        # same template and the same handler, and a check on one of them would leave the other's
        # rows unmeasured while reading as "the rows are named". A band the registry left empty is
        # reported `unoracled` on its own row rather than folded into the other band's pass.
        $typeName = 'MCPRouter.Shell.Views.DiscoverRow'
        $bandSpecs = @(
            [pscustomobject]@{ Row = 'discover.rows.recent'; Id = 'discover.band.recent' },
            [pscustomobject]@{ Row = 'discover.rows.used';   Id = 'discover.band.used'   })
        $rowEvidence = @()

        foreach ($spec in $bandSpecs) {
            $band = Wait-ById $window $spec.Id 15
            if ($null -eq $band) {
                Add-ControlRow $spec.Row 'fail' ("the Discover board publishes no element with the " +
                    "automation id '$($spec.Id)', so this band cannot be addressed and its rows " +
                    "cannot be scoped to it.")
                continue
            }

            $itemCond2 = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::ListItem)
            $rows = @()
            $until2 = (Get-Date).AddSeconds(45)
            while ((Get-Date) -lt $until2) {
                $rows = @($band.FindAll(
                    [System.Windows.Automation.TreeScope]::Descendants, $itemCond2))
                if ($rows.Count -gt 0) { break }
                Start-Sleep -Milliseconds 1500
            }

            if ($rows.Count -eq 0) {
                Add-ControlRow $spec.Row 'unoracled' ("the band '$($spec.Id)' published no row " +
                    'within 45 s - the registry search returned nothing for it on this host - so ' +
                    'no row name could be read. Not a finding about the rows: the harness cannot ' +
                    'reach them. Their declared surface is checked at the structural rung by ' +
                    'MCPRouter.Shell.Tests/ViewAutomationSurfaceTests.')
                continue
            }

            $rowNames = @()
            $rowIds   = @()
            foreach ($r in $rows) {
                $n = ''; $a = ''
                try { $n = $r.Current.Name } catch { }
                try { $a = $r.Current.AutomationId } catch { }
                $rowNames += $n
                $rowIds   += $a
            }

            $classNamed = @($rowNames | Where-Object { $_ -eq $typeName })
            $blank      = @($rowNames | Where-Object { [string]::IsNullOrWhiteSpace($_) })
            $distinct   = @($rowNames | Sort-Object -Unique)
            $idBlank    = @($rowIds | Where-Object { [string]::IsNullOrWhiteSpace($_) })
            $idDistinct = @($rowIds | Sort-Object -Unique)

            if ($classNamed.Count -gt 0) {
                Add-ControlRow $spec.Row 'fail' ("$($classNamed.Count) of $($rows.Count) row(s) " +
                    "publish the accessible name '$typeName' - the item type's ToString(). " +
                    'Narrator reads the class name aloud and every row answers to the same string.')
            } elseif ($blank.Count -gt 0) {
                Add-ControlRow $spec.Row 'fail' ("$($blank.Count) of $($rows.Count) row(s) publish " +
                    'an empty accessible name.')
            } elseif ($distinct.Count -ne $rows.Count) {
                Add-ControlRow $spec.Row 'fail' ("$($rows.Count) row(s) publish only " +
                    "$($distinct.Count) distinct accessible name(s), so an assertion by name " +
                    'addresses more than one row.')
            } elseif ($idBlank.Count -gt 0) {
                Add-ControlRow $spec.Row 'fail' ("$($idBlank.Count) of $($rows.Count) row(s) carry " +
                    'no automation id, so they have no stable address.')
            } elseif ($idDistinct.Count -ne $rows.Count) {
                Add-ControlRow $spec.Row 'fail' ("$($rows.Count) row(s) carry only " +
                    "$($idDistinct.Count) distinct automation id(s).")
            } else {
                Add-ControlRow $spec.Row 'pass' ("$($rows.Count) row(s) in '$($spec.Id)' each " +
                    'publish a distinct accessible name, none of them the type name, and a ' +
                    "distinct automation id. First three: " +
                    "$(($rowNames | Select-Object -First 3) -join ' | ')")
            }

            $rowEvidence += [pscustomobject]@{
                band  = $spec.Id
                rows  = $rows.Count
                names = $rowNames
                ids   = $rowIds
            }
        }

        # The names as read, committed beside the verdict: a grader can see what the tree actually
        # said rather than only what this arm concluded about it.
        @{
            schema = 'win-shell.discover-rows/1'
            bands  = $rowEvidence
            readAt = (Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json -Depth 5 |
            Set-Content -Path (Join-Path $Out 'discover-row-names.json') -Encoding UTF8
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

    # ------------------------------------------------------ DEF-089: the navigation pane's name
    # The cheapest read in this file, and it is here rather than in the destination sweep because
    # the sweep grades what selecting an item DOES. Whether the container those items live in says
    # anything a person could say out loud is a different claim, and the sweep passed all ten
    # destinations while the pane holding them published the empty string.
    if (-not (Get-Process -Id $script:ShellProcessId -ErrorAction SilentlyContinue)) {
        Add-ControlRow 'shell.navigationPane' 'unoracled' ('the shell was not running when the ' +
            'pane was to be read, so its accessible name was never fetched.')
    } else {
        $nav = Wait-ById $window 'Nav' 10
        if ($null -eq $nav) {
            Add-ControlRow 'shell.navigationPane' 'fail' ('no element on the automation plane ' +
                'carries the automation id "Nav", so the navigation pane is unaddressable.')
        } else {
            $navName = ''
            try { $navName = $nav.Current.Name } catch { }
            if ([string]::IsNullOrWhiteSpace($navName)) {
                Add-ControlRow 'shell.navigationPane' 'fail' ('the navigation pane publishes an ' +
                    'empty accessible name. Its ten items are named and the container holding ' +
                    'them is not, so a screen reader announces the destinations without ever ' +
                    'saying what they are a list of.')
            } else {
                Add-ControlRow 'shell.navigationPane' 'pass' ("the navigation pane publishes the " +
                    "accessible name '$navName'.")
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
