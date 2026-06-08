#!/bin/bash
# =============================================================================
# GCP Cloud Run Deployment Script for Registry Center
# =============================================================================
# Builds via Cloud Build (source deploy) and deploys to Cloud Run.
# No local Docker required.
#
# Prerequisites:
#   1. Run scripts/gcp/setup.sh first to create GCP resources.
#   2. gcloud auth login && gcloud auth configure-docker
#
# Usage:
#   export GCP_PROJECT_ID="my-project"
#   export GCP_REGION="asia-east1"
#   export CLOUDSQL_CONNECTION_NAME="my-project:asia-east1:registry-center-db"
#   bash scripts/gcp/deploy.sh
# =============================================================================

set -e
cd "$(dirname "$0")/../.."

GCP_PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
GCP_REGION="${GCP_REGION:?Set GCP_REGION}"
CLOUDSQL_CONNECTION_NAME="${CLOUDSQL_CONNECTION_NAME:?Set CLOUDSQL_CONNECTION_NAME}"
SERVICE_NAME="${SERVICE_NAME:-registry-center}"
DB_NAME="${DB_NAME:-registry_center}"
DB_USER="${DB_USER:-registry}"
DB_PASSWORD="${DB_PASSWORD:?Set DB_PASSWORD (same as setup.sh)}"
DB_POOL_MIN="${DB_POOL_MIN:-2}"
DB_POOL_MAX="${DB_POOL_MAX:-10}"
MEMORY="${MEMORY:-512Mi}"
CPU="${CPU:-1}"
MAX_INSTANCES="${MAX_INSTANCES:-10}"
SA_NAME="${SA_NAME:-registry-center-sa}"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

echo "============================================"
echo " Deploy Registry Center to Cloud Run"
echo " Project: ${GCP_PROJECT_ID}"
echo " Region:  ${GCP_REGION}"
echo "============================================"

gcloud run deploy "${SERVICE_NAME}" \
  --source=. \
  --region="${GCP_REGION}" \
  --platform=managed \
  --allow-unauthenticated \
  --memory="${MEMORY}" \
  --cpu="${CPU}" \
  --max-instances="${MAX_INSTANCES}" \
  --concurrency=80 \
  --timeout=300 \
  --port=8080 \
  --service-account="${SA_EMAIL}" \
  --add-cloudsql-instances="${CLOUDSQL_CONNECTION_NAME}" \
  --set-env-vars="PERSISTENCE_MODE=postgresql,DB_HOST=/cloudsql/${CLOUDSQL_CONNECTION_NAME},DB_PORT=5432,DB_NAME=${DB_NAME},DB_USERNAME=${DB_USER},DB_PASSWORD=${DB_PASSWORD},DB_POOL_MIN=${DB_POOL_MIN},DB_POOL_MAX=${DB_POOL_MAX},REGISTRY_ENABLE_HTTPS=false,REGISTRY_FORWARDED_ALLOW_IPS=*,REGISTRY_OWNER__VALIDATION__MODE=relaxed" \
  --project="${GCP_PROJECT_ID}"

echo ""
SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" --region="${GCP_REGION}" --format="value(status.url)" --project="${GCP_PROJECT_ID}")
echo "Deploy done! Service URL: ${SERVICE_URL}"
echo "Test: curl ${SERVICE_URL}/health"
