param(
    [string]$BaseUrl = "http://127.0.0.1:17321",
    [string]$Project = "rustdesk",
    [string]$Prompt = "Analyze the build entry points. Do not modify files.",
    [switch]$RunCodex,
    [switch]$TestConfirmation
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

    $json = $Body | ConvertTo-Json -Depth 8 -Compress
    return Invoke-RestMethod -Method $Method -Uri $uri -Body $json -ContentType "application/json"
}

function New-RequestId {
    return [guid]::NewGuid().ToString()
}

function ConvertTo-RedactedJson {
    param([Parameter(Mandatory = $true)][object]$Value)

    $json = $Value | ConvertTo-Json -Depth 8 -Compress
    return $json -replace '"token":"[^"]*"', '"token":"<redacted>"'
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

Write-Host "[bridge] unknown project should be rejected"
try {
    Invoke-BridgeJson -Method POST -Path "/agent/run" -Body @{
        request_id = New-RequestId
        project = "__missing__"
        prompt = "ping"
    } | Out-Null
    throw "Unknown project was not rejected"
} catch {
    Write-Host "[ok] unknown project rejected: $($_.Exception.Message)"
}

if ($RunCodex) {
    Write-Host "[bridge] read-only codex run project=$Project"
    $requestId = New-RequestId
    $run = Invoke-BridgeJson -Method POST -Path "/agent/run" -Body @{
        request_id = $requestId
        project = $Project
        prompt = $Prompt
    }
    Write-Host "[ok] run status=$($run.status)"
    $run | ConvertTo-Json -Depth 8
    Write-Host "[bridge] task status $requestId"
    $task = Invoke-BridgeJson -Method GET -Path "/agent/tasks/$requestId"
    Write-Host "[ok] task status=$($task.status)"
} else {
    Write-Host "[skip] read-only Codex execution. Add -RunCodex after configuring codex-bridge-projects and Codex login."
}

if ($TestConfirmation) {
    if (-not $RunCodex) {
        Write-Host "[info] -TestConfirmation requires a read-only planning run; enabling -RunCodex behavior for this check."
    }
    Write-Host "[bridge] confirmation request project=$Project"
    $requestId = New-RequestId
    $plan = Invoke-BridgeJson -Method POST -Path "/agent/run" -Body @{
        request_id = $requestId
        project = $Project
        prompt = "Modify README.md by adding a short smoke test note."
    }
    if ($plan.status -ne "needs_confirmation" -or [string]::IsNullOrWhiteSpace($plan.token)) {
        throw "Expected needs_confirmation with token, got: $(ConvertTo-RedactedJson $plan)"
    }
    Write-Host "[ok] confirmation token issued: <redacted>"
    Write-Host "[bridge] cancel pending confirmation"
    $cancel = Invoke-BridgeJson -Method POST -Path "/agent/cancel" -Body @{
        request_id = $requestId
        token = $plan.token
    }
    Write-Host "[ok] cancel status=$($cancel.status)"
    Write-Host "[skip] not calling /agent/confirm from smoke test to avoid workspace-write."
}
