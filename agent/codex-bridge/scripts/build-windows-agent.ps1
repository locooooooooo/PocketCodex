param(
    [string]$VsDevCmd = $env:RUSTDESK_VS_DEV_CMD,
    [string]$LlvmBin = $(if ($env:LLVM_BIN) { $env:LLVM_BIN } else { "C:\Program Files\LLVM\bin" }),
    [string]$VcpkgRoot = $env:VCPKG_ROOT,
    [string]$VcpkgInstalledRoot = $env:VCPKG_INSTALLED_ROOT,
    [string]$VsCMakeBin = $env:RUSTDESK_VS_CMAKE_BIN,
    [string]$WingetNinjaBin = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe",
    [string]$PythonDir = $env:PYTHON_HOME,
    [string]$FlutterBin = $env:FLUTTER_BIN,
    [string]$RustToolchain = $(if ($env:RUSTUP_TOOLCHAIN) { $env:RUSTUP_TOOLCHAIN } else { "1.75.0-x86_64-pc-windows-msvc" }),
    [string]$CargoRegistryProtocol = $(if ($env:CARGO_REGISTRIES_CRATES_IO_PROTOCOL) { $env:CARGO_REGISTRIES_CRATES_IO_PROTOCOL } else { "sparse" }),
    [string]$CargoHome = $env:CARGO_HOME,
    [string]$PubCache = $env:PUB_CACHE,
    [string]$PubHostedUrl = $env:PUB_HOSTED_URL,
    [string]$FlutterStorageBaseUrl = $env:FLUTTER_STORAGE_BASE_URL,
    [string]$Cc = $env:CC,
    [string]$Cxx = $env:CXX,
    [ValidateSet("check", "rust-release", "flutter-release")]
    [string]$Mode = "check"
)

$ErrorActionPreference = "Stop"

function Add-PathIfExists {
    param(
        [string[]]$Parts,
        [string]$Path
    )

    if ($Path -and (Test-Path $Path)) {
        return @($Path) + $Parts
    }
    return $Parts
}

function Test-SymlinkSupport {
    $testRoot = Join-Path $env:TEMP ("rustdesk-symlink-test-" + [guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        $target = Join-Path $testRoot "target.txt"
        $link = Join-Path $testRoot "link.txt"
        Set-Content -Path $target -Value "test" -Encoding ASCII
        New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
        return @{ ok = $true; error = "" }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    } finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-DeveloperModeState {
    try {
        $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
        $value = (Get-ItemProperty -Path $key -Name AllowDevelopmentWithoutDevLicense -ErrorAction Stop).AllowDevelopmentWithoutDevLicense
        if ($value -eq 1) {
            return "enabled"
        }
        return "disabled"
    } catch {
        return "unknown"
    }
}

function Add-CmdEnvLine {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $escaped = $Value.Replace('"', '""')
        $Lines.Add("set `"$Name=$escaped`"")
    }
}

function Resolve-WindowsReleaseExe {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $preferred = Join-Path $RepoRoot "flutter\build\windows\x64\runner\Release\rustdesk.exe"
    if (Test-Path $preferred) {
        return $preferred
    }

    $fallback = Join-Path $RepoRoot "flutter\build\windows\x64\runner\rustdesk.exe"
    if (Test-Path $fallback) {
        return $fallback
    }

    return $preferred
}

$repo = (Resolve-Path ".").Path
if ([string]::IsNullOrWhiteSpace($VcpkgInstalledRoot)) {
    $VcpkgInstalledRoot = Join-Path $repo ".vcpkg-installed"
}
if ([string]::IsNullOrWhiteSpace($VcpkgRoot)) {
    $VcpkgRoot = $VcpkgInstalledRoot
}
if ([string]::IsNullOrWhiteSpace($Cc)) {
    $Cc = "cl"
}
if ([string]::IsNullOrWhiteSpace($Cxx)) {
    $Cxx = "cl"
}

if ([string]::IsNullOrWhiteSpace($VsDevCmd) -or -not (Test-Path $VsDevCmd)) {
    throw "vcvars64.bat not found. Pass -VsDevCmd or set RUSTDESK_VS_DEV_CMD."
}

if (-not (Test-Path (Join-Path $LlvmBin "libclang.dll"))) {
    throw "libclang.dll not found. Install LLVM, then rerun. Expected: $LlvmBin"
}

if (-not (Test-Path (Join-Path $VcpkgInstalledRoot "x64-windows-static\include"))) {
    throw "vcpkg deps not found. Run agent/codex-bridge/scripts/install-windows-deps.ps1 first."
}

$compatInstalled = Join-Path $VcpkgInstalledRoot "installed"
if (-not (Test-Path $compatInstalled)) {
    New-Item -ItemType Directory -Force -Path $compatInstalled | Out-Null
}

$compatTriplet = Join-Path $compatInstalled "x64-windows-static"
$actualTriplet = Join-Path $VcpkgInstalledRoot "x64-windows-static"
if (-not (Test-Path $compatTriplet)) {
    cmd.exe /d /s /c "mklink /J `"$compatTriplet`" `"$actualTriplet`"" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create vcpkg compatibility junction: $compatTriplet -> $actualTriplet"
    }
}

$pathParts = @($LlvmBin, $VsCMakeBin, $WingetNinjaBin)
$pathParts = Add-PathIfExists -Parts $pathParts -Path $PythonDir
$pathParts = Add-PathIfExists -Parts $pathParts -Path $FlutterBin
$path = (($pathParts | Where-Object { $_ }) -join ";") + ";%PATH%"

switch ($Mode) {
    "check" {
        $cargoCommand = "cargo check --locked --lib --features flutter --offline"
    }
    "rust-release" {
        $cargoCommand = "cargo build --locked --lib --features flutter --release"
    }
    "flutter-release" {
        $flutterBat = if ($FlutterBin) { Join-Path $FlutterBin "flutter.bat" } else { "" }
        if (-not (Get-Command flutter -ErrorAction SilentlyContinue) -and (-not $flutterBat -or -not (Test-Path $flutterBat))) {
            throw "Flutter is not available. Install Flutter/Dart, pass -FlutterBin, or set FLUTTER_BIN."
        }

        $pythonExe = if ($PythonDir) { Join-Path $PythonDir "python.exe" } else { "" }
        if (-not (Get-Command python -ErrorAction SilentlyContinue) -and (-not $pythonExe -or -not (Test-Path $pythonExe))) {
            throw "Python is not available. Install Python, pass -PythonDir, or set PYTHON_HOME."
        }

        $symlink = Test-SymlinkSupport
        if (-not $symlink.ok) {
            $developerMode = Get-DeveloperModeState
            if ($developerMode -eq "enabled") {
                Write-Warning "Symbolic link self-check failed in the current PowerShell process, but Developer Mode is enabled. Continue and let Flutter/CMake perform the real build. Symlink test error: $($symlink.error)"
            } else {
                throw "Flutter Windows plugin build requires symlink support. Current process cannot create symlinks. Developer Mode: $developerMode. Enable Windows Developer Mode with 'start ms-settings:developers', or rerun this build from an elevated Administrator terminal. Symlink test error: $($symlink.error)"
            }
        }
        $cargoCommand = "python build.py --flutter --skip-portable-pack"
    }
}

$cmdLines = [System.Collections.Generic.List[string]]::new()
$cmdLines.Add("@echo off")
$cmdLines.Add('set "PROCESSOR_ARCHITECTURE=AMD64"')
$cmdLines.Add('set "PROCESSOR_ARCHITEW6432=AMD64"')
$cmdLines.Add("call `"$VsDevCmd`" >nul")
$cmdLines.Add("if errorlevel 1 exit /b %errorlevel%")
$cmdLines.Add("set `"PATH=$path`"")
Add-CmdEnvLine -Lines $cmdLines -Name "RUSTUP_TOOLCHAIN" -Value $RustToolchain
Add-CmdEnvLine -Lines $cmdLines -Name "CARGO_REGISTRIES_CRATES_IO_PROTOCOL" -Value $CargoRegistryProtocol
Add-CmdEnvLine -Lines $cmdLines -Name "LIBCLANG_PATH" -Value $LlvmBin
Add-CmdEnvLine -Lines $cmdLines -Name "VCPKG_ROOT" -Value $VcpkgRoot
Add-CmdEnvLine -Lines $cmdLines -Name "VCPKG_INSTALLED_ROOT" -Value $VcpkgInstalledRoot
Add-CmdEnvLine -Lines $cmdLines -Name "CARGO_HOME" -Value $CargoHome
Add-CmdEnvLine -Lines $cmdLines -Name "PUB_CACHE" -Value $PubCache
Add-CmdEnvLine -Lines $cmdLines -Name "PUB_HOSTED_URL" -Value $PubHostedUrl
Add-CmdEnvLine -Lines $cmdLines -Name "FLUTTER_STORAGE_BASE_URL" -Value $FlutterStorageBaseUrl
Add-CmdEnvLine -Lines $cmdLines -Name "CC" -Value $Cc
Add-CmdEnvLine -Lines $cmdLines -Name "CXX" -Value $Cxx
$cmdLines.Add("cd /d `"$repo`"")
$cmdLines.Add($cargoCommand)
$cmd = ($cmdLines -join "`r`n") + "`r`n"

Write-Host "Running $Mode build command:"
Write-Host $cargoCommand

$tmpCmd = Join-Path $env:TEMP ("rustdesk-agent-build-" + [guid]::NewGuid().ToString("N") + ".cmd")
try {
    Set-Content -Path $tmpCmd -Value $cmd -Encoding ASCII
    & cmd.exe /d /s /c "`"$tmpCmd`""
    if ($LASTEXITCODE -ne 0) {
        throw "Build command failed with exit code $LASTEXITCODE"
    }
} finally {
    Remove-Item -LiteralPath $tmpCmd -Force -ErrorAction SilentlyContinue
}

if ($Mode -eq "flutter-release") {
    $releaseExe = Resolve-WindowsReleaseExe -RepoRoot $repo
    if (-not (Test-Path $releaseExe)) {
        throw "Windows release executable was not produced. Expected: $releaseExe"
    }

    Write-Host ""
    Write-Host "Verifying Windows release executable:"
    Write-Host $releaseExe

    & $releaseExe --version
    if ($LASTEXITCODE -ne 0) {
        throw "rustdesk.exe --version failed with exit code $LASTEXITCODE"
    }
}
