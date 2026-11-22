---
name: github-cloudrun-e2e
description: >-
  End-to-end runbook and diagnostic toolkit for verifying local system connectivity
  with GitHub and Google Cloud Run, building and testing locally with a web browser,
  configuring GitHub branch protection on main, setting up Cloud Build 2nd-gen CI/CD
  that deploys new versions and switches traffic on PR merge, and deploying feature
  branches to non-default Cloud Run tagged preview revisions. Use this skill when
  setting up, checking, debugging, or operating GitHub-to-Cloud-Run deployments.
---

# GitHub to Cloud Run End-to-End Connectivity & CI/CD

Follow these steps in order to verify system connectivity, test locally in a browser, configure GitHub branch protection, set up automated Cloud Build CI/CD on `main`, and deploy feature branches to non-default Cloud Run preview URLs.

## Prerequisites & Defaults

Default parameters used across scripts (override with CLI flags as needed):
- **GitHub Repo**: `neilghosh/starter-service`
- **GCP Project**: `swiss-knife-c662b`
- **GCP Region**: `us-central1`
- **Cloud Run Service / Artifact Registry Repo**: `starter-service`

---

## Step 1: Check System & Cloud Connectivity

Run the non-destructive diagnostic script first to inspect CLI tools, GitHub auth/repo reachability, GCP project/APIs/IAM, Artifact Registry, Cloud Run, and Cloud Build connections:

```powershell
.\.agents\skills\github-cloudrun-e2e\scripts\check-connectivity.ps1 `
  -Repo neilghosh/starter-service `
  -Project swiss-knife-c662b `
  -Region us-central1 `
  -ServiceName starter-service
```

- Resolve any `[FAIL]` items using the remediation commands printed by the script (or see [troubleshooting.md](./references/troubleshooting.md)).
- Docker Desktop being stopped is reported as `[WARN]` — it is optional because local Node runs natively and Cloud Build builds containers remotely in GCP.

---

## Step 2: Build & Test Locally with a Web Browser

1. Run unit tests:
   ```powershell
   npm test
   ```
2. Start the local server:
   ```powershell
   npm start
   ```
3. Verify in a web browser:
   - Open `http://localhost:8080` and confirm the dashboard renders with a **healthy** badge and live JSON output.
   - Verify `http://localhost:8080/health` returns HTTP `200` with `"status": "ok"`:
     ```powershell
     Invoke-RestMethod http://localhost:8080/health
     ```
4. *(Optional)* If Docker Desktop is running, verify the container locally:
   ```powershell
   docker build -t starter-service:local .
   docker run --rm -p 8080:8080 starter-service:local
   ```

---

## Step 3: Initialize GitHub Repo & Configure Branch Protection

1. Initialize Git, commit, and create the GitHub repository (if not already linked):
   ```powershell
   git init -b main
   git add .
   git commit -m "Initial starter-service and E2E Cloud Run skill"
   gh repo create neilghosh/starter-service --public --source=. --remote=origin --push
   ```
   > Note: GitHub Free supports branch protection on **public** repositories (private repos require GitHub Pro/Team/Enterprise).

2. Apply branch protection to `main` (requires PRs before merging, blocks force pushes and deletions):
   ```powershell
   .\.agents\skills\github-cloudrun-e2e\scripts\setup-branch-protection.ps1 `
     -Repo neilghosh/starter-service `
     -Branch main `
     -RequiredApprovals 0
   ```
   - Set `-RequiredApprovals 1` for multi-developer teams.
   - Pass `-RequiredStatusChecks @("starter-service-main-deploy")` once your Cloud Build trigger has run at least once.

---

## Step 4: Set Up Cloud Build CI/CD (Auto-Deploy & Traffic Switch on PR Merge)

Run the idempotent CI/CD setup script to enable GCP APIs, create the Artifact Registry repo, grant Cloud Build IAM roles, create a Cloud Build 2nd-gen GitHub connection, link the repo, and create the `main` push trigger:

```powershell
.\.agents\skills\github-cloudrun-e2e\scripts\setup-cloudbuild-cicd.ps1 `
  -Repo neilghosh/starter-service `
  -Project swiss-knife-c662b `
  -Region us-central1 `
  -ServiceName starter-service `
  -ConnectionName github-connection
```

- **One-Time OAuth Step**: If the 2nd-gen GitHub connection is newly created, the script prints a GCP Console OAuth URL (`actionUri`) and exits cleanly. Open that URL in your browser, install/authorize the Google Cloud Build GitHub App on your account/repo, and then re-run the same script to finish linking the repo and creating the triggers.
- When a PR is merged to `main`, Cloud Build automatically executes `cloudbuild.yaml`:
  1. Runs `npm test`
  2. Builds & pushes the Docker image tagged with `$SHORT_SHA` and `latest`
  3. Deploys a new Cloud Run revision with `--no-traffic`
  4. Runs `gcloud run services update-traffic starter-service --region=us-central1 --to-latest` to switch 100% traffic to the new revision.

### Manual Initial Cloud Run Deploy (Optional / Before First PR Merge)

To deploy immediately from your local checkout without waiting for a GitHub push:

```powershell
$sha = (git rev-parse --short HEAD)
gcloud builds submit --project=swiss-knife-c662b --region=us-central1 `
  --config=cloudbuild.yaml `
  --substitutions="_REGION=us-central1,_AR_REPO=starter-service,_SERVICE=starter-service,SHORT_SHA=$sha"
```

Verify the live service URL:
```powershell
$url = gcloud run services describe starter-service --project=swiss-knife-c662b --region=us-central1 --format="value(status.url)"
Invoke-RestMethod "$url/health"
```

---

## Step 5: Deploy from a Feature Branch into Non-Default Cloud Run (Tagged Preview)

To test changes from any non-`main` branch on Cloud Run **without affecting production traffic**, deploy a tagged revision (`--no-traffic --tag <branch-slug>`):

1. Create and switch to a feature branch:
   ```powershell
   git checkout -b feat/my-change
   ```
2. Deploy the branch as a tagged preview revision:
   ```powershell
   .\.agents\skills\github-cloudrun-e2e\scripts\deploy-branch-preview.ps1 `
     -Project swiss-knife-c662b `
     -Region us-central1 `
     -ServiceName starter-service
   ```
3. The script sanitizes the branch name (e.g., `feat/my-change` -> `feat-my-change`), builds via `cloudbuild-preview.yaml`, deploys with `--no-traffic --tag feat-my-change`, and prints the dedicated preview URL:
   `https://feat-my-change---starter-service-<hash>-uc.a.run.app`
4. Verify in your browser that:
   - The preview URL serves your branch revision (`deployTag: "feat-my-change"`).
   - The default production URL still serves 100% traffic on the `main` revision.

---

## Step 6: End-to-End Verification Checklist

1. Open a Pull Request from your feature branch to `main`:
   ```powershell
   git push -u origin feat/my-change
   gh pr create --fill
   ```
2. Confirm branch protection requires a PR (direct pushes to `main` are blocked).
3. Merge the PR (`gh pr merge --squash`).
4. Watch the triggered Cloud Build run:
   ```powershell
   gcloud builds list --project=swiss-knife-c662b --region=us-central1 --limit=5
   ```
5. Confirm Cloud Run traffic switched to the newly built revision:
   ```powershell
   gcloud run services describe starter-service --project=swiss-knife-c662b --region=us-central1 --format="yaml(status.traffic)"
   ```

For errors and fixes, consult [references/troubleshooting.md](./references/troubleshooting.md).
