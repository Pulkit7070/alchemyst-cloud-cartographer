#!/usr/bin/env bash
# Full deploy: bundle app → terraform apply
# Usage: ./scripts/deploy.sh <project-id>
set -euo pipefail

PROJECT_ID="${1:-$(gcloud config get-value project)}"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo "latest")"

echo "==> Deploy: project=${PROJECT_ID} version=${GIT_SHA}"

# 1. Upload app bundle
bash scripts/bundle.sh "${PROJECT_ID}" "${GIT_SHA}"

# 2. Apply infra
cd terraform
terraform init \
  -backend-config="bucket=${PROJECT_ID}-tf-state" \
  -backend-config="prefix=cloud-cartographer" \
  -reconfigure

terraform apply \
  -var="project_id=${PROJECT_ID}" \
  -var="app_version=${GIT_SHA}" \
  -auto-approve

echo ""
echo "==> Deploy complete"
terraform output curl_example
