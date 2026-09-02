<#
.SYNOPSIS
    WIN22 effect witness, second half: the toast itself, read out of the Action Center by a process
    that did not raise it.

.DESCRIPTION
    WHY THIS LANE EXISTS, AND WHY ITS EXISTENCE IS THE FINDING. scripts/windows/win22-toast-witness.ps1
    witnesses the REGISTRATION - the AppUserModelID and the COM activator the notification platform
    writes into HKCU - and says in its own notMeasured[] that the toast itself is not witnessed.
    DEF-082 recorded why: enumerating the Action Center needs
    Windows.UI.Notifications.Management.UserNotificationListener, whose userNotificationListener
    capability is only grantable to a PACKAGED application, and MCPRouter.Shell is
    WindowsPackageType=None. The row named WIN19's MSIX as the thing that would unblock it.

    THAT BLOCKER WAS WRONG, AND IT WAS WRONG BEFORE WIN19 LANDED. Measured 2026-09-03 on this host,
    from an ordinary unpackaged Win32 console process with no package identity whatever -
    Package.Current throws InvalidOperationException, which this lane asserts rather than assumes:

      UserNotificationListener.Current              resolves
      RequestAccessAsync()                          returns Allowed, with no consent prompt
      GetNotificationsAsync(NotificationKinds.Toast) returns the toasts that are really there

    and among them, on the first run, were three toasts raised by MCPRouter.Shell's own
    win22-toast-witness runs the day before, carrying the exact strings its payload builder writes.
    No MSIX, no capability, no packaged identity. So the Action Center has been readable from this
    tree the whole time and nobody had tried.

    WHAT IS STILL NOT AVAILABLE UNPACKAGED, because it changes what this lane can assert: every
    member of UserNotification.AppInfo - AppUserModelId, PackageFamilyName, DisplayInfo - throws
    NotImplementedException (0x80004001) for a caller with no package identity. The listener can say
    what a notification SAYS and when it arrived; it cannot say who raised it. So attribution here
    rests on the payload TEXT, which the product owns, inside a time window this run opened. That is
    weaker than a publisher identity and it is said out loud rather than left for a reader to infer
    from a green.

    THE RECORDER IS NOT THE WRITER, and here they are not even the same process. The toast is raised
    by MCPRouter.Shell through the Windows App SDK's notification platform. It is read back by
    app/windows/MCPRouter.Witness.ActionCenter, a separate executable that shares no code with the
    shell and cannot raise a notification at all. The shell's own toast-probe.json - "the platform
    accepted a Show" - is carried in the evidence as the writer's self-report and is graded by
    nothing, because a process reporting its own effect is the shape DEF-072 was about.

    THE PRESENCE CONTROL. A recorder that answered "yes, here is a toast" unconditionally would pass
    every assertion above. So the matched notification is REMOVED through the listener and the
    Action Center is read a third time, and the recorder is required to say no.

.PARAMETER ProveRed
    Arming, and it plants the defect this lane is most at risk of: the shell is never launched, so
    nothing raises a toast, and EXACTLY EFFECT.toast must break. This is not a hypothetical plant -
    the Action Center on this machine already held three toasts with identical text from earlier
    runs, so a lane that matched on text alone would have found one and passed while the product did
    nothing at all. The arming run is what shows the time window is load-bearing.

.NOTES
    ASCII only, and written to parse under Windows PowerShell 5.1, because
    scripts/windows/ps-parse-gate.py holds every tracked .ps1 to that.

    Exit 0 pass, 1 fail, 3 NO VERDICT.
#>
[CmdletBinding()]
param(
    [string] $Out = 'planning/evidence/WIN22/run',
    [string] $ExePath = '',
    [int]    $TimeoutSeconds = 120,
    [switch] $ProveRed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutDir = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $RepoRoot $Out }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

# The strings the product's own payload builder writes. They are the attribution, since the listener
# cannot report a publisher, so they are named here rather than pattern-matched loosely: a change to
# NotificationPresentation that stopped producing them should redden this lane rather than quietly
# widen what it accepts.
$ExpectedTitle = 'postgres-mcp is waiting for review'
$ExpectedSource = 'win22-toast-witness'

$Arms = @()
$Notes = @()

function Add-Arm {
    param([string] $Id, [string] $What, [bool] $Held, [string] $Detail)
    $script:Arms += [pscustomobject]@{ id = $Id; what = $What; held = $Held; detail = $Detail }
    $mark = if ($Held) { 'HELD' } else { 'BROKE' }
    Write-Host ("  {0,-16} {1,-6} {2}" -f $Id, $mark, $What)
    if ($Detail) { Write-Host ("                          {0}" -f $Detail) }
}

function Write-Verdict {
    param([int] $Code, [string] $Verdict, [string] $Reason, $Writer = $null, $Listener = $null)
    $doc = [ordered]@{
        lane        = 'win22-toast-effect-witness'
        rung        = 'effect-witness'
        subject     = 'the toast MCPRouter.Shell raises, as it exists in the Action Center'
        writer      = 'MCPRouter.Shell, through the Windows App SDK notification platform'
        recorder    = 'app/windows/MCPRouter.Witness.ActionCenter - a separate unpackaged process reading UserNotificationListener'
        recorderIsNotWriter = $true
        arming      = [bool] $ProveRed
        verdict     = $Verdict
        reason      = $Reason
        arms        = $Arms
        armsHeld    = @($Arms | Where-Object { $_.held }).Count
        armsTotal   = $Arms.Count
        listenerReport = $Listener
        writerSelfReport = $Writer
        writerSelfReportIsNotEvidence =
            'the shell process reporting that the platform accepted a Show. Graded by nothing here: ' +
            'a process reporting its own effect is the shape DEF-072 was about. It is carried so a ' +
            'reader can see the two accounts side by side.'
        correctsDefect = ('DEF-082 said the Action Center could not be read without a packaged app ' +
            'holding the userNotificationListener capability. Measured on this host, an unpackaged ' +
            'process with no package identity reads it and is granted access without a prompt. The ' +
            'LISTENER.unpackaged arm below asserts that rather than restating it.')
        notMeasured = @(
            'WHO raised the toast - UserNotification.AppInfo throws NotImplementedException for an unpackaged caller, so attribution here is the payload text inside a time window this run opened, and not a publisher identity',
            'that pressing a toast button re-activates the process through the registered activator - nothing here can press one, and DEF-082 keeps that half'
        )
        notes       = $Notes
        host        = $env:COMPUTERNAME
        psVersion   = $PSVersionTable.PSVersion.ToString()
    }
    $path = Join-Path $OutDir $(if ($ProveRed) { 'toast-effect-armed.json' } else { 'toast-effect.json' })
    [System.IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 8),
        (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ("win22 toast effect witness: {0} - {1}" -f $Verdict, $Reason)
    Write-Host ("                            wrote {0}" -f $path)
    exit $Code
}

# --------------------------------------------------------------------------- the recorder
$ListenerProj = Join-Path $RepoRoot 'app\windows\MCPRouter.Witness.ActionCenter\MCPRouter.Witness.ActionCenter.csproj'
Write-Host 'win22 toast effect witness: building the Action Center reader'
$build = & dotnet build $ListenerProj -c Debug -v q --nologo 2>&1
if ($LASTEXITCODE -ne 0) {
    $Notes += ($build | Out-String)
    Write-Verdict 3 'NO VERDICT' 'the Action Center reader did not build, so there was no recorder.'
}
$ListenerExe = Join-Path $RepoRoot ('app\windows\MCPRouter.Witness.ActionCenter\bin\Debug\' +
    'net8.0-windows10.0.19041.0\win-x64\mcprouter-action-center-witness.exe')
if (-not (Test-Path $ListenerExe)) {
    Write-Verdict 3 'NO VERDICT' ("the reader build reported success and {0} is not on disk." -f $ListenerExe)
}

$ScratchDir = Join-Path $OutDir 'action-center'
if (-not (Test-Path $ScratchDir)) { New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null }

function Read-ActionCenter {
    param([string] $Label, [uint32] $RemoveId = 0)
    $file = Join-Path $ScratchDir ("{0}.json" -f $Label)
    Remove-Item $file -Force -ErrorAction SilentlyContinue
    if ($RemoveId -ne 0) { & $ListenerExe --out $file --remove $RemoveId 2>&1 | Out-Null }
    else { & $ListenerExe --out $file 2>&1 | Out-Null }
    if (-not (Test-Path $file)) { return $null }
    return (Get-Content $file -Raw | ConvertFrom-Json)
}

function ConvertTo-Utc {
    <#
      MEASURED, AND IT COST THIS LANE A FALSE RED. ConvertFrom-Json parses a Z-suffixed string into
      a [datetime] with Kind=Utc, so `[datetime]::TryParse($value, [ref] $out)` coerces that object
      back to a string FIRST - dropping the kind - and the result is an Unspecified local time.
      .ToUniversalTime() then adds this machine's offset a second time, and a toast raised ten
      seconds ago reads as ten hours old and falls outside the window. The lane reported the product
      for it.

      It failed closed rather than open, which is the right direction to be wrong in, but the fix is
      to never let the value become a string: a [datetime] is used as it stands, and only a genuine
      string is parsed, with AssumeUniversal because the field is named createdUtc and the tool that
      writes it writes UTC.
    #>
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        $moment = [datetime] $Value
        if ($moment.Kind -eq [System.DateTimeKind]::Unspecified) {
            return [datetime]::SpecifyKind($moment, [System.DateTimeKind]::Utc)
        }
        return $moment.ToUniversalTime()
    }
    $parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
              [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse([string] $Value, [System.Globalization.CultureInfo]::InvariantCulture,
                             $styles, [ref] $parsed)) {
        return $parsed
    }
    return $null
}

function Find-ProbeToast {
    param($Report, [datetime] $Since)
    if ($null -eq $Report -or -not $Report.ok) { return $null }
    foreach ($notification in @($Report.notifications)) {
        $text = (@($notification.text) -join ' | ')
        if ($text -notlike ("*{0}*" -f $ExpectedTitle)) { continue }
        if ($text -notlike ("*{0}*" -f $ExpectedSource)) { continue }
        $created = ConvertTo-Utc $notification.createdUtc
        if ($null -eq $created) { continue }
        if ($created -lt $Since) { continue }
        return $notification
    }
    return $null
}

# --------------------------------------------------------------------------- the writer
if (-not $ExePath) {
    $ExePath = Join-Path $RepoRoot ('app\windows\MCPRouter.Shell\bin\Debug\' +
        'net8.0-windows10.0.19041.0\win-x64\MCPRouter.Shell.exe')
}
if (-not (Test-Path $ExePath)) {
    Write-Verdict 3 'NO VERDICT' ("the shell is not built at {0}. Run scripts/windows/build-shell.ps1. " -f $ExePath +
        'A missing binary is a build job, never a finished gap.')
}
$Notes += ("shell binary {0}, written {1}" -f $ExePath, (Get-Item $ExePath).LastWriteTimeUtc.ToString('o'))

Write-Host ''
Write-Host  'win22 toast effect witness: the toast itself, in the Action Center'
Write-Host ("                            writer   {0}" -f $ExePath)
Write-Host ("                            recorder {0}" -f $ListenerExe)
if ($ProveRed) {
    Write-Host '                            ARMING: the shell is never launched, so nothing raises a toast'
    $Notes += ('ARMING RUN: the shell is not launched at all. EXACTLY EFFECT.toast is required to ' +
        'break. This machine already holds toasts with identical text from earlier runs, so a lane ' +
        'matching on text alone would pass here while the product did nothing.')
}
Write-Host ''

# --------------------------------------------------------------------------- BASELINE
$since = (Get-Date).ToUniversalTime()
$baseline = Read-ActionCenter 'baseline'
if ($null -eq $baseline) {
    Write-Verdict 3 'NO VERDICT' 'the Action Center reader wrote no report, so nothing was read.'
}
if (-not $baseline.ok) {
    $Notes += ('listener failure: ' + ($baseline | ConvertTo-Json -Depth 4))
    Write-Verdict 3 'NO VERDICT' ('the listener could not enumerate the Action Center on this host. ' +
        'That is a corrected blocker rather than a product failure, and it belongs on DEF-082 with ' +
        'the error, which is in notes[].')
}

# The arm that reddens DEF-082's stated blocker. It asserts BOTH halves: this process has no package
# identity, AND the listener answered anyway. Either half alone would be a weaker claim - a packaged
# process reading the Action Center proves only what the row already assumed.
Add-Arm 'LISTENER.unpackaged' 'an unpackaged process with no package identity can read the Action Center' `
    ((-not $baseline.packaged) -and ($baseline.access -eq 'Allowed')) `
    ("packaged={0}, RequestAccessAsync={1}, toasts visible={2}" -f
        $baseline.packaged, $baseline.access, $baseline.count)

$stale = Find-ProbeToast $baseline $since
Add-Arm 'BASELINE' 'no toast carrying this payload has arrived since this run opened its window' `
    ($null -eq $stale) `
    $(if ($null -eq $stale) { ("{0} toast(s) present, none of them this run's" -f $baseline.count) }
      else { 'a matching toast predates the raise, so every match below could be that one' })
if ($null -ne $stale) {
    Write-Verdict 1 'FAIL' 'the time window was already dirty, so no match below would be attributable.'
}

# --------------------------------------------------------------------------- raise it
$probeJson = Join-Path $OutDir 'toast-probe.json'
$writerReport = $null
# The shell needs a drawn window: from a station that is not WinSta0 a WinUI process dies at
# 0xC000027B before the App constructor, so it would raise nothing and this lane would report a
# product defect where there is a station problem. MEASURED on the first run of this lane, which is
# why the bridge is here: launched with Start-Process from this session the shell wrote no
# toast-probe.json in 120 seconds and no toast reached the Action Center. Same bridge
# win22-toast-witness.ps1 and run-shell-lane.ps1 use.
$taskName = 'MCPRouter-WIN22-ToastEffectWitness'
$station = ''
if (-not $ProveRed) {
    Add-Type -Namespace Win22Effect -Name Native -MemberDefinition @'
    [DllImport("user32.dll")] public static extern System.IntPtr GetProcessWindowStation();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetUserObjectInformationW(System.IntPtr h, int index,
        System.Text.StringBuilder buffer, int length, out int needed);
'@
    $sb = New-Object System.Text.StringBuilder 256
    $needed = 0
    [void][Win22Effect.Native]::GetUserObjectInformationW(
        [Win22Effect.Native]::GetProcessWindowStation(), 2, $sb, 256, [ref] $needed)
    $station = $sb.ToString()
    $Notes += ("window station '{0}'" -f $station)

    Remove-Item $probeJson -Force -ErrorAction SilentlyContinue
    if ($station -eq 'WinSta0') {
        Write-Host '  station WinSta0; launching the shell directly'
        Start-Process -FilePath $ExePath -ArgumentList @('--toast-probe', $OutDir) | Out-Null
    }
    else {
        Write-Host ("  station '{0}'; scheduling the shell into the interactive session" -f $station)
        $command = ('"{0}" --toast-probe "{1}"' -f $ExePath, $OutDir)
        & schtasks.exe /Create /TN $taskName /TR $command /SC ONCE /ST 00:00 /IT /F 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Verdict 3 'NO VERDICT' ("could not register the interactive task (schtasks exit {0}), " -f $LASTEXITCODE +
                'so the shell was never given a station on which it could draw.')
        }
        # schtasks /Run prints "Attempted to run" either way, so its exit code is not evidence. The
        # probe file on disk is the only signal that the shell got as far as running.
        & schtasks.exe /Run /TN $taskName 2>&1 | Out-Null
    }

    for ($waited = 0; $waited -lt $TimeoutSeconds; $waited += 2) {
        Start-Sleep -Seconds 2
        if (Test-Path $probeJson) { break }
    }
    if (Test-Path $probeJson) {
        $writerReport = (Get-Content $probeJson -Raw | ConvertFrom-Json)
    }
    else {
        $Notes += ("the shell wrote no toast-probe.json within {0}s. The arms below still stand: " -f $TimeoutSeconds +
            'what is graded is what reached the Action Center, not what the shell said about it.')
    }
    # The platform takes a moment to place the notification, and this lane must not read the Action
    # Center before it is there and then report the product for it.
    Start-Sleep -Seconds 5
    Get-Process -Name 'MCPRouter.Shell' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    if ($station -ne 'WinSta0') { & schtasks.exe /Delete /TN $taskName /F 2>&1 | Out-Null }
}

# --------------------------------------------------------------------------- EFFECT
$effect = Read-ActionCenter 'effect'
$found = Find-ProbeToast $effect $since
Add-Arm 'EFFECT.toast' 'the Action Center holds a toast carrying this product''s payload, raised inside this run''s window' `
    ($null -ne $found) `
    $(if ($null -ne $found) { ("id={0} created={1} text={2}" -f $found.id, $found.createdUtc, (@($found.text) -join ' | ')) }
      else { ("no matching toast among {0}" -f $(if ($null -ne $effect) { $effect.count } else { 'no report' })) })

$listenerReport = $effect
if ($null -ne $found) {
    # -------------------------------------------------------------- SILENCE
    $silence = Read-ActionCenter 'silence' ([uint32] $found.id)
    $stillThere = $null
    if ($null -ne $silence -and $silence.ok) {
        $stillThere = @($silence.notifications | Where-Object { $_.id -eq $found.id })
    }
    Add-Arm 'SILENCE' 'the recorder reports the toast gone once it is removed' `
        (($null -ne $stillThere) -and ($stillThere.Count -eq 0)) `
        $(if (($null -ne $stillThere) -and ($stillThere.Count -eq 0))
          { 'the recorder can say no about this notification, so its yes above was a reading' }
          else { 'the recorder still reports it, so its earlier yes proves nothing' })
    $listenerReport = $silence
}

$broke = @($Arms | Where-Object { -not $_.held })

if ($ProveRed) {
    $ids = ($broke | ForEach-Object { $_.id }) -join ', '
    if ($ids -eq 'EFFECT.toast') {
        Write-Verdict 0 'PASS (armed)' ('the planted defect - nothing raised a toast - broke ' +
            'EFFECT.toast and nothing else, with toasts of identical text still sitting in the ' +
            'Action Center from earlier runs. The match is bounded by this run''s window.') `
            $writerReport $listenerReport
    }
    Write-Verdict 1 'FAIL (arming)' ("expected exactly EFFECT.toast to break; broke: {0}" -f
        $(if ($ids) { $ids } else { 'nothing - the assertion cannot fail' })) $writerReport $listenerReport
}

if ($broke.Count -gt 0) {
    Write-Verdict 1 'FAIL' ("{0} of {1} arm(s) broke: {2}" -f $broke.Count, $Arms.Count,
        (($broke | ForEach-Object { $_.id }) -join ', ')) $writerReport $listenerReport
}
Write-Verdict 0 'PASS' (('all {0} arm(s) held: a toast the shell raised was found in the Action ' +
    'Center by a separate unpackaged process that cannot raise one, inside the window this run ' +
    'opened, and was gone again once removed. Who raised it is still not readable - AppInfo throws ' +
    'for an unpackaged caller - and pressing a toast button is still unmeasured.') -f $Arms.Count) `
    $writerReport $listenerReport
