#!/bin/bash
set -e

# --- Configuration (Should match poc_gcp_setup.sh) ---
# Source these from a common file or ensure they are set correctly here
GCP_PROJECT_ID="${GCP_PROJECT_ID:-aipress-project}" # Default if not set externally
GCP_REGION="${GCP_REGION:-us-central1}"            # Default if not set externally
SHARED_SQL_INSTANCE_NAME="${SHARED_SQL_INSTANCE_NAME:-aipress-poc-db-shared}" # Default if not set externally
WP_RUNTIME_SA_NAME="${WP_RUNTIME_SA_NAME:-wp-runtime-sa}"       # Default if not set externally
AR_REPO_NAME="${AR_REPO_NAME:-aipress-images}"       # Default if not set externally
IMAGE_NAME="wordpress-runtime"
TAG="latest"

# --- Get script's directory and project root ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )
CONTROL_PLANE_DIR="${PROJECT_ROOT}/src/control-plane"
INFRA_DIR="${PROJECT_ROOT}/infra"
TF_KEY_FILE="${SCRIPT_DIR}/terraform-key.json" # Key expected in scripts dir

# --- Set Environment Variables for Control Plane ---
export GCP_PROJECT_ID
export GCP_REGION
export SHARED_SQL_INSTANCE_NAME
export WP_RUNTIME_SA_NAME
# Construct the default image URL if not provided externally
export WP_DOCKER_IMAGE_URL="${WP_DOCKER_IMAGE_URL:-${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${TAG}}"
# Point TF_MAIN_PATH relative to the control plane app's location
export TF_MAIN_PATH="../../infra"

# --- Set Terraform Authentication ---
# Check if the key file exists
if [ ! -f "${TF_KEY_FILE}" ]; then
    echo "ERROR: Terraform key file not found at ${TF_KEY_FILE}"
    echo "Please ensure 'terraform-key.json' exists in the 'scripts' directory (generated by poc_gcp_setup.sh)."
    exit 1
fi
# Make the path absolute for GOOGLE_APPLICATION_CREDENTIALS
export GOOGLE_APPLICATION_CREDENTIALS=$(realpath "${TF_KEY_FILE}")
echo "Using Terraform credentials from: ${GOOGLE_APPLICATION_CREDENTIALS}"

# --- Navigate to Control Plane Directory ---
cd "${CONTROL_PLANE_DIR}"
echo "Changed directory to $(pwd)"

# --- Setup Python Environment (Optional: Use venv) ---
# Simple check for requirements.txt and install if needed
if [ -f "requirements.txt" ]; then
    echo "Installing Python dependencies from requirements.txt..."
    # Consider using a virtual environment
    # python3 -m venv venv
    # source venv/bin/activate
    pip install -r requirements.txt
else
    echo "Warning: requirements.txt not found in ${CONTROL_PLANE_DIR}."
fi
echo "---"

# --- Run the Control Plane API ---
echo "Starting Control Plane API via uvicorn..."
echo "API will be available at http://0.0.0.0:8000"
echo "Press Ctrl+C to stop."

# Run uvicorn (adjust module path if needed)
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
# Remove --reload if you don't need automatic reloading on code changes

echo "Control Plane API stopped."
