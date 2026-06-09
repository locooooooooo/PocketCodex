param(
    [string]$VsDevCmd = $env:RUSTDESK_VS_DEV_CMD,
    [string]$LlvmBin = $(if ($env:LLVM_BIN) { $env:LLVM_BIN } else { "C:\Program Files\LLVM\bin" }),
    [string]$VsCMakeBin = $env:RUSTDESK_VS_CMAKE_BIN,
    [string]$WingetNinjaBin = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe",
    [string]$GitUsrBin = "C:\Program Files\Git\usr\bin"
)

$ErrorActionPreference = "Stop"

function Find-CommandPath {
    param([Parameter(Mandatory = $true)][string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    return $null
}

function Test-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$ExplicitPath
    )

    $path = $null
    if ($ExplicitPath -and (Test-Path $ExplicitPath)) {
        $path = $ExplicitPath
    } else {
        $path = Find-CommandPath $Name
    }

    [pscustomobject]@{
        tool = $Name
        ok = [bool]$path
        path = $path
    }
}

function Join-PathIfBase {
    param(
        [string]$Base,
        [string]$Child
    )
    if ([string]::IsNullOrWhiteSpace($Base)) {
        return ""
    }
    return Join-Path $Base $Child
}

$tools = @(
    (Test-Tool -Name "cargo"),
    (Test-Tool -Name "rustc"),
    (Test-Tool -Name "git"),
    (Test-Tool -Name "codex"),
    (Test-Tool -Name "flutter"),
    (Test-Tool -Name "dart"),
    (Test-Tool -Name "cmake" -ExplicitPath (Join-PathIfBase $VsCMakeBin "cmake.exe")),
    (Test-Tool -Name "ninja" -ExplicitPath (Join-PathIfBase $WingetNinjaBin "ninja.exe")),
    (Test-Tool -Name "perl" -ExplicitPath (Join-PathIfBase $GitUsrBin "perl.exe")),
    (Test-Tool -Name "clang" -ExplicitPath (Join-PathIfBase $LlvmBin "clang.exe")),
    (Test-Tool -Name "libclang.dll" -ExplicitPath (Join-PathIfBase $LlvmBin "libclang.dll")),
    (Test-Tool -Name "vcvars64.bat" -ExplicitPath $VsDevCmd)
)

Write-Host "RustDesk Agent Windows environment"
Write-Host "Repository: $((Resolve-Path .).Path)"
Write-Host ""

$tools | Format-Table -AutoSize

$missingRequired = $tools | Where-Object {
    $_.tool -in @("cargo", "rustc", "git", "codex", "cmake", "ninja", "perl", "clang", "libclang.dll", "vcvars64.bat") -and -not $_.ok
}

if ($missingRequired.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing required desktop build tools:" -ForegroundColor Yellow
    $missingRequired | ForEach-Object { Write-Host "  - $($_.tool)" }
    Write-Host ""
    Write-Host "Configuration hints:" -ForegroundColor Yellow
    Write-Host "  - Set RUSTDESK_VS_DEV_CMD or pass -VsDevCmd for vcvars64.bat."
    Write-Host "  - Set RUSTDESK_VS_CMAKE_BIN or pass -VsCMakeBin for Visual Studio or standalone CMake."
    Write-Host "  - Set LLVM_BIN or pass -LlvmBin for LLVM/bin."
    exit 1
}

if (-not (Find-CommandPath "flutter")) {
    Write-Host ""
    Write-Host "Flutter is not on PATH. Rust checks can run, but a full Flutter desktop build still needs Flutter/Dart." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Environment check complete."
