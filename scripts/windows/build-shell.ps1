<#
.SYNOPSIS
  Builds the Windows client (WIN3's shell and its two sibling projects).

.DESCRIPTION
  Two things here are measurements rather than style, and both cost a session to find:

  1. `dotnet build` cannot build a WinUI 3 project on this machine. It resolves
     MSBuildExtensionsPath to the .NET SDK, which carries no AppxPackage tasks, and fails MSB4062
     however complete the Visual Studio install is. WIN1 measured that. The lane is Visual
     Studio's own MSBuild.exe.

  2. Restore and Build must be SEPARATE invocations. `MSBuild -t:Restore,Build` in one call fails
     on a cold obj/ with `CS0103: The name 'InitializeComponent' does not exist in the current
     context`, because the Build target evaluates before Restore has written the WindowsAppSDK
     targets that add the XAML markup-compile passes. The same project builds cleanly when the
     two targets are separate calls. Measured 2026-08-30 on a clean tree, both ways.

  Exit 0 build succeeded. Any other code is MSBuild's.
#>
param(
    [ValidateSet('Debug', 'Release')] [string] $Configuration = 'Debug',
    [switch] $Clean
)

$ErrorActionPreference = 'Continue'   # native tools write progress to stderr; see CLAUDE.md

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$msbuild = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
$project = Join-Path $root 'app\windows\MCPRouter.Shell\MCPRouter.Shell.csproj'

if (-not (Test-Path $msbuild)) {
    Write-Host "MSBuild.exe not found at $msbuild" -ForegroundColor Red
    Write-Host "WinUI 3 needs Visual Studio Build Tools 2022 with the managed-desktop and UWP build-tool workloads."
    exit 2
}
if (-not (Test-Path $project)) {
    Write-Host "project not found: $project" -ForegroundColor Red
    exit 2
}

if ($Clean) {
    foreach ($dir in @('bin', 'obj')) {
        Get-ChildItem (Join-Path $root 'app\windows') -Recurse -Directory -Filter $dir -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "restore..." -ForegroundColor Cyan
& $msbuild $project -t:Restore -p:Configuration=$Configuration -v:q -nologo
if ($LASTEXITCODE -ne 0) { Write-Host "restore failed ($LASTEXITCODE)" -ForegroundColor Red; exit $LASTEXITCODE }

Write-Host "build..." -ForegroundColor Cyan
& $msbuild $project -t:Build -p:Configuration=$Configuration -v:m -nologo
if ($LASTEXITCODE -ne 0) { Write-Host "build failed ($LASTEXITCODE)" -ForegroundColor Red; exit $LASTEXITCODE }

$exe = Join-Path $root "app\windows\MCPRouter.Shell\bin\$Configuration\net8.0-windows10.0.19041.0\win-x64\MCPRouter.Shell.exe"
if (-not (Test-Path $exe)) {
    # A wrapper's exit code is not evidence. Judge by the artefact on disk.
    Write-Host "MSBuild reported success and produced no executable at $exe" -ForegroundColor Red
    exit 3
}

Write-Host "built: $exe" -ForegroundColor Green
exit 0
