<#
.SYNOPSIS
    WIN22 effect witness: the toast activator registration, written by the notification platform
    and read back out of the Windows registry.

.DESCRIPTION
    WHY THIS LANE EXISTS. DEF-072 found WIN22's "Action Center toast notifications" to be a payload
    record, a builder, and a test asserting the builder built the record. `AppNotificationManager`
    and `ToastNotificationManager` had zero hits in product source, so no toast could reach the
    Action Center, under a ledger row reading "621 tests green, Action Center toast notifications".

    WHAT AN UNPACKAGED WIN32 APP HAS TO DO, and what this lane can and cannot see:

      the AppUserModelID     claimed by the app before registration, so the notification is
                             attributed to a stable identity rather than one derived from the
                             executable's path. WITNESSED - it is the key the registration lands
                             under, and this lane finds the key by name.
      the COM activator      `AppNotificationManager.Register()` writes a CustomActivator CLSID
                             under that AUMID and a LocalServer32 for the CLSID pointing at the
                             executable. It is what lets Windows re-launch this application when
                             somebody presses a toast button an hour after the process exited, and
                             without it the toast appears and pressing it does nothing - the
                             failure that looks most like success. WITNESSED, and this is the arm
                             that carries the item.
      the toast itself       NOT WITNESSED HERE, and witnessed next door. This lane once said the
                             Action Center could not be read at all without a packaged application
                             holding the userNotificationListener capability. That was measured on
                             2026-09-03 and is false on this host: an unpackaged process with no
                             package identity gets Allowed from RequestAccessAsync and enumerates
                             the real toasts. scripts/windows/win22-toast-effect-witness.ps1 is the
                             lane that does it, and it found this lane's own toasts from the day
                             before. DEF-082 keeps only what is still true - that nothing here can
                             press a notification button.

    THE RECORDER IS NOT THE WRITER. The registration is written by the Windows App SDK's
    notification platform, inside the shell process, through an API this repository does not
    implement. It is read here out of HKCU by PowerShell's registry provider, in a different
    process. Nothing in this repository sits between the two.

    THE WRITER'S OWN ACCOUNT IS COLLECTED AND IS NOT THE VERDICT. `--toast-probe` makes the shell
    write toast-probe.json saying whether the platform accepted a Show. That file is carried in the
    evidence as `writerSelfReport` and is graded by nothing: a process reporting that it raised a
    notification is precisely the shape of claim DEF-072 was about.

.PARAMETER ProveRed
    Arming. Points every registry read at an AUMID nothing registers, and requires the EFFECT arms
    to BREAK while BASELINE still holds. Without it the reads could be finding any registration at
    all - the registry is full of them - and this proves they are keyed on this application's
    identity.

.NOTES
    Exit 0 pass, 1 fail, 3 NO VERDICT.
#>
[CmdletBinding()]
param(
    [string] $Out = 'planning/evidence/WIN22/run',
    [string] $ExePath = '',
    [int]    $TimeoutSeconds = 300,
    [switch] $ProveRed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutDir = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $RepoRoot $Out }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$ShippedAumid = 'Fledgeling.MCPRouter.Shell'
# The arming id. Deliberately a name no code registers, so an EFFECT arm that still held would be
# reporting on some other application's registration rather than on this one's.
$Aumid = if ($ProveRed) { $ShippedAumid + '.NOTREGISTERED' } else { $ShippedAumid }

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
    param([int] $Code, [string] $Verdict, [string] $Reason, $Writer = $null)
    $doc = [ordered]@{
        lane        = 'win22-toast-witness'
        rung        = 'effect-witness'
        subject     = 'MCPRouter.Shell.Notifications.ToastNotifier'
        writer      = 'AppNotificationManager.Register(), inside the shell process'
        recorder    = 'the Windows registry under HKCU, read by PowerShell in a different process'
        recorderIsNotWriter = $true
        appUserModelId = $Aumid
        arming      = [bool] $ProveRed
        verdict     = $Verdict
        reason      = $Reason
        arms        = $Arms
        armsHeld    = @($Arms | Where-Object { $_.held }).Count
        armsTotal   = $Arms.Count
        writerSelfReport = $Writer
        writerSelfReportIsNotEvidence =
            'the shell process reporting that it raised a toast. Graded by nothing here: a process ' +
            'reporting its own effect is the shape of claim DEF-072 was about. It is carried so a ' +
            'reader can see the two accounts side by side.'
        notMeasured = @(
            'that a toast is drawn in the Action Center - scripts/windows/win22-toast-effect-witness.ps1 measures that, from a separate unpackaged process reading UserNotificationListener; this lane measures the registration only',
            'that pressing a toast button re-activates the process through the registered activator - nothing here can press one'
        )
        notes       = $Notes
        host        = $env:COMPUTERNAME
        psVersion   = $PSVersionTable.PSVersion.ToString()
    }
    $path = Join-Path $OutDir $(if ($ProveRed) { 'witness-armed.json' } else { 'witness.json' })
    [System.IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 6),
        (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ("win22 witness: {0} - {1}" -f $Verdict, $Reason)
    Write-Host ("               wrote {0}" -f $path)
    exit $Code
}

function Read-Registration {
    <#
      The independent read. Everything here comes out of HKCU through the registry provider; not
      one line of it calls into the assembly under test or into the notification platform.
    #>
    param([string] $Id)

    $key = "HKCU:\Software\Classes\AppUserModelId\$Id"
    if (-not (Test-Path $key)) { return $null }

    $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    $clsid = $null
    if ($null -ne $props -and $props.PSObject.Properties.Name -contains 'CustomActivator') {
        $clsid = [string] $props.CustomActivator
    }

    $server = $null
    if ($clsid) {
        $serverKey = "HKCU:\Software\Classes\CLSID\$clsid\LocalServer32"
        if (Test-Path $serverKey) {
            $server = (Get-ItemProperty -Path $serverKey -ErrorAction SilentlyContinue).'(default)'
            if (-not $server) {
                $server = (Get-Item $serverKey).GetValue('')
            }
        }
    }

    return [pscustomobject]@{
        key             = $key
        customActivator = $clsid
        localServer32   = $server
    }
}

# --------------------------------------------------------------------------- the writer
if (-not $ExePath) {
    # bin\Debug, not bin\x64\Debug. MEASURED 2026-09-03: this lane defaulted to the x64 path, which
    # is what `MSBuild -p:Platform=x64` writes and NOT what scripts/windows/build-shell.ps1 writes,
    # so a freshly and correctly built tree gave this lane NO VERDICT and told the reader to go and
    # build a shell that was already there. It is the same split that let a twelve-hour-old binary
    # fabricate twelve control failures for the UIA lane, arriving here as the harmless-looking half:
    # the lane refuses to speak instead of speaking falsely. DEF-321.
    $ExePath = Join-Path $RepoRoot 'app\windows\MCPRouter.Shell\bin\Debug\net8.0-windows10.0.19041.0\win-x64\MCPRouter.Shell.exe'
}
if (-not (Test-Path $ExePath)) {
    # The -f binds to the whole parenthesised expression rather than to the second string alone.
    # Without the brackets this message printed a literal {0} where the path should be, which is a
    # NO VERDICT that does not say what is missing.
    Write-Verdict 3 'NO VERDICT' (("the shell binary is not on disk at {0}. Build it with " +
        'scripts/windows/build-shell.ps1 - dotnet build cannot build WinUI here - and run this again.') -f $ExePath)
}

Write-Host ''
Write-Host  'win22 witness: the toast activator registration'
Write-Host ("               AUMID    {0}{1}" -f $Aumid, $(if ($ProveRed) { '   (ARMING - nothing registers this)' } else { '' }))
Write-Host  '               writer   AppNotificationManager.Register(), inside the shell'
Write-Host  '               recorder HKCU, read by the registry provider in this process'
Write-Host ''

# --------------------------------------------------------------------------- BASELINE
$before = Read-Registration $Aumid
if ($null -ne $before) {
    # Removed rather than failed, and recorded rather than tidied away silently. A registration
    # left by an earlier run of the product makes every EFFECT arm below pass over a launch that
    # registered nothing - which is the same shape as this lane's BASELINE arm existing at all.
    $Notes += ("a registration for '{0}' existed before this run and was removed so the baseline " +
        'could be taken. It is written again by the launch below.') -f $Aumid
    Remove-Item -Path $before.key -Recurse -Force -ErrorAction SilentlyContinue
    $before = Read-Registration $Aumid
}
Add-Arm 'BASELINE' 'no registration under this AUMID before the shell runs' ($null -eq $before) `
    $(if ($null -eq $before) { 'the arms below measure this launch' }
      else { 'a registration survived removal; every arm below would be about it' })

# --------------------------------------------------------------------------- the launch
# The shell needs a drawn window: from session 0 a WinUI process dies at 0xC000027B before the App
# constructor, so the registration would never be written and this lane would report a product
# defect where there is a station problem. Same bridge run-shell-lane.ps1 uses.
Add-Type -Namespace Win22Run -Name Native -MemberDefinition @'
    [DllImport("user32.dll")] public static extern System.IntPtr GetProcessWindowStation();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetUserObjectInformationW(System.IntPtr h, int index,
        System.Text.StringBuilder buffer, int length, out int needed);
'@
$sb = New-Object System.Text.StringBuilder 256
$needed = 0
[void][Win22Run.Native]::GetUserObjectInformationW(
    [Win22Run.Native]::GetProcessWindowStation(), 2, $sb, 256, [ref] $needed)
$station = $sb.ToString()

$probeJson = Join-Path $OutDir 'toast-probe.json'
Remove-Item $probeJson -ErrorAction SilentlyContinue
$taskName = 'MCPRouter-WIN22-ToastWitness'

if ($station -eq 'WinSta0') {
    Write-Host "  station WinSta0; launching the shell directly"
    Start-Process -FilePath $ExePath -ArgumentList @('--toast-probe', $OutDir) | Out-Null
} else {
    Write-Host ("  station '{0}'; scheduling the shell into the interactive session" -f $station)
    $command = "`"$ExePath`" --toast-probe `"$OutDir`""
    & schtasks.exe /Create /TN $taskName /TR $command /SC ONCE /ST 00:00 /IT /F | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Verdict 3 'NO VERDICT' "could not register the interactive task (schtasks exit $LASTEXITCODE)."
    }
    # schtasks /Run prints "Attempted to run" either way, so its exit code is not evidence. The
    # probe file on disk is the only signal that the shell got as far as running.
    & schtasks.exe /Run /TN $taskName | Out-Null
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline -and -not (Test-Path $probeJson)) {
    Start-Sleep -Seconds 2
}

$writer = $null
if (Test-Path $probeJson) {
    $writer = Get-Content $probeJson -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $Notes += ("the shell wrote no toast-probe.json within {0}s. The registry arms below still " +
        'run, because the registration happens before the probe and might be there anyway - but ' +
        'read them knowing the launch is not confirmed.') -f $TimeoutSeconds
}

$after = Read-Registration $Aumid

# The shell opens a window and stays open; nothing else here closes it.
Get-Process -Name 'MCPRouter.Shell' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
if ($station -ne 'WinSta0') {
    & schtasks.exe /Delete /TN $taskName /F | Out-Null
}

# --------------------------------------------------------------------------- EFFECT
Add-Arm 'EFFECT.aumid' 'the notification platform wrote a key under this AUMID' ($null -ne $after) `
    $(if ($null -ne $after) { $after.key } else { "no key at HKCU:\Software\Classes\AppUserModelId\$Aumid" })

$clsid = if ($null -ne $after) { $after.customActivator } else { $null }
Add-Arm 'EFFECT.activator' 'that key names a CustomActivator CLSID' `
    (-not [string]::IsNullOrWhiteSpace($clsid)) `
    $(if ($clsid) { $clsid } else { 'no CustomActivator value - a toast under this identity could appear and activate nothing' })

$server = if ($null -ne $after) { $after.localServer32 } else { $null }
$serverPointsAtShell = (-not [string]::IsNullOrWhiteSpace($server)) -and
                       ($server -like '*MCPRouter.Shell.exe*')
Add-Arm 'EFFECT.localserver' 'the CLSID has a LocalServer32 naming this executable' $serverPointsAtShell `
    $(if ($server) { $server } else { 'no LocalServer32 for that CLSID - Windows would have nothing to launch' })

if ($null -ne $writer) {
    Write-Host ''
    Write-Host ("  writer's own account (graded by nothing): showAccepted={0}" -f $writer.showAccepted)
}

# --------------------------------------------------------------------------- the verdict
$broke = @($Arms | Where-Object { -not $_.held })
$brokeIds = ($broke | ForEach-Object { $_.id }) -join ', '

if ($ProveRed) {
    $baselineHeld = @($Arms | Where-Object { $_.id -eq 'BASELINE' -and $_.held }).Count -eq 1
    $allEffectBroke = @($broke | Where-Object { $_.id -like 'EFFECT.*' }).Count -eq 3
    if ($baselineHeld -and $allEffectBroke) {
        Write-Verdict 0 'PASS (armed)' ('pointed at an AUMID nothing registers, every EFFECT arm ' +
            'broke and BASELINE held. So the registry reads are keyed on this application''s ' +
            'identity and are not finding whatever registration happens to be nearby.') $writer
    }
    Write-Verdict 1 'FAIL (arming)' ("expected BASELINE to hold and all three EFFECT arms to break; broke: {0}" -f
        $(if ($brokeIds) { $brokeIds } else { 'nothing - the reads cannot fail' })) $writer
}

if ($broke.Count -gt 0) {
    Write-Verdict 1 'FAIL' ("{0} of {1} arm(s) broke: {2}" -f $broke.Count, $Arms.Count, $brokeIds) $writer
}
$reason = ('all {0} arm(s) held: the shell claimed its AppUserModelID and the notification ' +
    'platform wrote a COM activator under it whose LocalServer32 names this executable, read out ' +
    'of the registry by a process that did not write it. The toast itself is NOT witnessed here ' +
    'and notMeasured[] says so.') -f $Arms.Count
Write-Verdict 0 'PASS' $reason $writer
