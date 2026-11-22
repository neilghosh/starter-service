<#
.SYNOPSIS
    Idempotent setup for GCP APIs, Artifact Registry, IAM roles, Cloud Build 2nd-gen GitHub connection,
    repository link, and CI/CD triggers (main push auto-deploy + traffic switch, optional PR preview).
#>
[CmdletBinding()]
param(
    [string]$Repo = "neilghosh/starter-service",
    [string]$Project = "swiss-knife-c662b",
    [string]$Region = "us-central1",
    [string]$ServiceName = "starter-service",
    [string]$ArRepo = "starter-service",
    [string]$ConnectionName = "github-connection",
    [switch]$IncludePrPreviewTrigger
)

$ErrorActionPreference = "Stop"

$repoParts = $Repo -split "/"
if ($repoParts.Count -ne 2) {
    throw "Repo must be in 'owner/name' format. Got: $Repo"
}
$ghOwner = $repoParts[0]
$ghRepoName = $repoParts[1]
$linkedRepoId = "$ghOwner-$ghRepoName" -replace "[^a-zA-Z0-9-]", "-"

Write-Host "`n[1/6] Enabling required GCP APIs on $Project..." -ForegroundColor Cyan
& gcloud services enable `
    run.googleapis.com `
    cloudbuild.googleapis.com `
    artifactregistry.googleapis.com `
    secretmanager.googleapis.com `
    --project=$Project

Write-Host "`n[2/6] Ensuring Artifact Registry Docker repository '$ArRepo' in $Region..." -ForegroundColor Cyan
$ErrorActionPreference = "Continue"
& gcloud artifacts repositories describe $ArRepo --project=$Project --location=$Region --format="value(name)" 2>&1 | Out-Null
$arExists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = "Stop"

if (-not $arExists) {
    & gcloud artifacts repositories create $ArRepo `
        --project=$Project `
        --location=$Region `
        --repository-format=docker `
        --description="Docker images for $ServiceName"
} else {
    Write-Host "  Artifact Registry repo '$ArRepo' already exists." -ForegroundColor Green
}

Write-Host "`n[3/6] Granting IAM roles to Cloud Build & Compute service accounts..." -ForegroundColor Cyan
$projectNumber = (& gcloud projects describe $Project --format="value(projectNumber)").Trim()
$cbSa = "serviceAccount:$projectNumber@cloudbuild.gserviceaccount.com"
$computeSa = "serviceAccount:$projectNumber-compute@developer.gserviceaccount.com"
$cbP4Sa = "serviceAccount:service-$projectNumber@gcp-sa-cloudbuild.iam.gserviceaccount.com"

foreach ($member in @($cbSa, $computeSa)) {
    foreach ($role in @("roles/run.admin", "roles/iam.serviceAccountUser", "roles/artifactregistry.writer", "roles/logging.logWriter")) {
        & gcloud projects add-iam-policy-binding $Project `
            --member=$member `
            --role=$role `
            --condition=None `
            --quiet | Out-Null
    }
}
# Cloud Build 2nd-gen connection stores GitHub token in Secret Manager using the Cloud Build service agent
& gcloud projects add-iam-policy-binding $Project `
    --member=$cbP4Sa `
    --role="roles/secretmanager.admin" `
    --condition=None `
    --quiet | Out-Null
Write-Host "  IAM bindings ensured for $cbSa, $computeSa, and $cbP4Sa." -ForegroundColor Green

Write-Host "`n[4/6] Checking Cloud Build 2nd-gen GitHub connection '$ConnectionName' in $Region..." -ForegroundColor Cyan
$ErrorActionPreference = "Continue"
$connStage = (& gcloud builds connections describe $ConnectionName --project=$Project --region=$Region --format="value(installationState.stage)" 2>&1)
$connExists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = "Stop"

if (-not $connExists) {
    Write-Host "  Creating GitHub connection '$ConnectionName'..."
    & gcloud builds connections create github $ConnectionName --project=$Project --region=$Region
    $connStage = (& gcloud builds connections describe $ConnectionName --project=$Project --region=$Region --format="value(installationState.stage)").Trim()
} else {
    $connStage = ($connStage -join "").Trim()
}

if ($connStage -ne "COMPLETE") {
    $actionUri = (& gcloud builds connections describe $ConnectionName --project=$Project --region=$Region --format="value(installationState.actionUri)").Trim()
    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "ONE-TIME ACTION REQUIRED: Authorize Google Cloud Build on GitHub" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "Current connection stage: $connStage"
    Write-Host "Open this URL in your browser and install/authorize the Cloud Build GitHub App:"
    Write-Host "  $actionUri" -ForegroundColor Green
    Write-Host "`nOnce authorized, re-run this script to finish linking '$Repo' and creating triggers."
    exit 0
}
Write-Host "  Connection '$ConnectionName' is COMPLETE." -ForegroundColor Green

Write-Host "`n[5/6] Linking GitHub repository '$Repo' to Cloud Build connection..." -ForegroundColor Cyan
$ErrorActionPreference = "Continue"
& gcloud builds repositories describe $linkedRepoId --connection=$ConnectionName --project=$Project --region=$Region --format="value(name)" 2>&1 | Out-Null
$repoLinked = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = "Stop"

if (-not $repoLinked) {
    & gcloud builds repositories create $linkedRepoId `
        --remote-uri="https://github.com/$Repo.git" `
        --connection=$ConnectionName `
        --project=$Project `
        --region=$Region
} else {
    Write-Host "  Repository '$linkedRepoId' is already linked." -ForegroundColor Green
}

$repoResource = "projects/$Project/locations/$Region/connections/$ConnectionName/repositories/$linkedRepoId"

Write-Host "`n[6/6] Creating Cloud Build triggers..." -ForegroundColor Cyan
$mainTriggerName = "$ServiceName-main-deploy"
$ErrorActionPreference = "Continue"
& gcloud builds triggers describe $mainTriggerName --project=$Project --region=$Region --format="value(name)" 2>&1 | Out-Null
$mainTriggerExists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = "Stop"

if (-not $mainTriggerExists) {
    & gcloud builds triggers create github `
        --name=$mainTriggerName `
        --project=$Project `
        --region=$Region `
        --repository=$repoResource `
        --branch-pattern="^main$" `
        --build-config="cloudbuild.yaml" `
        --substitutions="_REGION=$Region,_AR_REPO=$ArRepo,_SERVICE=$ServiceName"
    Write-Host "  Created main push trigger: $mainTriggerName" -ForegroundColor Green
} else {
    Write-Host "  Main push trigger '$mainTriggerName' already exists." -ForegroundColor Green
}

if ($IncludePrPreviewTrigger) {
    $prTriggerName = "$ServiceName-pr-preview"
    $ErrorActionPreference = "Continue"
    & gcloud builds triggers describe $prTriggerName --project=$Project --region=$Region --format="value(name)" 2>&1 | Out-Null
    $prTriggerExists = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = "Stop"

    if (-not $prTriggerExists) {
        & gcloud builds triggers create github `
            --name=$prTriggerName `
            --project=$Project `
            --region=$Region `
            --repository=$repoResource `
            --pull-request-pattern="^main$" `
            --build-config="cloudbuild-preview.yaml" `
            --substitutions="_REGION=$Region,_AR_REPO=$ArRepo,_SERVICE=$ServiceName,_TAG=pr-preview,_COMMIT_SHA=`$SHORT_SHA"
        Write-Host "  Created PR preview trigger: $prTriggerName" -ForegroundColor Green
    } else {
        Write-Host "  PR preview trigger '$prTriggerName' already exists." -ForegroundColor Green
    }
}

Write-Host "`nCloud Build CI/CD setup complete!" -ForegroundColor Green
