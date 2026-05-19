#!/usr/bin/env bash
# Creates the GCS bucket for Terraform remote state and the app-bundles bucket.
# Run ONCE before `terraform init`. Safe to re-run (idempotent).
set -euo pipefail

PROJECT_ID="${1:-$(gcloud config get-value project)}"
REGION="${2:-asia-south1}"
STATE_BUCKET="${PROJECT_ID}-tf-state"
BUNDLES_BUCKET="${PROJECT_ID}-app-bundles"

echo "==> Bootstrapping project: ${PROJECT_ID}"

# Enable required APIs
gcloud services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  iap.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  storage.googleapis.com \
  secretmanager.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="${PROJECT_ID}"

echo "==> APIs enabled"

# Create state bucket
if ! gsutil ls -p "${PROJECT_ID}" "gs://${STATE_BUCKET}" &>/dev/null; then
  gsutil mb -p "${PROJECT_ID}" -l "${REGION}" "gs://${STATE_BUCKET}"
  gsutil versioning set on "gs://${STATE_BUCKET}"
  gsutil ubla set on "gs://${STATE_BUCKET}"
  echo "==> State bucket created: gs://${STATE_BUCKET}"
else
  echo "==> State bucket already exists: gs://${STATE_BUCKET}"
fi

# Create app bundles bucket
if ! gsutil ls -p "${PROJECT_ID}" "gs://${BUNDLES_BUCKET}" &>/dev/null; then
  gsutil mb -p "${PROJECT_ID}" -l "${REGION}" "gs://${BUNDLES_BUCKET}"
  gsutil versioning set on "gs://${BUNDLES_BUCKET}"
  echo "==> App bundles bucket created: gs://${BUNDLES_BUCKET}"
else
  echo "==> App bundles bucket already exists: gs://${BUNDLES_BUCKET}"
fi

echo ""
echo "==> Now run:"
echo "    cd terraform"
echo "    terraform init -backend-config=\"bucket=${STATE_BUCKET}\" -backend-config=\"prefix=cloud-cartographer\""
echo "    cp terraform.tfvars.example terraform.tfvars  # edit with your values"
echo "    terraform plan"
