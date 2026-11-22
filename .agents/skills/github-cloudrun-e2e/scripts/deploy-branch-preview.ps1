<#
.SYNOPSIS
    Deploys the current (or specified) non-main git branch to a tagged Cloud Run preview revision
    with --no-traffic so production traffic on `main` is unaffected.
#>
[CmdletBinding()]
param(
    [string]$Project = "demoneil",
    [string]$Region = "us-central1",
    [string]$ServiceName = "starter-service",
    [string]$ArRepo = "starter-service",
    [string]$Branch = ""
)

$ErrorActionPreference = "Stop"

if (-not $Branch) {
    $Branch = (& git rev-parse --abbrev-ref HEAD).Trim()
}

if ($Branch -eq "main" -or $Branch -eq "master" -or $Branch -eq "HEAD") {
    throw "Refusing to deploy '$Branch' as a non-default preview revision. Checkout a feature branch first (e.g., git checkout -b feat/my-test)."
}

# Sanitize branch name into valid Cloud Run tag: lowercase [a-z0-9-], max 63 chars, no leading/trailing hyphen
$tag = $Branch.ToLower() -replace "[^a-z0-9]+", "-"
$tag = $tag.Trim("-")
if ($tag.Length -gt 63) {
    $tag = $tag.Substring(0, 63).Trim("-")
}
if (-not $tag) {
    throw "Could not derive a valid Cloud Run tag from branch '$Branch'."
}

$shortSha = (& git rev-parse --short HEAD).Trim()
if (-not $shortSha) { $shortSha = "manual" }

Write-Host "Deploying branch '$Branch' (SHA: $shortSha) to Cloud Run preview tag '$tag'..." -ForegroundColor Cyan
Write-Host "  Project : $Project"
Write-Host "  Region  : $Region"
Write-Host "  Service : $ServiceName (--no-traffic --tag=$tag)"

& gcloud builds submit `
    --project=$Project `
    --region=$Region `
    --config="cloudbuild-preview.yaml" `
    --substitutions="_REGION=$Region,_AR_REPO=$ArRepo,_SERVICE=$ServiceName,_TAG=$tag,_COMMIT_SHA=$shortSha"

if ($LASTEXITCODE -ne 0) {
    throw "Cloud Build preview deployment failed."
}

Write-Host "`nFetching preview URL and traffic split..." -ForegroundColor Cyan
$trafficJson = & gcloud run services describe $ServiceName --project=$Project --region=$Region --format="json(status.url,status.traffic)"
$svc = $trafficJson | ConvertFrom-Json
$previewEntry = $svc.status.traffic | Where-Object { $_.tag -eq $tag } | Select-Object -First 1

Write-Host "`n=== Branch Preview Deployment Complete ===" -ForegroundColor Green
Write-Host "Production URL (unchanged) : $($svc.status.url)"
if ($previewEntry -and $previewEntry.url) {
    Write-Host "Branch Preview URL         : $($previewEntry.url)" -ForegroundColor Yellow
    Write-Host "Preview Revision           : $($previewEntry.revisionName) (traffic: $($previewEntry.percent)%)"
} else {
    Write-Host "Tagged revision deployed with tag '$tag'. Inspect via: gcloud run services describe $ServiceName --region=$Region"
}
