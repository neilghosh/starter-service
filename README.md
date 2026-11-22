# starter-service

Minimal Node.js web service bundled with an end-to-end **GitHub + Cloud Build + Cloud Run** Antigravity Skill.

## Workspace Skill & Runbook

See [`.agents/skills/github-cloudrun-e2e/SKILL.md`](./.agents/skills/github-cloudrun-e2e/SKILL.md) for the complete operational guide covering:

1. System & connectivity diagnostics (`check-connectivity.ps1`)
2. Local build, unit tests, and web browser verification
3. GitHub repo creation & `main` branch protection (`setup-branch-protection.ps1`)
4. Cloud Run deployment & Cloud Build 2nd-gen CI/CD with auto-deploy and traffic switching on PR merge (`setup-cloudbuild-cicd.ps1`)
5. Deploying feature branches to non-default Cloud Run tagged preview revisions (`deploy-branch-preview.ps1`)

## Local Quickstart

```powershell
npm test
npm start
# Open http://localhost:8080 and http://localhost:8080/health
```
