param(
    [string]$BaseUrl = "http://127.0.0.1:17321",
    [string]$Project = "rustdesk",
    [string]$Prompt = "只回复 ok",
    [switch]$SkipRunProbe,
    [switch]$SkipSessionProbe
)

$ErrorActionPreference = "Stop"

function Invoke-BridgeJson {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body
    )

    $uri = "$BaseUrl$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri
    }

    $json = $Body | ConvertTo-Json -Depth 10 -Compress
    return Invoke-RestMethod -Method $Method -Uri $uri -Body $json -ContentType "application/json"
}

function New-RequestId {
    return [guid]::NewGuid().ToString()
}

function Measure-JsonLength {
    param([Parameter(Mandatory = $true)][object]$Value)
    return (($Value | ConvertTo-Json -Depth 10 -Compress).Length)
}

Write-Host "[bridge] health $BaseUrl/health"
$health = Invoke-BridgeJson -Method GET -Path "/health"
if ($health.status -ne "ok") {
    throw "Unexpected health response: $($health | ConvertTo-Json -Compress)"
}
Write-Host "[ok] health"

Write-Host "[bridge] config"
$config = Invoke-BridgeJson -Method GET -Path "/agent/config"
Write-Host "[ok] config projects=$($config.projects.Count) enabled=$($config.enabled) requireConfirmation=$($config.require_confirmation)"
if ($config.errors.Count -gt 0) {
    Write-Host "[warn] config errors:"
    $config.errors | ForEach-Object { Write-Host "  - $_" }
}

if (-not $SkipRunProbe) {
    Write-Host "[bridge] run read-only probe project=$Project"
    $requestId = New-RequestId
    $run = Invoke-BridgeJson -Method POST -Path "/agent/run" -Body @{
        request_id = $requestId
        project = $Project
        prompt = $Prompt
        mode = "read-only"
        require_confirmation = $false
    }
    Write-Host "[ok] run status=$($run.status)"
}

if (-not $SkipSessionProbe) {
    Write-Host "[bridge] direct sessions catalog"
    $directSessions = Invoke-BridgeJson -Method GET -Path "/agent/sessions"
    $directCount = @($directSessions).Count
    Write-Host "[ok] direct sessions count=$directCount"

    Write-Host "[bridge] remote list_sessions envelope probe project=$Project"
    $requestId = New-RequestId
    $response = Invoke-BridgeJson -Method POST -Path "/agent/run" -Body @{
        request_id = $requestId
        project = $Project
        prompt = (@{
                kind = "list_sessions"
                action = "list_sessions"
                conversation_id = "sessions-probe"
            } | ConvertTo-Json -Compress)
        mode = "read-only"
        require_confirmation = $false
    }

    $detail = $null
    if (-not [string]::IsNullOrWhiteSpace($response.detail_json)) {
        $detail = $response.detail_json | ConvertFrom-Json
    }
    if ($null -eq $detail) {
        throw "Remote list_sessions did not return detail_json."
    }

    $items = @($detail.items)
    $detailBytes = Measure-JsonLength $detail
    Write-Host "[ok] remote sessions count=$($items.Count) detail_json_bytes=$detailBytes"

    if ($directCount -gt 0 -and $items.Count -eq 0) {
        Write-Warning "Bridge has local sessions but remote envelope returned zero items. Check mobile route/UI event application."
    }

    if ($directCount -gt $items.Count) {
        Write-Host "[info] remote catalog is intentionally capped for mobile delivery."
    }
}

Write-Host ""
Write-Host "Agent Dashboard sessions check complete."
