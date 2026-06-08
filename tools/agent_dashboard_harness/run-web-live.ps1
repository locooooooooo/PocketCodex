param(
  [ValidateSet('floating', 'full')]
  [string] $Mode = 'floating',
  [int] $Port = 53231,
  [int] $BridgePort = 17331,
  [switch] $RebuildOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$bridgeDir = Join-Path $root 'debug-bridge'
$webRoot = Join-Path $root 'build\web'

function Start-HiddenProcess {
  param(
    [Parameter(Mandatory = $true)][string] $WorkingDirectory,
    [Parameter(Mandatory = $true)][string] $Command
  )

  Start-Process powershell `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $Command) `
    -WorkingDirectory $WorkingDirectory `
    -WindowStyle Hidden
}

Push-Location $bridgeDir
try {
  if (-not (Test-Path (Join-Path $bridgeDir 'node_modules'))) {
    npm.cmd install
  }
} finally {
  Pop-Location
}

$bridgeListening = Get-NetTCPConnection -LocalPort $BridgePort -State Listen -ErrorAction SilentlyContinue
if (-not $bridgeListening) {
  $bridgeCommand = @(
    "`$env:RUSTDESK_DEBUG_BRIDGE_PORT='$BridgePort'"
    "`$env:RUSTDESK_UPSTREAM_BRIDGE_URL='http://127.0.0.1:17321'"
    "Set-Location '$bridgeDir'"
    'node server.mjs'
  ) -join '; '

  Start-HiddenProcess -WorkingDirectory $bridgeDir -Command $bridgeCommand

  Start-Sleep -Seconds 2
}

Push-Location $root
try {
  flutter build web `
    --pwa-strategy=none `
    --dart-define=RUSTDESK_DEV_DASHBOARD_MODE=$Mode `
    --dart-define=RUSTDESK_DEV_DASHBOARD_DATA_MODE=live `
    --dart-define=RUSTDESK_AGENT_DASHBOARD_BRIDGE_URL=http://127.0.0.1:$BridgePort
} finally {
  Pop-Location
}

if ($RebuildOnly) {
  exit 0
}

$webListening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (-not $webListening) {
  $webCommand = @(
    "`$env:RUSTDESK_DASHBOARD_WEB_PORT='$Port'"
    "`$env:RUSTDESK_DASHBOARD_WEB_ROOT='$webRoot'"
    "Set-Location '$root'"
    "node serve-web.mjs"
  ) -join '; '

  Start-HiddenProcess -WorkingDirectory $root -Command $webCommand
  Start-Sleep -Seconds 2
}
