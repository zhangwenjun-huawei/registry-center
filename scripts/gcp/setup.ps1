# =============================================================================
# GCP One-Time Setup Script for Registry Center (PowerShell)
# =============================================================================
# This script sets up all required GCP resources:
#   - Artifact Registry repository (for Docker images)
#   - Cloud SQL PostgreSQL instance
#   - Cloud SQL database
#   - Secret Manager secrets for DB credentials
#   - Service account with required roles
#
# Usage:
#   $env:GCP_PROJECT_ID = "my-project"
#   $env:GCP_REGION = "asia-east1"
#   $env:DB_PASSWORD = "your-secure-password"
#   .\scripts\gcp\setup.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$GCP_PROJECT_ID = $env:GCP_PROJECT_ID
$GCP_REGION     = $env:GCP_REGION
$DB_PASSWORD    = $env:DB_PASSWORD

if (-not $GCP_PROJECT_ID) { Write-Error "Set `$env:GCP_PROJECT_ID first" }
if (-not $GCP_REGION)     { Write-Error "Set `$env:GCP_REGION first" }
if (-not $DB_PASSWORD)    { Write-Error "Set `$env:DB_PASSWORD first" }

$SERVICE_NAME     = if ($env:SERVICE_NAME)     { $env:SERVICE_NAME }     else { "registry-center" }
$ARTIFACT_REPO    = if ($env:ARTIFACT_REPO)    { $env:ARTIFACT_REPO }    else { "registry-center" }
$CLOUDSQL_INST    = if ($env:CLOUDSQL_INSTANCE){ $env:CLOUDSQL_INSTANCE } else { "registry-center-db" }
$DB_NAME          = if ($env:DB_NAME)          { $env:DB_NAME }          else { "registry_center" }
$DB_USER          = if ($env:DB_USER)          { $env:DB_USER }          else { "registry" }
$DB_TIER          = if ($env:DB_TIER)          { $env:DB_TIER }          else { "db-f1-micro" }
$DB_DISK_SIZE     = if ($env:DB_DISK_SIZE)     { $env:DB_DISK_SIZE }     else { "10" }
$SERVICE_ACCOUNT  = if ($env:SERVICE_ACCOUNT)  { $env:SERVICE_ACCOUNT }  else { "registry-center-sa" }
$SA_EMAIL         = "${SERVICE_ACCOUNT}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
$SECRET_ID        = "${SERVICE_NAME}-db-password"

Write-Host "============================================"
Write-Host " GCP Setup for Registry Center"
Write-Host " Project: ${GCP_PROJECT_ID}"
Write-Host " Region:  ${GCP_REGION}"
Write-Host "============================================"

# ── 1. Enable required APIs ────────────────────────────────────────────────
Write-Host ""
Write-Host "[1/7] Enabling required GCP APIs..."
gcloud services enable artifactregistry.googleapis.com sqladmin.googleapis.com run.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com --project="${GCP_PROJECT_ID}"

# ── 2. Create Artifact Registry ───────────────────────────────────────────
Write-Host ""
Write-Host "[2/7] Creating Artifact Registry repository..."
$existingRepo = gcloud artifacts repositories list --location="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --format="value(name)" 2>$null | Select-String -Pattern "^${ARTIFACT_REPO}$" -SimpleMatch
if ($existingRepo) {
    Write-Host "  Artifact Registry '${ARTIFACT_REPO}' already exists."
} else {
    gcloud artifacts repositories create "${ARTIFACT_REPO}" --repository-format=docker --location="${GCP_REGION}" --description="Registry Center Docker images" --project="${GCP_PROJECT_ID}"
}

# ── 3. Create Cloud SQL PostgreSQL instance ───────────────────────────────
Write-Host ""
Write-Host "[3/7] Creating Cloud SQL PostgreSQL instance..."
$sqlCheck = gcloud sql instances describe "${CLOUDSQL_INST}" --project="${GCP_PROJECT_ID}" 2>$null
if ($sqlCheck) {
    Write-Host "  Cloud SQL instance '${CLOUDSQL_INST}' already exists."
} else {
    gcloud sql instances create "${CLOUDSQL_INST}" --database-version=POSTGRES_15 --tier="${DB_TIER}" --region="${GCP_REGION}" --storage-size="${DB_DISK_SIZE}" --storage-type=SSD --project="${GCP_PROJECT_ID}"
    Write-Host "  Cloud SQL instance created. This may take a few minutes..."
}

# ── 4. Create database ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/7] Creating database '${DB_NAME}'..."
$dbCheck = gcloud sql databases describe "${DB_NAME}" --instance="${CLOUDSQL_INST}" --project="${GCP_PROJECT_ID}" 2>$null
if ($dbCheck) {
    Write-Host "  Database '${DB_NAME}' already exists."
} else {
    gcloud sql databases create "${DB_NAME}" --instance="${CLOUDSQL_INST}" --project="${GCP_PROJECT_ID}"
}

# ── 5. Create database user ────────────────────────────────────────────────
Write-Host ""
Write-Host "[5/7] Creating database user '${DB_USER}'..."
$userCheck = gcloud sql users list --instance="${CLOUDSQL_INST}" --project="${GCP_PROJECT_ID}" --format="value(name)" 2>$null | Select-String -Pattern "^${DB_USER}$" -SimpleMatch
if ($userCheck) {
    Write-Host "  User '${DB_USER}' already exists."
} else {
    gcloud sql users create "${DB_USER}" --instance="${CLOUDSQL_INST}" --password="${DB_PASSWORD}" --project="${GCP_PROJECT_ID}"
}

# ── 6. Store DB password in Secret Manager ─────────────────────────────────
Write-Host ""
Write-Host "[6/7] Storing DB credentials in Secret Manager..."
$secretCheck = gcloud secrets describe "${SECRET_ID}" --project="${GCP_PROJECT_ID}" 2>$null
if ($secretCheck) {
    Write-Host "  Secret '${SECRET_ID}' already exists, updating..."
    [System.Text.Encoding]::UTF8.GetBytes($DB_PASSWORD) | gcloud secrets versions add "${SECRET_ID}" --data-file=- --project="${GCP_PROJECT_ID}"
} else {
    [System.Text.Encoding]::UTF8.GetBytes($DB_PASSWORD) | gcloud secrets create "${SECRET_ID}" --data-file=- --replication-policy="automatic" --project="${GCP_PROJECT_ID}"
}

# ── 7. Create service account with required roles ──────────────────────────
Write-Host ""
Write-Host "[7/7] Creating service account..."
$saCheck = gcloud iam service-accounts describe "${SA_EMAIL}" --project="${GCP_PROJECT_ID}" 2>$null
if ($saCheck) {
    Write-Host "  Service account '${SERVICE_ACCOUNT}' already exists."
} else {
    gcloud iam service-accounts create "${SERVICE_ACCOUNT}" --display-name="Registry Center Service Account" --project="${GCP_PROJECT_ID}"
}

gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" --member="serviceAccount:${SA_EMAIL}" --role="roles/cloudsql.client" --condition=None 2>$null
gcloud secrets add-iam-policy-binding "${SECRET_ID}" --member="serviceAccount:${SA_EMAIL}" --role="roles/secretmanager.secretAccessor" --project="${GCP_PROJECT_ID}" 2>$null

Write-Host ""
Write-Host "============================================"
Write-Host " Setup Complete!"
Write-Host "============================================"
Write-Host ""
Write-Host "Summary:"
Write-Host "  Artifact Registry: ${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${ARTIFACT_REPO}"
Write-Host "  Cloud SQL instance: ${CLOUDSQL_INST}"
Write-Host "  Database:           ${DB_NAME}"
Write-Host "  Database user:      ${DB_USER}"
Write-Host "  Secret Manager:     ${SECRET_ID}"
Write-Host "  Service account:    ${SA_EMAIL}"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  Run deploy:"
Write-Host "    `$env:GCP_PROJECT_ID='${GCP_PROJECT_ID}'"
Write-Host "    `$env:GCP_REGION='${GCP_REGION}'"
Write-Host "    `$env:DB_PASSWORD='(your password)'"
Write-Host "    .\scripts\gcp\deploy.ps1"
