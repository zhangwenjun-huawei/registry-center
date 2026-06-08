#!/bin/bash
# =============================================================================
# GCP One-Time Setup Script for Registry Center
# =============================================================================
# This script sets up all required GCP resources for the first time:
#   - Artifact Registry repository (for Docker images)
#   - Cloud SQL PostgreSQL instance
#   - Cloud SQL database
#   - Secret Manager secrets for DB credentials
#   - Service account with required roles
#
# Usage:
#   export GCP_PROJECT_ID="my-project"
#   export GCP_REGION="asia-east1"
#   export DB_PASSWORD="your-secure-password"
#   bash scripts/gcp/setup.sh
# =============================================================================

set -e

# ── Configuration ──────────────────────────────────────────────────────────
GCP_PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID environment variable}"
GCP_REGION="${GCP_REGION:?Set GCP_REGION environment variable (e.g. asia-east1)}"
SERVICE_NAME="${SERVICE_NAME:-registry-center}"
ARTIFACT_REPO="${ARTIFACT_REPO:-registry-center}"
CLOUDSQL_INSTANCE="${CLOUDSQL_INSTANCE:-registry-center-db}"
DB_NAME="${DB_NAME:-registry_center}"
DB_USER="${DB_USER:-registry}"
DB_PASSWORD="${DB_PASSWORD:?Set DB_PASSWORD environment variable}"
DB_TIER="${DB_TIER:-db-f1-micro}"
DB_DISK_SIZE="${DB_DISK_SIZE:-10}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-registry-center-sa}"

echo "============================================"
echo " GCP Setup for Registry Center"
echo " Project: ${GCP_PROJECT_ID}"
echo " Region:  ${GCP_REGION}"
echo "============================================"

# ── 1. Enable required APIs ────────────────────────────────────────────────
echo ""
echo "[1/7] Enabling required GCP APIs..."
gcloud services enable \
  artifactregistry.googleapis.com \
  sqladmin.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  --project="${GCP_PROJECT_ID}"

# ── 2. Create Artifact Registry ───────────────────────────────────────────
echo ""
echo "[2/7] Creating Artifact Registry repository..."
gcloud artifacts repositories list \
  --location="${GCP_REGION}" \
  --project="${GCP_PROJECT_ID}" \
  --format="value(name)" | grep -q "^${ARTIFACT_REPO}$" 2>/dev/null && \
  echo "  Artifact Registry '${ARTIFACT_REPO}' already exists." || \
  gcloud artifacts repositories create "${ARTIFACT_REPO}" \
    --repository-format=docker \
    --location="${GCP_REGION}" \
    --description="Registry Center Docker images" \
    --project="${GCP_PROJECT_ID}"

# ── 3. Create Cloud SQL PostgreSQL instance ───────────────────────────────
echo ""
echo "[3/7] Creating Cloud SQL PostgreSQL instance..."
if gcloud sql instances describe "${CLOUDSQL_INSTANCE}" \
    --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  echo "  Cloud SQL instance '${CLOUDSQL_INSTANCE}' already exists."
else
  gcloud sql instances create "${CLOUDSQL_INSTANCE}" \
    --database-version=POSTGRES_15 \
    --tier="${DB_TIER}" \
    --region="${GCP_REGION}" \
    --storage-size="${DB_DISK_SIZE}" \
    --storage-type=SSD \
    --project="${GCP_PROJECT_ID}"
  echo "  Cloud SQL instance created. This may take a few minutes..."
fi

# ── 4. Create database ─────────────────────────────────────────────────────
echo ""
echo "[4/7] Creating database '${DB_NAME}'..."
if gcloud sql databases describe "${DB_NAME}" \
    --instance="${CLOUDSQL_INSTANCE}" \
    --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  echo "  Database '${DB_NAME}' already exists."
else
  gcloud sql databases create "${DB_NAME}" \
    --instance="${CLOUDSQL_INSTANCE}" \
    --project="${GCP_PROJECT_ID}"
fi

# ── 5. Create database user ────────────────────────────────────────────────
echo ""
echo "[5/7] Creating database user '${DB_USER}'..."
if gcloud sql users list \
    --instance="${CLOUDSQL_INSTANCE}" \
    --project="${GCP_PROJECT_ID}" \
    --format="value(name)" | grep -q "^${DB_USER}$"; then
  echo "  User '${DB_USER}' already exists."
else
  gcloud sql users create "${DB_USER}" \
    --instance="${CLOUDSQL_INSTANCE}" \
    --password="${DB_PASSWORD}" \
    --project="${GCP_PROJECT_ID}"
fi

# ── 6. Store DB password in Secret Manager ─────────────────────────────────
echo ""
echo "[6/7] Storing DB credentials in Secret Manager..."
SECRET_ID="${SERVICE_NAME}-db-password"
if gcloud secrets describe "${SECRET_ID}" \
    --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  echo "  Secret '${SECRET_ID}' already exists, updating..."
  echo -n "${DB_PASSWORD}" | gcloud secrets versions add "${SECRET_ID}" \
    --data-file=- --project="${GCP_PROJECT_ID}"
else
  echo -n "${DB_PASSWORD}" | gcloud secrets create "${SECRET_ID}" \
    --data-file=- \
    --replication-policy="automatic" \
    --project="${GCP_PROJECT_ID}"
fi

# ── 7. Create service account with required roles ──────────────────────────
echo ""
echo "[7/7] Creating service account..."
SA_EMAIL="${SERVICE_ACCOUNT}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "${SA_EMAIL}" \
    --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  echo "  Service account '${SERVICE_ACCOUNT}' already exists."
else
  gcloud iam service-accounts create "${SERVICE_ACCOUNT}" \
    --display-name="Registry Center Service Account" \
    --project="${GCP_PROJECT_ID}"
fi

# Grant Cloud SQL client role to the service account
gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/cloudsql.client" \
  --condition=None >/dev/null 2>&1 || true

# Grant Secret Manager accessor role
gcloud secrets add-iam-policy-binding "${SECRET_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --project="${GCP_PROJECT_ID}" >/dev/null 2>&1 || true

echo ""
echo "============================================"
echo " Setup Complete!"
echo "============================================"
echo ""
echo "Summary:"
echo "  Artifact Registry: ${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${ARTIFACT_REPO}"
echo "  Cloud SQL instance: ${CLOUDSQL_INSTANCE}"
echo "  Database:           ${DB_NAME}"
echo "  Database user:      ${DB_USER}"
echo "  Secret Manager:     ${SECRET_ID}"
echo "  Service account:    ${SA_EMAIL}"
echo ""
echo "Next steps:"
echo "  1. Get Cloud SQL connection name:"
echo "     gcloud sql instances describe ${CLOUDSQL_INSTANCE} --format='value(connectionName)'"
echo ""
echo "  2. Deploy to Cloud Run:"
echo "     export CLOUDSQL_CONNECTION_NAME=\$(gcloud sql instances describe ${CLOUDSQL_INSTANCE} --format='value(connectionName)')"
echo "     bash scripts/gcp/deploy.sh"
