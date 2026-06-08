# =============================================================================
# GCP Cloud Run Deployment Script for Registry Center (PowerShell)
# =============================================================================
# Builds via Cloud Build (source deploy) and deploys to Cloud Run.
# No local Docker required.
#
# Prerequisites:
#   1. Run .\setup.ps1 first to create GCP resources.
#   2. gcloud auth login
#
# Usage:
#   $env:GCP_PROJECT_ID = "my-project"
#   $env:GCP_REGION = "asia-east1"
#   $env:DB_PASSWORD = "your-password"
#   .\scripts\gcp\deploy.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$GCP_PROJECT_ID = $env:GCP_PROJECT_ID
$GCP_REGION     = $env:GCP_REGION
$DB_PASSWORD    = $env:DB_PASSWORD

if (-not $GCP_PROJECT_ID) { Write-Error "Set `$env:GCP_PROJECT_ID first" }
if (-not $GCP_REGION)     { Write-Error "Set `$env:GCP_REGION first" }
if (-not $DB_PASSWORD)    { Write-Error "Set `$env:DB_PASSWORD first" }

$SERVICE_NAME = if ($env:SERVICE_NAME) { $env:SERVICE_NAME } else { "registry-center" }
$CLOUDSQL_INST = if ($env:CLOUDSQL_INSTANCE) { $env:CLOUDSQL_INSTANCE } else { "registry-center-db" }
$CLOUDSQL_CONN = "${GCP_PROJECT_ID}:${GCP_REGION}:${CLOUDSQL_INST}"
$DB_NAME    = if ($env:DB_NAME)    { $env:DB_NAME }    else { "registry_center" }
$DB_USER    = if ($env:DB_USER)    { $env:DB_USER }    else { "registry" }
$DB_MIN     = if ($env:DB_POOL_MIN) { $env:DB_POOL_MIN } else { "2" }
$DB_MAX     = if ($env:DB_POOL_MAX) { $env:DB_POOL_MAX } else { "10" }
$MEMORY     = if ($env:MEMORY)      { $env:MEMORY }      else { "512Mi" }
$CPU        = if ($env:CPU)         { $env:CPU }         else { "1" }
$MAX_INST   = if ($env:MAX_INSTANCES){ $env:MAX_INSTANCES } else { "10" }
$SA_NAME    = if ($env:SERVICE_ACCOUNT) { $env:SERVICE_ACCOUNT } else { "registry-center-sa" }
$SA_EMAIL   = "${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

Write-Host "============================================"
Write-Host " Deploy Registry Center to Cloud Run"
Write-Host " Project: ${GCP_PROJECT_ID}"
Write-Host " Region:  ${GCP_REGION}"
Write-Host "============================================"

gcloud run deploy "${SERVICE_NAME}" `
  --source=. `
  --region="${GCP_REGION}" `
  --platform=managed `
  --allow-unauthenticated `
  --memory="${MEMORY}" `
  --cpu="${CPU}" `
  --max-instances="${MAX_INST}" `
  --concurrency=80 `
  --timeout=300 `
  --port=8080 `
  --service-account="${SA_EMAIL}" `
  --add-cloudsql-instances="${CLOUDSQL_CONN}" `
  --set-env-vars="PERSISTENCE_MODE=postgresql,DB_HOST=/cloudsql/${CLOUDSQL_CONN},DB_PORT=5432,DB_NAME=${DB_NAME},DB_USERNAME=${DB_USER},DB_PASSWORD=${DB_PASSWORD},DB_POOL_MIN=${DB_MIN},DB_POOL_MAX=${DB_MAX},REGISTRY_ENABLE_HTTPS=false,REGISTRY_FORWARDED_ALLOW_IPS=*,REGISTRY_OWNER__VALIDATION__MODE=relaxed" `
  --project="${GCP_PROJECT_ID}"

$SERVICE_URL = gcloud run services describe "${SERVICE_NAME}" --region="${GCP_REGION}" --format="value(status.url)" --project="${GCP_PROJECT_ID}"
Write-Host ""
Write-Host "Deploy done! Service URL: ${SERVICE_URL}"
Write-Host "Test: curl ${SERVICE_URL}/health"
