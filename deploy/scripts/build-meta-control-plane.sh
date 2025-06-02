#!/bin/bash

# ==============================================================================
# Build and Push Meta Control Plane Container
# ==============================================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd )"

# Environment variables (should be set by main orchestrator)
GCP_PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID must be set}"
GCP_REGION="${GCP_REGION:?GCP_REGION must be set}"
DEPLOY_ENV="${DEPLOY_ENV:?DEPLOY_ENV must be set}"

AR_REPO_NAME="aipress-images-${DEPLOY_ENV}"
IMAGE_NAME="meta-control-plane"
TAG="${BUILD_TAG:-$(git rev-parse --short HEAD)}"

# Construct the full image URL
IMAGE_URL="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${TAG}"

echo "Building Meta Control Plane container..."
echo "Project: $GCP_PROJECT_ID"
echo "Environment: $DEPLOY_ENV"
echo "Image: $IMAGE_URL"

# --- Authenticate Docker with Artifact Registry ---
echo "Configuring Docker authentication..."
gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --project="${GCP_PROJECT_ID}"

# --- Build the Docker Image ---
echo "Building Docker image..."
docker build \
    --platform linux/amd64 \
    --build-arg GCP_PROJECT_ID="${GCP_PROJECT_ID}" \
    --build-arg DEPLOY_ENV="${DEPLOY_ENV}" \
    -t "${IMAGE_URL}" \
    -f "${PROJECT_ROOT}/src/meta-control-plane/Dockerfile" \
    "${PROJECT_ROOT}"

# --- Push the Docker Image ---
echo "Pushing Docker image..."
docker push "${IMAGE_URL}"

# --- Tag as latest for environment ---
LATEST_URL="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${DEPLOY_ENV}-latest"
docker tag "${IMAGE_URL}" "${LATEST_URL}"
docker push "${LATEST_URL}"

echo "Meta Control Plane container built and pushed successfully!"
echo "Image URL: ${IMAGE_URL}"
echo "Latest URL: ${LATEST_URL}"

# Export for use by deployment scripts
export META_CONTROL_PLANE_IMAGE_URL="${IMAGE_URL}"
echo "META_CONTROL_PLANE_IMAGE_URL=${IMAGE_URL}" >> "$GITHUB_ENV" 2>/dev/null || true
