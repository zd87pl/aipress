#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration (Should match poc_gcp_setup.sh) ---
# Source these from a common file or ensure they are set correctly here
GCP_PROJECT_ID="${GCP_PROJECT_ID:-aipress-project}" # Default if not set externally
GCP_REGION="${GCP_REGION:-us-central1}"            # Default if not set externally
AR_REPO_NAME="${AR_REPO_NAME:-aipress-images}"       # Default if not set externally
IMAGE_NAME="wordpress-runtime"
TAG="experimental" # Use the experimental tag

# Construct the full image URL
IMAGE_URL="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${TAG}"

# --- Get script's directory and project root ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd ) # Assumes script is in 'scripts' subdir

# --- Authenticate Docker with Artifact Registry ---
echo "Configuring Docker authentication for ${GCP_REGION}-docker.pkg.dev..."
gcloud auth configure-docker ${GCP_REGION}-docker.pkg.dev --project=${GCP_PROJECT_ID}
echo "Docker authentication configured."
echo "---"

# --- Build the Docker Image ---
echo "Building EXPERIMENTAL Docker image for linux/amd64: ${IMAGE_URL}"
# Run build from project root so Docker context is correct for COPY commands
# Explicitly specify the target platform for Cloud Run compatibility
# Use the experimental Dockerfile
docker build --no-cache --platform linux/amd64 -t "${IMAGE_URL}" -f "${PROJECT_ROOT}/src/wordpress-runtime/Dockerfile.experimental" "${PROJECT_ROOT}"
echo "EXPERIMENTAL Docker image built."
echo "---"

# --- Push the Docker Image ---
echo "Pushing EXPERIMENTAL Docker image: ${IMAGE_URL}"
docker push "${IMAGE_URL}"
echo "EXPERIMENTAL Docker image pushed successfully."
echo "---"

echo "========================================"
echo "Build and Push script completed."
echo "Experimental Image URL: ${IMAGE_URL}"
echo "========================================"
