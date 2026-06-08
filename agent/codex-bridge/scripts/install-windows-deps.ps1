param(
    [string]$VcpkgExe = $(if ($env:VCPKG_ROOT) { Join-Path $env:VCPKG_ROOT "vcpkg.exe" } else { "vcpkg.exe" }),
    [string]$InstallRoot = $env:VCPKG_INSTALLED_ROOT,
    [string]$ManifestDir = "",
    [string]$OverlayPorts = "",
    [string]$VsCMakeBin = $env:RUSTDESK_VS_CMAKE_BIN,
    [string]$WingetNinjaBin = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe",
    [string]$GitUsrBin = "C:\Program Files\Git\usr\bin",
    [switch]$SkipAom,
    [switch]$CleanManifestDir
)

$ErrorActionPreference = "Stop"

function Resolve-Executable {
    param([Parameter(Mandatory = $true)][string]$CommandOrPath)

    if (Test-Path $CommandOrPath) {
        return (Resolve-Path $CommandOrPath).Path
    }
    $command = Get-Command $CommandOrPath -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    return $null
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $repo ".vcpkg-installed"
}
if ([string]::IsNullOrWhiteSpace($ManifestDir)) {
    $ManifestDir = Join-Path $PSScriptRoot "..\vcpkg-minimal"
}
if ([string]::IsNullOrWhiteSpace($OverlayPorts)) {
    $OverlayPorts = Join-Path $PSScriptRoot "..\vcpkg-overlays"
}

$resolvedVcpkgExe = Resolve-Executable $VcpkgExe
if (-not $resolvedVcpkgExe) {
    throw "vcpkg.exe not found. Pass -VcpkgExe or set VCPKG_ROOT."
}
$VcpkgExe = $resolvedVcpkgExe

if ([string]::IsNullOrWhiteSpace($VsCMakeBin)) {
    throw "CMake not configured. Pass -VsCMakeBin or set RUSTDESK_VS_CMAKE_BIN."
}

if (-not (Test-Path (Join-Path $VsCMakeBin "cmake.exe"))) {
    throw "CMake not found. Pass -VsCMakeBin or set RUSTDESK_VS_CMAKE_BIN."
}

if (-not (Test-Path (Join-Path $WingetNinjaBin "ninja.exe"))) {
    throw "Ninja not found. Install with: winget install --id Ninja-build.Ninja -e"
}

if (-not (Test-Path (Join-Path $GitUsrBin "perl.exe"))) {
    throw "Perl not found. Expected Git bundled Perl at: $GitUsrBin"
}

if ($CleanManifestDir -and (Test-Path $ManifestDir)) {
    Remove-Item -LiteralPath $ManifestDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $ManifestDir | Out-Null

$dependencies = @(
    '"libvpx"',
    '"libyuv"',
    '"opus"'
)

if (-not $SkipAom) {
    $dependencies = @('"aom"') + $dependencies
}

$manifest = @"
{
  "builtin-baseline": "120deac3062162151622ca4860575a33844ba10b",
  "dependencies": [
    $($dependencies -join ",`n    ")
  ]
}
"@

Set-Content -Path (Join-Path $ManifestDir "vcpkg.json") -Value $manifest -Encoding UTF8

$env:PATH = "$VsCMakeBin;$WingetNinjaBin;$GitUsrBin;$env:PATH"
$env:VCPKG_ROOT = Split-Path -Parent $VcpkgExe
$env:PERL = Join-Path $GitUsrBin "perl.exe"
Remove-Item Env:\VCPKG_FORCE_SYSTEM_BINARIES -ErrorAction SilentlyContinue

Write-Host "Installing minimal RustDesk desktop deps into $InstallRoot"
Write-Host "Manifest: $ManifestDir"
Write-Host "Overlay ports: $OverlayPorts"
Write-Host "VCPKG_ROOT: $env:VCPKG_ROOT"
Write-Host "PERL: $env:PERL"

Push-Location $ManifestDir
try {
    & $VcpkgExe install --triplet x64-windows-static --x-install-root="$InstallRoot" --overlay-ports="$OverlayPorts"
    if ($LASTEXITCODE -ne 0) {
        throw "vcpkg install failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Done. Use VCPKG_INSTALLED_ROOT=$InstallRoot when running cargo."
