param(
  [string] $ServiceName = 'RustDesk',
  [string] $SourceExe = '',
  [string] $InstallExe = $env:RUSTDESK_INSTALL_EXE
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($SourceExe)) {
  $SourceExe = Join-Path $repo 'target\debug\rustdesk.exe'
}
if ([string]::IsNullOrWhiteSpace($InstallExe)) {
  throw 'Install exe is required. Pass -InstallExe or set RUSTDESK_INSTALL_EXE.'
}

if (-not (Test-Path -LiteralPath $SourceExe)) {
  throw "Source exe not found: $SourceExe"
}

$installDir = Split-Path -Path $InstallExe -Parent
if (-not (Test-Path -LiteralPath $installDir)) {
  throw "Install dir not found: $installDir"
}

Write-Host "Stopping service $ServiceName"
sc.exe stop $ServiceName | Out-Host
Start-Sleep -Seconds 3

Write-Host "Killing remaining rustdesk.exe processes"
Get-Process rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "Copying $SourceExe -> $InstallExe"
Copy-Item -LiteralPath $SourceExe -Destination $InstallExe -Force

Write-Host "Ensuring service binPath"
sc.exe config $ServiceName binPath= "`"$InstallExe`" --service" | Out-Host

Write-Host "Starting service $ServiceName"
sc.exe start $ServiceName | Out-Host
Start-Sleep -Seconds 3

Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" |
  Select-Object Name, State, PathName, ProcessId |
  Format-List
