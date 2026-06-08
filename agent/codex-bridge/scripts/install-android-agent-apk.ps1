param(
    [string]$Adb = $(if ($env:ANDROID_SDK_ROOT) { Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe" } elseif ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME "platform-tools\adb.exe" } else { "adb" }),
    [string]$ApkPath = "",
    [string]$PackageName = "com.carriez.flutter_hbb",
    [string]$ActivityName = "com.carriez.flutter_hbb.MainActivity",
    [string]$Serial = "",
    [switch]$SkipLaunch
)

$ErrorActionPreference = "Stop"

function Require-Path {
    param(
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path $Path)) {
        throw "$Message Missing: $Path"
    }
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $adbArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        $adbArgs += @("-s", $Serial)
    }
    $adbArgs += $Arguments
    Write-Host "$Adb $($adbArgs -join ' ')"
    & $Adb @adbArgs
    if ($LASTEXITCODE -ne 0) {
        throw "adb command failed with exit code $LASTEXITCODE"
    }
}

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
if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $repo "flutter\build\app\outputs\flutter-apk\app-arm64-v8a-debug.apk"
}

$resolvedAdb = Resolve-Executable $Adb
if (-not $resolvedAdb) {
    throw "adb is not available. Add adb to PATH, set ANDROID_SDK_ROOT/ANDROID_HOME, or pass -Adb."
}
$Adb = $resolvedAdb
Require-Path $ApkPath "APK is not available."

$deviceOutput = & $Adb devices
if ($LASTEXITCODE -ne 0) {
    throw "Failed to query adb devices."
}

$deviceLines = @($deviceOutput | Select-Object -Skip 1 | Where-Object {
    $_ -and $_.Trim() -and ($_ -notmatch "^\*") -and ($_ -notmatch "^\s*$")
})

$readyDevices = @($deviceLines | Where-Object { $_ -match "`tdevice($|\s)" })
$unauthorizedDevices = @($deviceLines | Where-Object { $_ -match "`tunauthorized($|\s)" })

if ($unauthorizedDevices.Count -gt 0) {
    throw "Android device is connected but not authorized for USB debugging. Accept the RSA prompt on the phone first."
}

if ($readyDevices.Count -eq 0) {
    throw "No authorized Android device found. Connect the phone, enable Developer Options + USB debugging, and rerun."
}

if ([string]::IsNullOrWhiteSpace($Serial) -and $readyDevices.Count -gt 1) {
    throw "Multiple Android devices detected. Rerun with -Serial <device-id>."
}

if ([string]::IsNullOrWhiteSpace($Serial)) {
    $Serial = ($readyDevices[0] -split "`t")[0].Trim()
}

Write-Host ""
Write-Host "Using Android device: $Serial"

Invoke-Adb -Arguments @("install", "-r", $ApkPath)

if (-not $SkipLaunch) {
    Invoke-Adb -Arguments @("shell", "am", "start", "-n", "$PackageName/$ActivityName")
}

Write-Host ""
Write-Host "Android APK installed successfully."
if (-not $SkipLaunch) {
    Write-Host "RustDesk launch command sent."
}
