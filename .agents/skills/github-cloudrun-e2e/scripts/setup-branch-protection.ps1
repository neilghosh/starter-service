<#
.SYNOPSIS
    Configures GitHub branch protection on main (or specified branch) using GitHub CLI (gh api).
#>
[CmdletBinding()]
param(
    [string]$Repo = "neilghosh/starter-service",
    [string]$Branch = "main",
    [int]$RequiredApprovals = 0,
    [string[]]$RequiredStatusChecks = @(),
    [switch]$EnforceAdmins
)

$ErrorActionPreference = "Stop"

Write-Host "Configuring branch protection on $Repo ($Branch)..." -ForegroundColor Cyan

$statusChecksPayload = if ($RequiredStatusChecks.Count -gt 0) {
    @{
        strict   = $true
        contexts = $RequiredStatusChecks
    }
} else {
    $null
}

$payload = @{
    required_status_checks        = $statusChecksPayload
    enforce_admins                = [bool]$EnforceAdmins
    required_pull_request_reviews = @{
        dismiss_stale_reviews           = $true
        require_code_owner_reviews      = $false
        required_approving_review_count = $RequiredApprovals
    }
    restrictions                  = $null
    required_conversation_resolution = $true
    allow_force_pushes            = $false
    allow_deletions               = $false
}

$json = $payload | ConvertTo-Json -Depth 6
$result = $json | & gh api -X PUT "repos/$Repo/branches/$Branch/protection" -H "Accept: application/vnd.github+json" --input - 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to apply branch protection on $Repo ($Branch):`n$result"
    exit 1
}

Write-Host "Branch protection enabled on $Repo ($Branch)!" -ForegroundColor Green
Write-Host "  - Pull Request required: Yes (approvals required: $RequiredApprovals)"
Write-Host "  - Dismiss stale reviews: Yes"
Write-Host "  - Require conversation resolution: Yes"
Write-Host "  - Force pushes & deletions: Blocked"
if ($RequiredStatusChecks.Count -gt 0) {
    Write-Host "  - Required status checks: $($RequiredStatusChecks -join ', ')"
}
