param(
    [string]$RulePrefix = "RustDesk SelfHosted",
    [int[]]$TcpPorts = @(21115, 21116, 21117, 21118, 21119),
    [int[]]$UdpPorts = @(21116)
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-FirewallRule {
    param(
        [string]$DisplayName,
        [string]$Protocol,
        [string]$Ports
    )

    $existing = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Remove-NetFirewallRule | Out-Null
    }

    New-NetFirewallRule `
        -DisplayName $DisplayName `
        -Direction Inbound `
        -Action Allow `
        -Enabled True `
        -Profile Any `
        -Protocol $Protocol `
        -LocalPort $Ports | Out-Null
}

if (-not (Test-IsAdministrator)) {
    throw "Administrator privileges are required. Re-run this script from an elevated PowerShell window."
}

$tcpPortList = ($TcpPorts | Sort-Object -Unique) -join ","
$udpPortList = ($UdpPorts | Sort-Object -Unique) -join ","

if ($tcpPortList) {
    Set-FirewallRule -DisplayName "$RulePrefix TCP" -Protocol TCP -Ports $tcpPortList
}

if ($udpPortList) {
    Set-FirewallRule -DisplayName "$RulePrefix UDP" -Protocol UDP -Ports $udpPortList
}

Write-Host "Firewall rules updated."
Write-Host "  TCP: $tcpPortList"
Write-Host "  UDP: $udpPortList"
