<#
.SYNOPSIS
    WIN19 effect witness: an MSIX that is actually built, actually installed, and actually
    uninstalled - with Windows itself as the recorder at every step.

.DESCRIPTION
    WHY THIS LANE EXISTS. DEF-073 recorded that WIN19's "packaging and distribution" shipped no
    package. A repository-wide search for *.appxmanifest, any winget manifest and any *.wxs returned
    nothing, and the only MSIX and winget strings anywhere were WIN19's own three model files - 67
    added lines under a ledger row reading "winget and MSIX distribution channel contract,
    SmartScreen disclosure, clean uninstall rules". There was no channel, no package, and nothing to
    uninstall.

    FOUR THINGS ARE MEASURED, and each has a recorder that is not the thing that wrote it:

      PACK       MakeAppx.exe builds a .msix from app/windows/packaging. The recorder is .NET's
                 ZipArchive reading the OPC container - not MakeAppx, and not this script's idea of
                 what it asked for. The identity is parsed OUT OF THE PACKED ARTIFACT and compared
                 against PackagingPresentation's own constants, so a manifest that drifts from the
                 identity the application states reddens here.
      WINGET     `winget validate` on the three YAML files. That is the winget client applying a
                 schema this repository does not own, through a parser it does not implement.
      INSTALL    Add-AppxPackage, then Get-AppxPackage as the recorder. This is the arm that turns
                 "a package exists" into "Windows accepted it": a manifest can pack cleanly and be
                 refused at deployment for a capability, an architecture or a signature, and every
                 static check in the world passes right up to that point.
      UNINSTALL  Remove-AppxPackage, then Get-AppxPackage must report absence - AND the
                 configuration directory PackagingPresentation.UninstallGuidance promises to
                 preserve must still be there. That second half is the whole of "clean uninstall
                 rules" as a measurable claim rather than a sentence: it is a promise about what
                 SURVIVES, and only an uninstall that actually ran can settle it.

    WHAT THIS MUTATES, AND PUTS BACK. A self-signed certificate is created and placed in
    LocalMachine\TrustedPeople so an unsigned developer package can be deployed at all, and it is
    removed in a finally block whether the lane passes, fails or throws. The package is removed the
    same way. A lane that leaves a trusted certificate behind has changed what this machine will
    install, which is not a side effect a test gets to have.

    WHAT IS NOT MEASURED, said here rather than left to a green: nothing publishes the package
    anywhere, so the InstallerUrl in the winget manifest is a deliberate placeholder and this lane
    asserts it is one. `winget install` has never been run against a real release, because there is
    no release. DEF-083 carries that, and it is an outward-facing action nobody has authorised.

.PARAMETER ProveRed
    Arming. Packs a layout whose manifest declares a DIFFERENT identity than PackagingPresentation
    states, and requires exactly PACK.identity to break. That arm is the one most likely to rot
    quietly: an identity is a string in two places, drift between them changes nothing anybody
    notices, and a package under the wrong identity packs, validates and installs perfectly while
    being a different product.

    THE FIRST ARMING ATTEMPT PLANTED A DIFFERENT DEFECT AND IS RECORDED HERE BECAUSE IT FAILED
    USEFULLY. It removed the executable from the layout, expecting PACK.payload to break on the
    reasoning that MakeAppx would pack a manifest naming a file the layout did not carry. MakeAppx
    refuses outright - it validates payload presence and exits 1 - so PACK.payload cannot be armed
    by removal, and it is defended by the packer as well as by this lane. That makes the arm cheap
    redundancy rather than the load-bearing check it was written as, and the load-bearing one is
    the identity cross-check.

.NOTES
    Needs elevation for the certificate store. Exit 0 pass, 1 fail, 3 NO VERDICT.
#>
[CmdletBinding()]
param(
    [string] $Out = 'planning/evidence/WIN19/run',
    [string] $ExeDir = '',
    [switch] $ProveRed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutDir = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $RepoRoot $Out }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$PackagingDir = Join-Path $RepoRoot 'app\windows\packaging'
$WingetDir = Join-Path $PackagingDir 'winget'
$PackageName = 'Fledgeling.MCPRouter'
$PublisherId = 'CN=Fledgeling'

$Arms = @()
$Notes = @()

function Add-Arm {
    param([string] $Id, [string] $What, [bool] $Held, [string] $Detail)
    $script:Arms += [pscustomobject]@{ id = $Id; what = $What; held = $Held; detail = $Detail }
    $mark = if ($Held) { 'HELD' } else { 'BROKE' }
    Write-Host ("  {0,-18} {1,-6} {2}" -f $Id, $mark, $What)
    if ($Detail) { Write-Host ("                            {0}" -f $Detail) }
}

function Write-Verdict {
    param([int] $Code, [string] $Verdict, [string] $Reason)
    $doc = [ordered]@{
        lane     = 'win19-package-witness'
        rung     = 'effect-witness'
        subject  = 'app/windows/packaging (AppxManifest.xml, winget/*.yaml)'
        writers  = @('MakeAppx.exe pack', 'Add-AppxPackage', 'Remove-AppxPackage')
        recorders = @(
            'System.IO.Compression.ZipArchive reading the packed OPC container - not MakeAppx',
            'winget validate - the winget client, applying a schema this repository does not own',
            'Get-AppxPackage - the Windows deployment stack reporting its own state'
        )
        recorderIsNotWriter = $true
        arming   = [bool] $ProveRed
        verdict  = $Verdict
        reason   = $Reason
        arms     = $Arms
        armsHeld = @($Arms | Where-Object { $_.held }).Count
        armsTotal = $Arms.Count
        notMeasured = @(
            'that `winget install Fledgeling.MCPRouter` works - nothing publishes the package anywhere, the InstallerUrl is a deliberate placeholder, and this lane asserts it is one (DEF-083)',
            'that a code-signed release installs without a SmartScreen prompt - this lane self-signs, which is the opposite of the case the disclosure is about'
        )
        notes    = $Notes
        host     = $env:COMPUTERNAME
    }
    $path = Join-Path $OutDir $(if ($ProveRed) { 'witness-armed.json' } else { 'witness.json' })
    [System.IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 6),
        (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ("win19 witness: {0} - {1}" -f $Verdict, $Reason)
    Write-Host ("               wrote {0}" -f $path)
    exit $Code
}

# --------------------------------------------------------------------------- the tools
$makeappx = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\makeappx.exe' -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
if ($null -eq $makeappx) {
    Write-Verdict 3 'NO VERDICT' 'no makeappx.exe under the Windows Kits, so nothing could be packed.'
}
$signtool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe' -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1

if (-not $ExeDir) {
    $ExeDir = Join-Path $RepoRoot 'app\windows\MCPRouter.Shell\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64'
}
if (-not (Test-Path (Join-Path $ExeDir 'MCPRouter.Shell.exe'))) {
    Write-Verdict 3 'NO VERDICT' ("no MCPRouter.Shell.exe under {0}. Build it with the Visual " +
        'Studio MSBuild - dotnet build cannot build WinUI here - and run this again.' -f $ExeDir)
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host  'win19 witness: the MSIX, the winget manifest, and a real install/uninstall cycle'
Write-Host ("               makeappx {0}" -f $makeappx.FullName)
Write-Host ("               payload  {0}" -f $ExeDir)
if ($ProveRed) { Write-Host '               ARMING: the executable is withheld from the layout' }
Write-Host ''

# --------------------------------------------------------------------------- PACK
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("mcprouter-msix-" + [guid]::NewGuid().ToString('N'))
$msix = Join-Path $OutDir 'MCPRouter.Shell.msix'
$certSubject = 'CN=Fledgeling'
$cert = $null
$installed = $false

try {
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Copy-Item (Join-Path $PackagingDir 'AppxManifest.xml') $stage
    Copy-Item (Join-Path $PackagingDir 'Assets') $stage -Recurse
    Copy-Item (Join-Path $ExeDir '*') $stage -Recurse -Force -ErrorAction SilentlyContinue
    if ($ProveRed) {
        # THE PLANTED DEFECT: the manifest in the STAGED layout declares an identity that is not
        # the one PackagingPresentation states. Nothing refuses it - MakeAppx packs it, the OPC
        # container is well formed, the payload is present - and the package is a different
        # product. Only the cross-check against the application's own constants can see it.
        #
        # The staged copy is edited and never the tracked file, so an interrupted arming run cannot
        # leave a drifted identity in the repository.
        $stagedManifest = Join-Path $stage 'AppxManifest.xml'
        $planted = (Get-Content $stagedManifest -Raw) -replace
            'Name="Fledgeling.MCPRouter"', 'Name="Fledgeling.MCPRouter.WRONG"'
        [System.IO.File]::WriteAllText($stagedManifest, $planted,
            (New-Object System.Text.UTF8Encoding($false)))
    }

    Remove-Item $msix -Force -ErrorAction SilentlyContinue
    Add-Arm 'BASELINE' 'no package on disk before this run' (-not (Test-Path $msix)) `
        'so what the arms below read is this build'

    $packLog = & $makeappx.FullName pack /d $stage /p $msix /o 2>&1
    $packRc = $LASTEXITCODE
    if ($packRc -ne 0) {
        $Notes += ($packLog | Out-String)
        Add-Arm 'PACK' 'MakeAppx builds a package from app/windows/packaging' $false `
            ("makeappx exit {0}; its output is in notes[]" -f $packRc)
        Write-Verdict 1 'FAIL' 'the manifest could not be packed.'
    }

    # ------------------------------------------------------------------ read it back, not with MakeAppx
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($msix)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName })
        $manifestEntry = $zip.GetEntry('AppxManifest.xml')
        $manifestXml = $null
        if ($null -ne $manifestEntry) {
            $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
            try { $manifestXml = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
    } finally {
        $zip.Dispose()
    }

    Add-Arm 'PACK.container' 'the artifact is an OPC container holding a manifest' `
        ($null -ne $manifestXml) ("{0} entries" -f $entries.Count)

    $packedName = $null
    $packedPublisher = $null
    $packedCaps = 0
    if ($manifestXml) {
        $doc = [xml] $manifestXml
        $packedName = $doc.Package.Identity.Name
        $packedPublisher = $doc.Package.Identity.Publisher
        # ELEMENTS ONLY, and this is a correction rather than a preference. The first version
        # counted ChildNodes, which includes the XML COMMENT sitting inside <Capabilities> - so the
        # arm reported 2 for a manifest declaring exactly one capability, and it would have gone
        # quiet again the moment somebody deleted the comment. An instrument whose answer moves
        # with the prose around the thing it measures is measuring the prose.
        $packedCaps = @($doc.Package.Capabilities.ChildNodes |
            Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element }).Count
    }

    # Compared against PackagingPresentation's constants, read out of the PACKED artifact. A
    # manifest edited to a different identity than the application states would otherwise pack,
    # validate and install perfectly while being a different product.
    Add-Arm 'PACK.identity' 'the packed identity is the one PackagingPresentation states' `
        (($packedName -eq $PackageName) -and ($packedPublisher -eq $PublisherId)) `
        ("Name={0} Publisher={1}" -f $packedName, $packedPublisher)

    $capNames = @()
    if ($manifestXml) {
        $capNames = @($doc.Package.Capabilities.ChildNodes |
            Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element } |
            ForEach-Object { $_.GetAttribute('Name') })
    }
    Add-Arm 'PACK.capabilities' 'exactly one capability is requested, and it is runFullTrust' `
        (($packedCaps -eq 1) -and ($capNames -contains 'runFullTrust')) `
        ("{0} capability element(s): {1}. More than one is a decision about what the operator is asked to permit at install time, and it should not be made by an editor tidying a manifest." -f $packedCaps, ($capNames -join ', '))

    $hasExe = $entries -contains 'MCPRouter.Shell.exe'
    # Kept, and honestly labelled. MakeAppx refuses to pack a manifest naming a file the layout does
    # not carry - measured 2026-09-02, exit 1 - so this arm is a second line behind the packer's own
    # check rather than the only thing standing there. It is worth its two lines because it reads
    # the SHIPPED CONTAINER, which is what an operator receives, and because a future change to how
    # the layout is staged could put a different file in that name.
    Add-Arm 'PACK.payload' 'the package actually carries the executable it names' $hasExe `
        $(if ($hasExe) { 'MCPRouter.Shell.exe is inside the container (MakeAppx also refuses to pack without it)' }
          else { 'the manifest names MCPRouter.Shell.exe and the container does not hold it' })

    # ------------------------------------------------------------------ WINGET
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        $Notes += 'winget is not on PATH, so the manifest was not validated by the client that reads it.'
        Add-Arm 'WINGET.validate' 'the winget client accepts the manifest' $false `
            'winget is absent - NOT a pass: the manifest was read by nothing here'
    } else {
        $wingetOut = & $winget.Source validate --manifest $WingetDir 2>&1
        $wingetRc = $LASTEXITCODE
        Add-Arm 'WINGET.validate' 'the winget client accepts the manifest' ($wingetRc -eq 0) `
            (($wingetOut | Select-Object -First 1) -join ' ')
    }

    # The placeholder is asserted PRESENT. A manifest whose InstallerUrl looked plausible would
    # validate, read as finished, and 404 for the first person who ran `winget install`.
    $installerYaml = Get-Content (Join-Path $WingetDir 'Fledgeling.MCPRouter.installer.yaml') -Raw
    Add-Arm 'WINGET.placeholder' 'the installer URL is still an unmistakable placeholder' `
        ($installerYaml -match 'example\.invalid') `
        'nothing publishes this package, so a plausible-looking URL would be a lie that validates'

    # ------------------------------------------------------------------ INSTALL / UNINSTALL
    if ($ProveRed) {
        $Notes += ('arming run: the install and uninstall arms are skipped. The planted ' +
            'package carries a DIFFERENT identity, so deploying it would register a ' +
            'Fledgeling.MCPRouter.WRONG package that this lane cleanup does not name - and a ' +
            'witness that leaves a stray package behind is the shape of side effect this one ' +
            'refuses to have.')
    } elseif (-not $elevated) {
        $Notes += 'not elevated: the certificate store could not be written, so the install and uninstall arms did not run. That is NOT a pass for them.'
        Add-Arm 'INSTALL' 'Windows accepts the package' $false 'not run - this session is not elevated'
    } elseif ($null -eq $signtool) {
        $Notes += 'no signtool.exe under the Windows Kits, so the package could not be signed for deployment.'
        Add-Arm 'INSTALL' 'Windows accepts the package' $false 'not run - signtool absent'
    } else {
        # The configuration directory the uninstall promises to preserve. Created if absent, so the
        # UNINSTALL.preserves arm has something to be about on a machine that has never run the
        # product - and recorded, because a lane that creates the thing it then finds is only honest
        # if it says so.
        $configDir = Join-Path $env:USERPROFILE '.claude\mcp-router'
        $marker = Join-Path $configDir 'win19-witness-marker.txt'
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Force -Path $configDir | Out-Null
            $Notes += ("created {0} - it did not exist, and the preservation arm needs something to be about." -f $configDir)
        }
        [System.IO.File]::WriteAllText($marker, 'planted by win19-package-witness before install')

        $cert = New-SelfSignedCertificate -Type Custom -Subject $certSubject `
            -KeyUsage DigitalSignature -FriendlyName 'MCPRouter WIN19 witness (transient)' `
            -CertStoreLocation 'Cert:\CurrentUser\My' `
            -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}Subject Type:End Entity')

        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
            'TrustedPeople', 'LocalMachine')
        $store.Open('ReadWrite')
        $store.Add($cert)
        $store.Close()

        $signOut = & $signtool.FullName sign /fd SHA256 /a /sha1 $cert.Thumbprint $msix 2>&1
        if ($LASTEXITCODE -ne 0) {
            $Notes += ($signOut | Out-String)
            Add-Arm 'INSTALL' 'Windows accepts the package' $false `
                'signtool refused the package; its output is in notes[]'
        } else {
            Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
                Remove-AppxPackage -ErrorAction SilentlyContinue
            Add-Arm 'INSTALL.baseline' 'the package is not installed before this run' `
                ($null -eq (Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)) `
                'so the install arm measures this deployment'

            $addError = $null
            try { Add-AppxPackage -Path $msix -ErrorAction Stop }
            catch { $addError = $_.Exception.Message }

            $seen = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
            $installed = ($null -ne $seen)
            # THE ARM THAT TURNS A FILE INTO A PACKAGE. Everything above is static: a manifest can
            # pack and validate and be refused here for a capability, an architecture or a
            # signature, and no static check anywhere would have said so.
            Add-Arm 'INSTALL' 'the Windows deployment stack reports the package installed' $installed `
                $(if ($installed) { "PackageFullName=" + $seen.PackageFullName }
                  else { "Add-AppxPackage did not deploy it: " + $addError })

            if ($installed) {
                Add-Arm 'INSTALL.identity' 'the deployed publisher is the one the manifest declared' `
                    ($seen.Publisher -eq $PublisherId) ("Publisher=" + $seen.Publisher)

                Remove-AppxPackage -Package $seen.PackageFullName -ErrorAction SilentlyContinue
                $after = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
                $installed = ($null -ne $after)
                Add-Arm 'UNINSTALL' 'the package is gone once removed' ($null -eq $after) `
                    $(if ($null -eq $after) { 'Get-AppxPackage reports nothing, so its earlier yes was a reading' }
                      else { 'the deployment stack still reports it' })

                # "Clean uninstall rules" as a measurable claim. UninstallGuidance promises the
                # configuration survives; this is the only way to find out, and it needed an
                # uninstall that actually ran.
                Add-Arm 'UNINSTALL.preserves' 'the configuration UninstallGuidance names survives' `
                    (Test-Path $marker) ("checked {0}" -f $marker)
            }
        }
    }
}
finally {
    # Everything this lane changed about the machine, put back. A witness that leaves a trusted
    # certificate behind has changed what this machine will install, which is not a side effect a
    # test gets to have - and it is the kind that survives every future run silently.
    if ($installed) {
        Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
            Remove-AppxPackage -ErrorAction SilentlyContinue
    }
    if ($null -ne $cert) {
        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
                'TrustedPeople', 'LocalMachine')
            $store.Open('ReadWrite')
            $found = $store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
            foreach ($c in @($found)) { $store.Remove($c) }
            $store.Close()
            Remove-Item ("Cert:\CurrentUser\My\" + $cert.Thumbprint) -Force -ErrorAction SilentlyContinue
        } catch {
            $Notes += ('CERTIFICATE NOT REMOVED: ' + $_.Exception.Message +
                       ' - this machine now trusts a self-signed publisher it did not before.')
        }
    }
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------------- the verdict
$broke = @($Arms | Where-Object { -not $_.held })
$brokeIds = ($broke | ForEach-Object { $_.id }) -join ', '

if ($ProveRed) {
    if ($brokeIds -eq 'PACK.identity') {
        Write-Verdict 0 'PASS (armed)' ('a manifest declaring Fledgeling.MCPRouter.WRONG packed ' +
            'cleanly, held a well-formed container, carried its payload and passed every other ' +
            'arm - and exactly PACK.identity broke. So that arm reads the identity OUT OF THE ' +
            'PACKED ARTIFACT and compares it with what the application states, rather than ' +
            'restating either. Nothing else in the toolchain notices this: a package under the ' +
            'wrong identity installs perfectly and is a different product.')
    }
    Write-Verdict 1 'FAIL (arming)' ("expected exactly PACK.identity to break; broke: {0}" -f
        $(if ($brokeIds) { $brokeIds } else { 'nothing - the identity cross-check cannot fail' }))
}

if ($broke.Count -gt 0) {
    Write-Verdict 1 'FAIL' ("{0} of {1} arm(s) broke: {2}" -f $broke.Count, $Arms.Count, $brokeIds)
}
$reason = ('all {0} arm(s) held: the manifest packs into an MSIX carrying the executable it names ' +
    'under the identity PackagingPresentation states, the winget client accepts the three YAML ' +
    'files, Windows deployed the package and reported it, and removing it left the configuration ' +
    'UninstallGuidance promises to preserve in place.') -f $Arms.Count
Write-Verdict 0 'PASS' $reason
