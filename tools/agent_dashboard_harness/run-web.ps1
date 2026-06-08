param(
  [ValidateSet('floating', 'full')]
  [string] $Mode = 'floating',
  [int] $Port = 53221
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
try {
  flutter run -d chrome --web-hostname=127.0.0.1 --web-port=$Port --dart-define=RUSTDESK_DEV_DASHBOARD_MODE=$Mode
} finally {
  Pop-Location
}
