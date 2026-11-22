<#
.SYNOPSIS
    Non-destructive end-to-end connectivity diagnostic for GitHub, GCP, Artifact Registry, Cloud Build, and Cloud Run.
#>
[CmdletBinding()]
param(
    [string]$Repo = "neilghosh/starter-service",
    [string]$Project = "demoneil",
    [string]$Region = "us-central1",
    [string]$ServiceName = "starter-service",
    [string]$ArRepo = "starter-service",
    [string]$ConnectionName = "github-connection"
)

$ErrorActionPreference = "Continue"
$results = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [string]$Category,
        [string]$Name,
        [ValidateSet("PASS", "WARN", "FAIL")][string]$Status,
        [string]$Details,
        [string]$Remediation = ""
    )
    $results.Add([pscustomobject]@{
        Category    = $Category
        Check       = $Name
        Status      = $Status
        Details     = $Details
        Remediation = $Remediation
    })
}

# 1. Local CLI Tools
foreach ($tool in @("git", "gh", "gcloud", "node")) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if ($cmd) {
        Add-Check "Local CLI" $tool "PASS" $cmd.Source
    } else {
        Add-Check "Local CLI" $tool "FAIL" "Not found in PATH" "Install $tool and ensure it is on PATH."
    }
}

$dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
if ($dockerCmd) {
    $dockerVer = & docker version --format '{{.Server.Version}}' 2>&1
    if ($LASTEXITCODE -eq 0) {
        Add-Check "Local CLI" "docker daemon" "PASS" "Server v$($dockerVer -join '')"
    } else {
        Add-Check "Local CLI" "docker daemon" "WARN" "CLI installed, daemon stopped (optional for Cloud Build)" "Start Docker Desktop if you want local container builds."
    }
} else {
    Add-Check "Local CLI" "docker" "WARN" "Not installed (optional when using Cloud Build)" "Install Docker Desktop for local container testing."
}

# 2. GitHub Auth & Repo Connectivity
$ghAuth = & gh auth status 2>&1
if ($LASTEXITCODE -eq 0) {
    $ghUser = (& gh api user --jq ".login" 2>&1) -join ""
    Add-Check "GitHub" "gh auth" "PASS" "Authenticated as $ghUser"
} else {
    Add-Check "GitHub" "gh auth" "FAIL" "Not authenticated" "Run: gh auth login"
}

$ghRepo = & gh repo view $Repo --json nameWithOwner,visibility,defaultBranchRef 2>&1
if ($LASTEXITCODE -eq 0) {
    $repoObj = $ghRepo | ConvertFrom-Json
    Add-Check "GitHub" "repository" "PASS" "$($repoObj.nameWithOwner) ($($repoObj.visibility), default: $($repoObj.defaultBranchRef.name))"
} else {
    Add-Check "GitHub" "repository" "FAIL" "Repo '$Repo' not found or inaccessible" "Run: gh repo create $Repo --public --source=. --remote=origin --push"
}

$gitRemote = & git remote get-url origin 2>&1
if ($LASTEXITCODE -eq 0) {
    $lsRemote = & git ls-remote --heads origin 2>&1
    if ($LASTEXITCODE -eq 0) {
        Add-Check "GitHub" "git remote" "PASS" "$($gitRemote -join '') (reachable)"
    } else {
        Add-Check "GitHub" "git remote" "FAIL" "Remote '$gitRemote' unreachable" "Verify git credentials / gh auth setup-git."
    }
} else {
    Add-Check "GitHub" "git remote" "WARN" "No git 'origin' remote configured in current directory" "Initialize git and add origin remote."
}

$bpCheck = & gh api "repos/$Repo/branches/main/protection" 2>&1
if ($LASTEXITCODE -eq 0) {
    Add-Check "GitHub" "branch protection (main)" "PASS" "Enabled on main"
} else {
    Add-Check "GitHub" "branch protection (main)" "WARN" "Not configured on main" "Run: .\.agents\skills\github-cloudrun-e2e\scripts\setup-branch-protection.ps1 -Repo $Repo"
}

# 3. Google Cloud Auth, Project, APIs
$gcloudAcct = (& gcloud config get-value account 2>&1) -join ""
if ($LASTEXITCODE -eq 0 -and $gcloudAcct -and $gcloudAcct -ne "(unset)") {
    Add-Check "GCP" "gcloud auth" "PASS" $gcloudAcct
} else {
    Add-Check "GCP" "gcloud auth" "FAIL" "No active gcloud account" "Run: gcloud auth login"
}

$projDesc = & gcloud projects describe $Project --format="value(projectNumber)" 2>&1
if ($LASTEXITCODE -eq 0) {
    $projectNumber = ($projDesc | Select-Object -Last 1).Trim()
    Add-Check "GCP" "project access" "PASS" "$Project (#$projectNumber)"
} else {
    Add-Check "GCP" "project access" "FAIL" "Cannot access project '$Project'" "Run: gcloud config set project $Project"
    $projectNumber = $null
}

if ($projectNumber) {
    $enabledApis = (& gcloud services list --enabled --project=$Project --format="value(config.name)" 2>&1)
    $requiredApis = @("run.googleapis.com", "cloudbuild.googleapis.com", "artifactregistry.googleapis.com", "secretmanager.googleapis.com")
    $missingApis = $requiredApis | Where-Object { $enabledApis -notcontains $_ }
    if ($missingApis.Count -eq 0) {
        Add-Check "GCP" "required APIs" "PASS" "All 4 APIs enabled (run, cloudbuild, artifactregistry, secretmanager)"
    } else {
        Add-Check "GCP" "required APIs" "WARN" "Missing: $($missingApis -join ', ')" "Run: gcloud services enable $($missingApis -join ' ') --project=$Project"
    }

    # Artifact Registry
    $arCheck = & gcloud artifacts repositories describe $ArRepo --project=$Project --location=$Region --format="value(format)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Add-Check "GCP" "Artifact Registry" "PASS" "$Region/$ArRepo ($($arCheck -join ''))"
    } else {
        Add-Check "GCP" "Artifact Registry" "WARN" "Repository '$ArRepo' not found in $Region" "Run: setup-cloudbuild-cicd.ps1 to create it."
    }

    # Cloud Run service
    $crUrl = & gcloud run services describe $ServiceName --project=$Project --region=$Region --format="value(status.url)" 2>&1
    if ($LASTEXITCODE -eq 0 -and $crUrl) {
        Add-Check "Cloud Run" "service ($ServiceName)" "PASS" ($crUrl -join "")
    } else {
        Add-Check "Cloud Run" "service ($ServiceName)" "WARN" "Service '$ServiceName' not deployed yet in $Region" "Deploy via Cloud Build or gcloud run deploy."
    }

    # Cloud Build 2nd-gen connection
    $connStage = & gcloud builds connections describe $ConnectionName --project=$Project --region=$Region --format="value(installationState.stage)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $stage = ($connStage -join "").Trim()
        if ($stage -eq "COMPLETE") {
            Add-Check "Cloud Build" "GitHub connection" "PASS" "$ConnectionName ($stage)"
        } else {
            Add-Check "Cloud Build" "GitHub connection" "WARN" "$ConnectionName is $stage" "Complete OAuth in browser via: gcloud builds connections describe $ConnectionName --region=$Region --format='value(installationState.actionUri)'"
        }
    } else {
        Add-Check "Cloud Build" "GitHub connection" "WARN" "Connection '$ConnectionName' not found in $Region" "Run: setup-cloudbuild-cicd.ps1"
    }

    # Cloud Build triggers
    $triggers = & gcloud builds triggers list --project=$Project --region=$Region --format="value(name)" 2>&1
    if ($LASTEXITCODE -eq 0 -and ($triggers | Where-Object { $_ -match $ServiceName })) {
        $matched = ($triggers | Where-Object { $_ -match $ServiceName }) -join ", "
        Add-Check "Cloud Build" "CI/CD triggers" "PASS" $matched
    } else {
        Add-Check "Cloud Build" "CI/CD triggers" "WARN" "No triggers matching '$ServiceName' in $Region" "Run: setup-cloudbuild-cicd.ps1"
    }
}

Write-Host "`n=== End-to-End Connectivity Diagnostic Report ===" -ForegroundColor Cyan
$results | Format-Table -Property Category, Check, Status, Details -AutoSize

$actionItems = $results | Where-Object { $_.Status -ne "PASS" -and $_.Remediation }
if ($actionItems.Count -gt 0) {
    Write-Host "Recommended Actions:" -ForegroundColor Yellow
    foreach ($item in $actionItems) {
        $color = if ($item.Status -eq "FAIL") { "Red" } else { "Yellow" }
        Write-Host "  [$($item.Status)] $($item.Category) / $($item.Check): $($item.Remediation)" -ForegroundColor $color
    }
}

$failCount = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
if ($failCount -gt 0) {
    exit 1
}
exit 0
