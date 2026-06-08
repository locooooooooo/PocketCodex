param(
    [string]$HostIp = $env:RUSTDESK_HOST_IP,
    [string]$RelayPort = "21117",
    [string]$ComposeFile = ""
)

$ErrorActionPreference = "Stop"
$TcpPorts = @(21115, 21116, 21117, 21118, 21119)

function Test-TcpPort {
    param(
        [string]$TargetHost,
        [int]$Port,
        [int]$TimeoutMs = 1500
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $asyncResult = $client.BeginConnect($TargetHost, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($asyncResult)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

Require-Command "docker"

if ([string]::IsNullOrWhiteSpace($HostIp)) {
    throw "Host IP is required. Pass -HostIp or set RUSTDESK_HOST_IP to the LAN address clients should use."
}
if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path "infra\rustdesk-server-oss\docker-compose.yml"
}

$composeDir = Split-Path -Parent $ComposeFile
if (-not (Test-Path $composeDir)) {
    throw "Compose directory does not exist: $composeDir"
}

$dataDir = Join-Path $composeDir "data"
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

$envFile = Join-Path $composeDir ".env"
@(
    "RUSTDESK_HOST_IP=$HostIp"
    "RUSTDESK_RELAY_HOST=$HostIp"
    "RUSTDESK_RELAY_PORT=$RelayPort"
) | Set-Content -Path $envFile -Encoding ASCII

Push-Location $composeDir
try {
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Start-Sleep -Seconds 3

$pubKeyPath = Join-Path $dataDir "id_ed25519.pub"
if (-not (Test-Path $pubKeyPath)) {
    throw "Public key not generated yet: $pubKeyPath"
}

$pubKey = (Get-Content $pubKeyPath -Raw).Trim()
$portReport = foreach ($port in $TcpPorts) {
    [PSCustomObject]@{
        Port = $port
        Open = Test-TcpPort -TargetHost $HostIp -Port $port
    }
}
$clientConfig = @{
    host = $HostIp
    relay = "${HostIp}:$RelayPort"
    api = ""
    key = $pubKey
} | ConvertTo-Json -Compress

Write-Host ""
Write-Host "RustDesk self-hosted server is up."
Write-Host "Host IP: $HostIp"
Write-Host "Relay: ${HostIp}:$RelayPort"
Write-Host "Public key: $pubKey"
Write-Host "Client config json: $clientConfig"
Write-Host ""
Write-Host "Local TCP port check:"
$portReport | Format-Table -AutoSize | Out-String | Write-Host
Write-Host ""
Write-Host "Android/Desktop manual client values:"
Write-Host "  ID Server: $HostIp"
Write-Host "  Relay Server: ${HostIp}:$RelayPort"
Write-Host "  Key: $pubKey"
Write-Host ""
Write-Host "If phone clients still report registration failure:"
Write-Host "  1. Run agent/codex-bridge/scripts/open-rustdesk-selfhosted-firewall.ps1 as Administrator."
Write-Host "  2. Keep mobile 'Use WebSocket' disabled when targeting RustDesk server OSS."
Write-Host "  3. Re-enter the server config and retry the connect icon next to the remote ID field."

$requiredPorts = @(21115, 21116, 21117)
$missingRequiredPorts = $portReport | Where-Object { $_.Port -in $requiredPorts -and -not $_.Open }
if ($missingRequiredPorts) {
    throw "Required self-hosted ports are not reachable on ${HostIp}: $($missingRequiredPorts.Port -join ', ')"
}
