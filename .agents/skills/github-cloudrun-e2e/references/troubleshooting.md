# Troubleshooting Guide: GitHub + Cloud Build + Cloud Run

## 1. Docker Desktop Daemon Not Running
**Symptom**: `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`
**Impact**: Non-blocking for local Node.js development and remote Cloud Build deployments.
**Fix**: Only needed if you want to run `docker build` / `docker run` locally — launch Docker Desktop and wait for the engine to report ready.

## 2. Cloud Build 2nd-Gen GitHub Connection Pending OAuth
**Symptom**: `installationState.stage` is `PENDING_USER_OAUTH` or `PENDING_INSTALL_APP`.
**Fix**:
1. Run:
   ```powershell
   gcloud builds connections describe github-connection --region=us-central1 --format="value(installationState.actionUri)"
   ```
2. Open the printed URL in a browser, authorize Google Cloud Build, and select the target repository (`neilghosh/starter-service`).
3. Re-run `setup-cloudbuild-cicd.ps1`.

## 3. Cloud Build Permission Denied Deploying to Cloud Run
**Symptom**: `PERMISSION_DENIED: Permission 'iam.serviceAccounts.actAs' denied on service account ...` or `run.services.update denied`.
**Fix**: Grant the Cloud Build service account (`<PROJECT_NUMBER>@cloudbuild.gserviceaccount.com`) and the Compute Engine default SA (if Cloud Build runs with it in newer projects) the required roles:
- `roles/run.admin`
- `roles/iam.serviceAccountUser`
- `roles/artifactregistry.writer`

## 4. Branch Protection Fails with 403 on Private Repo
**Symptom**: `HTTP 403: Upgrade to GitHub Pro or make this repository public to enable this feature.`
**Fix**: Either make the repository public (`gh repo edit <owner>/<repo> --visibility public --accept-visibility-change-consequences`) or upgrade to GitHub Pro/Team/Enterprise.

## 5. Invalid Cloud Run Revision Tag Name
**Symptom**: `Invalid tag: must match ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`
**Fix**: Cloud Run revision tags must be lowercase ASCII letters, digits, or hyphens, start and end with an alphanumeric character, and be at most 63 characters. `deploy-branch-preview.ps1` automatically sanitizes branch names (e.g., `Feat/My_Branch` -> `feat-my-branch`).

## 6. Cloud Build Trigger Fails When Submitting Manually Without `SHORT_SHA`
**Symptom**: Empty image tag `...starter-service:` during manual `gcloud builds submit`.
**Fix**: Pass `--substitutions="SHORT_SHA=$(git rev-parse --short HEAD)"` when running `cloudbuild.yaml` manually, or let the GitHub push trigger populate `$SHORT_SHA` automatically.
