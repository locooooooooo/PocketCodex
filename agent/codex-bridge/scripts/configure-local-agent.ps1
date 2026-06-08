param(
    [string]$RustDeskExe = "rustdesk",
    [string]$ProjectId = "rustdesk",
    [string]$ProjectPath = "",
    [int]$Port = 17321,
    [string]$CodexCommand = "codex",
    [string]$Executor = "codex",
    [string]$Profile = "",
    [string]$Session = "",
    [switch]$ResumeLast,
    [switch]$DisableConfirmation
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
}

if (-not (Test-Path $ProjectPath)) {
    throw "Project path does not exist: $ProjectPath"
}

$project = [ordered]@{
    id = $ProjectId
    path = $ProjectPath
}
if ($Executor.Trim()) {
    $project.executor = $Executor
}
if ($Profile.Trim()) {
    $project.profile = $Profile
}
if ($ResumeLast) {
    $project.resume_last = $true
} elseif ($Session.Trim()) {
    $project.session = $Session
}

$projectsJson = @([pscustomobject]$project) | ConvertTo-Json -Compress

$requireConfirmation = if ($DisableConfirmation) { "N" } else { "Y" }

$commands = @(
    @("--option", "codex-bridge-enabled", "Y"),
    @("--option", "codex-bridge-port", "$Port"),
    @("--option", "codex-bridge-command", "$CodexCommand"),
    @("--option", "codex-bridge-require-confirmation", "$requireConfirmation"),
    @("--option", "codex-bridge-projects", "$projectsJson")
)

foreach ($args in $commands) {
    Write-Host "$RustDeskExe $($args -join ' ')"
    & $RustDeskExe @args
    if ($LASTEXITCODE -ne 0) {
        throw "RustDesk config command failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "Local agent bridge config written."
Write-Host "Project: $ProjectId -> $ProjectPath"
Write-Host "Executor: $Executor"
if ($Profile.Trim()) {
    Write-Host "Profile: $Profile"
}
if ($ResumeLast) {
    Write-Host "ResumeLast: true"
} elseif ($Session.Trim()) {
    Write-Host "Session: $Session"
}
Write-Host "Port: $Port"
