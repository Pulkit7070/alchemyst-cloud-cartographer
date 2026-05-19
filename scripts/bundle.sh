#!/usr/bin/env bash
# Packages the app (quickstart + systemd units) and uploads to GCS.
# Usage: ./scripts/bundle.sh <project-id> [git-sha]
set -euo pipefail

PROJECT_ID="${1:-$(gcloud config get-value project)}"
GIT_SHA="${2:-$(git rev-parse --short HEAD 2>/dev/null || echo "latest")}"
BUNDLES_BUCKET="${PROJECT_ID}-app-bundles"
BUNDLE_FILE="/tmp/app-${GIT_SHA}.tar.gz"

echo "==> Building bundle: ${GIT_SHA}"

# Pack quickstart + systemd units
tar -czf "${BUNDLE_FILE}" \
  quickstart/ \
  systemd/

# Upload
gsutil cp "${BUNDLE_FILE}" "gs://${BUNDLES_BUCKET}/app-${GIT_SHA}.tar.gz"
gsutil cp "${BUNDLE_FILE}" "gs://${BUNDLES_BUCKET}/app-latest.tar.gz"

echo "==> Uploaded gs://${BUNDLES_BUCKET}/app-${GIT_SHA}.tar.gz"
echo "==> Uploaded gs://${BUNDLES_BUCKET}/app-latest.tar.gz"
rm -f "${BUNDLE_FILE}"
