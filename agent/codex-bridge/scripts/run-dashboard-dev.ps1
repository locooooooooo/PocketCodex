param(
    [ValidateSet("windows", "android")]
    [string]$Platform = "windows",
    [ValidateSet("normal", "full", "floating")]
    [string]$Mode = "floating",
    [string]$FlutterBin = $env:FLUTTER_BIN,
    [string]$AndroidDeviceId = $env:RUSTDESK_ANDROID_DEVICE_ID
)

$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Body
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$flutterDir = Join-Path $repo "flutter"
if ([string]::IsNullOrWhiteSpace($FlutterBin)) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        $FlutterBin = Split-Path -Parent $flutterCommand.Source
    }
}
if ([string]::IsNullOrWhiteSpace($FlutterBin)) {
    throw "Flutter is not configured. Set FLUTTER_BIN, add flutter to PATH, or pass -FlutterBin."
}

$flutterExe = Join-Path $FlutterBin "flutter.bat"
if (-not (Test-Path $flutterExe)) {
    throw "Flutter not found: $flutterExe"
}

$env:PATH = "$FlutterBin;$env:PATH"

switch ($Platform) {
    "windows" { $device = "windows" }
    "android" {
        if ([string]::IsNullOrWhiteSpace($AndroidDeviceId)) {
            throw "Android device id is required for -Platform android. Pass -AndroidDeviceId or set RUSTDESK_ANDROID_DEVICE_ID."
        }
        $device = $AndroidDeviceId
    }
}

$args = @("run", "-d", $device)

if ($Mode -ne "normal") {
    $args += "--dart-define=RUSTDESK_DEV_DASHBOARD_MODE=$Mode"
}

Invoke-Step "Flutter doctor" {
    Push-Location $flutterDir
    try {
        & $flutterExe doctor -v
    } finally {
        Pop-Location
    }
}

Invoke-Step "Flutter run ($Platform / $Mode)" {
    Push-Location $flutterDir
    try {
        Write-Host "Command: flutter $($args -join ' ')"
        & $flutterExe @args
    } finally {
        Pop-Location
    }
}
