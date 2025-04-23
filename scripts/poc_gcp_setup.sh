#!/bin/bash

# ==============================================================================
# AIPress Proof-of-Concept (PoC) - Initial GCP Setup Script
# ==============================================================================
#
# This script performs the initial setup steps required in the GCP project
# before running the Terraform configuration for the PoC.
#
# IMPORTANT:
# - Run this script manually step-by-step or ensure you understand each command.
# - Replace placeholder values (like YOUR_PROJECT_ID, YOUR_REGION, etc.)
# - Securely store any generated keys (e.g., terraform-key.json). DO NOT COMMIT KEYS.
# - The Terraform SA permissions granted here are broad for PoC simplicity.
#   REPLACE with least-privilege roles before any production use.
#
# Prerequisites:
# - gcloud CLI installed and authenticated with appropriate user permissions.
# - A GCP Project created.
# - Permissions to create Service Accounts, enable APIs, create Cloud SQL, GCS, Secret Manager secrets, Artifact Registry.

# --- Configuration ---
export GCP_PROJECT_ID="wp-engine-ziggy" # !!! REPLACE with your actual Project ID !!!
export GCP_REGION="us-central1"            # !!! REPLACE with your desired region !!!
export TF_SA_NAME="terraform-sa"
export WP_RUNTIME_SA_NAME="wp-runtime-sa"
export AR_REPO_NAME="aipress-images"
export SHARED_SQL_INSTANCE_NAME="aipress-poc-db-shared"
export SQL_ROOT_PASSWORD_SECRET_NAME="aipress-poc-sql-root-password"
# SQL Root password will be prompted for interactively

# --- Get script's directory ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# --- 1. Enable Necessary APIs ---
echo "The following APIs will be enabled:"
echo "- run.googleapis.com"
echo "- sqladmin.googleapis.com"
echo "- storage.googleapis.com"
echo "- secretmanager.googleapis.com"
echo "- iam.googleapis.com"
echo "- artifactregistry.googleapis.com"
echo "- cloudbuild.googleapis.com (Optional)"
echo "- cloudresourcemanager.googleapis.com"
read -p "Do you want to enable these APIs in project ${GCP_PROJECT_ID}? [y/N]: " confirm_apis
if [[ ! "$confirm_apis" =~ ^[Yy]$ ]]; then
    echo "Aborting API enablement."
    exit 1
fi
echo "Enabling required GCP APIs..."
gcloud services enable run.googleapis.com --project=${GCP_PROJECT_ID}
gcloud services enable sqladmin.googleapis.com --project=${GCP_PROJECT_ID}
gcloud services enable storage.googleapis.com --project=${GCP_PROJECT_ID}
gcloud services enable secretmanager.googleapis.com --project=${GCP_PROJECT_ID}
gcloud services enable iam.googleapis.com --project=${GCP_PROJECT_ID}
gcloud services enable artifactregistry.googleapis.com --project=${GCP_PROJECT_ID}
gcloud services enable cloudbuild.googleapis.com --project=${GCP_PROJECT_ID} # Optional: If using Cloud Build
gcloud services enable cloudresourcemanager.googleapis.com --project=${GCP_PROJECT_ID}
echo "APIs enabled."
echo "---"

# --- 2. Create Service Accounts ---
echo "Creating Service Accounts..."

# Terraform Service Account
read -p "Create Terraform Service Account '${TF_SA_NAME}' in project ${GCP_PROJECT_ID}? [y/N]: " confirm_tf_sa_create
if [[ ! "$confirm_tf_sa_create" =~ ^[Yy]$ ]]; then
    echo "Aborting Terraform SA creation."
    exit 1
fi

# Check if Terraform SA exists
if gcloud iam service-accounts describe "${TF_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" --project=${GCP_PROJECT_ID} &> /dev/null; then
    echo "Terraform SA '${TF_SA_NAME}' already exists."
else
    echo "Creating Terraform SA: ${TF_SA_NAME}"
    gcloud iam service-accounts create ${TF_SA_NAME} \
      --display-name "Terraform Service Account for AIPress PoC" \
      --project=${GCP_PROJECT_ID}
fi

echo "!!!"
echo "!!! WARNING: The next step grants the highly privileged 'roles/owner' role to the Terraform SA."
echo "!!! This is NOT recommended for production. Use least-privilege roles instead."
echo "!!!"
read -p "Grant 'roles/owner' to '${TF_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com'? (PoC ONLY) [y/N]: " confirm_tf_sa_owner
if [[ ! "$confirm_tf_sa_owner" =~ ^[Yy]$ ]]; then
    echo "Aborting Terraform SA role grant."
    # Consider deleting the SA if the role isn't granted? Maybe not for PoC.
    exit 1
fi
echo "Granting roles/owner to Terraform SA..."
# This command is additive, less critical to check beforehand if it already exists
gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${TF_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/owner" # !!! REPLACE with specific roles for Production !!!

# --- Handle Terraform SA Key ---
KEY_FILE_PATH="${SCRIPT_DIR}/terraform-key.json" # Define path

if [ -f "${KEY_FILE_PATH}" ]; then
    # File exists, ask to overwrite
    read -p "Key file '${KEY_FILE_PATH}' already exists. Overwrite? [y/N]: " confirm_key_overwrite
    if [[ "$confirm_key_overwrite" =~ ^[Yy]$ ]]; then
        echo "Overwriting key file '${KEY_FILE_PATH}' for Terraform SA..."
        echo "!!! Store terraform-key.json securely and DO NOT commit it to Git !!!"
        gcloud iam service-accounts keys create "${KEY_FILE_PATH}" \
          --iam-account="${TF_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
          --project="${GCP_PROJECT_ID}"
    else
        echo "Skipping overwrite of existing key file '${KEY_FILE_PATH}'."
    fi # Closes confirm_key_overwrite if
else
    # File doesn't exist, ask to create
    read -p "Create key file '${KEY_FILE_PATH}' for Terraform SA '${TF_SA_NAME}'? (Store securely!) [y/N]: " confirm_key_create
    if [[ "$confirm_key_create" =~ ^[Yy]$ ]]; then
        echo "Creating key file '${KEY_FILE_PATH}' for Terraform SA..."
        echo "!!! Store terraform-key.json securely and DO NOT commit it to Git !!!"
        gcloud iam service-accounts keys create "${KEY_FILE_PATH}" \
          --iam-account="${TF_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
          --project="${GCP_PROJECT_ID}"
    else
        echo "Skipping Terraform SA key creation."
    fi # Closes confirm_key_create if
fi # Closes outer if -f
# --- End Handle Terraform SA Key ---


# WordPress Runtime Service Account
read -p "Create WordPress Runtime Service Account '${WP_RUNTIME_SA_NAME}' in project ${GCP_PROJECT_ID}? [y/N]: " confirm_wp_sa_create
if [[ ! "$confirm_wp_sa_create" =~ ^[Yy]$ ]]; then
    echo "Aborting WordPress Runtime SA creation."
    exit 1
fi

# Check if WP Runtime SA exists
if gcloud iam service-accounts describe "${WP_RUNTIME_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" --project=${GCP_PROJECT_ID} &> /dev/null; then
    echo "WordPress Runtime SA '${WP_RUNTIME_SA_NAME}' already exists."
else
    echo "Creating WordPress Runtime SA: ${WP_RUNTIME_SA_NAME}"
    gcloud iam service-accounts create ${WP_RUNTIME_SA_NAME} \
      --display-name "WordPress Runtime Service Account for AIPress PoC" \
      --project=${GCP_PROJECT_ID}
fi

echo "Granting base roles to WordPress Runtime SA (Specific resource permissions granted via Terraform)..."
# Grant roles/cloudsql.client - Needed to connect via proxy
read -p "Grant 'roles/cloudsql.client' to WordPress Runtime SA '${WP_RUNTIME_SA_NAME}'? [y/N]: " confirm_wp_sa_sql
if [[ ! "$confirm_wp_sa_sql" =~ ^[Yy]$ ]]; then
    echo "Aborting WordPress Runtime SA role grant."
    exit 1
fi
echo "Granting roles/cloudsql.client to WordPress Runtime SA..."
# This command is additive
gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${WP_RUNTIME_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

# Grant roles/secretmanager.secretAccessor - Needed to read DB password and salts
read -p "Grant 'roles/secretmanager.secretAccessor' to WordPress Runtime SA '${WP_RUNTIME_SA_NAME}'? (Needed for DB password/salts) [y/N]: " confirm_wp_sa_secret
if [[ ! "$confirm_wp_sa_secret" =~ ^[Yy]$ ]]; then
    echo "Aborting WordPress Runtime SA Secret Accessor role grant."
    exit 1
fi
echo "Granting roles/secretmanager.secretAccessor to WordPress Runtime SA..."
# This command is additive
gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  --member="serviceAccount:${WP_RUNTIME_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Note: roles/storage.objectAdmin will be granted per-resource via Terraform.

echo "Service Accounts created and base roles granted."
echo "---"

# --- 3. Create Artifact Registry Repository ---
read -p "Create Artifact Registry Docker repository '${AR_REPO_NAME}' in region ${GCP_REGION}? [y/N]: " confirm_ar_repo
if [[ ! "$confirm_ar_repo" =~ ^[Yy]$ ]]; then
    echo "Aborting Artifact Registry repository creation."
    exit 1
fi

# Check if Artifact Registry repo exists
if gcloud artifacts repositories describe ${AR_REPO_NAME} --location=${GCP_REGION} --project=${GCP_PROJECT_ID} &> /dev/null; then
    echo "Artifact Registry repository '${AR_REPO_NAME}' already exists in region ${GCP_REGION}."
else
    echo "Creating Artifact Registry repository: ${AR_REPO_NAME}"
    gcloud artifacts repositories create ${AR_REPO_NAME} \
      --repository-format=docker \
      --location=${GCP_REGION} \
      --description="Docker images for AIPress PoC" \
      --project=${GCP_PROJECT_ID}
    echo "Artifact Registry repository created."
fi
echo "---"

# --- 4. Create Shared Cloud SQL Instance ---
echo "Creating Shared Cloud SQL instance: ${SHARED_SQL_INSTANCE_NAME}"
echo "You will be prompted for the desired root password for the Cloud SQL instance."
read -sp "Enter desired Cloud SQL Root Password: " SQL_ROOT_PASSWORD_INPUT
echo # Add a newline after the password input

if [ -z "$SQL_ROOT_PASSWORD_INPUT" ]; then
  echo "ERROR: SQL Root Password cannot be empty. Exiting."
  exit 1
fi

read -p "Create Cloud SQL instance '${SHARED_SQL_INSTANCE_NAME}' (MySQL 8.0, db-f1-micro) in region ${GCP_REGION}? (This may take several minutes) [y/N]: " confirm_sql_instance
if [[ ! "$confirm_sql_instance" =~ ^[Yy]$ ]]; then
    echo "Aborting Cloud SQL instance creation."
    exit 1
fi

# Check if Cloud SQL instance exists
if gcloud sql instances describe ${SHARED_SQL_INSTANCE_NAME} --project=${GCP_PROJECT_ID} &> /dev/null; then
    echo "Cloud SQL instance '${SHARED_SQL_INSTANCE_NAME}' already exists."
    # Optionally prompt to update password if needed, but skip for now
else
    echo "Initiating Cloud SQL instance creation (This may take several minutes)..."
    gcloud sql instances create ${SHARED_SQL_INSTANCE_NAME} \
      --database-version=MYSQL_8_0 \
      --tier=db-f1-micro \
      --region=${GCP_REGION} \
      --project=${GCP_PROJECT_ID} \
      --root-password="${SQL_ROOT_PASSWORD_INPUT}"
      # Add --network, --no-assign-ip for private IP later
    echo "Cloud SQL instance creation command submitted."
fi
echo "---"

# --- 5. Create Placeholder Secret for SQL Root Password ---
# Store the interactively entered password in Secret Manager.
# Note: Terraform will create per-tenant DB users/passwords and store those separately.
# This root password secret is primarily for initial setup/emergency access.
read -p "Store the entered SQL root password in Secret Manager as '${SQL_ROOT_PASSWORD_SECRET_NAME}'? [y/N]: " confirm_secret
if [[ ! "$confirm_secret" =~ ^[Yy]$ ]]; then
    echo "Aborting secret creation."
    # Clear the variable since we aren't storing it
    unset SQL_ROOT_PASSWORD_INPUT
    # Clear the variable since we aren't storing it
    unset SQL_ROOT_PASSWORD_INPUT
    exit 1
fi

# Check if Secret exists before creating
if gcloud secrets describe ${SQL_ROOT_PASSWORD_SECRET_NAME} --project=${GCP_PROJECT_ID} &> /dev/null; then
    echo "Secret '${SQL_ROOT_PASSWORD_SECRET_NAME}' already exists. Skipping creation."
    # Optionally prompt to add a new version, but keep it simple for now
    # Clear variable if secret exists and we didn't ask for it
    unset SQL_ROOT_PASSWORD_INPUT
else
    echo "Storing the entered SQL root password in Secret Manager: ${SQL_ROOT_PASSWORD_SECRET_NAME}"
    echo -n "${SQL_ROOT_PASSWORD_INPUT}" | \
      gcloud secrets create ${SQL_ROOT_PASSWORD_SECRET_NAME} \
      --data-file=- \
      --project=${GCP_PROJECT_ID} \
      --replication-policy=automatic
    # Clear the variable from memory just in case
    unset SQL_ROOT_PASSWORD_INPUT
    echo "Secret created."
fi
echo "---"

# --- 6. Create GCS Bucket for Terraform State ---
export TF_STATE_BUCKET="aipress-tf-state-${GCP_PROJECT_ID}" # Define state bucket name
read -p "Create GCS bucket '${TF_STATE_BUCKET}' for Terraform state? [y/N]: " confirm_tf_bucket
if [[ ! "$confirm_tf_bucket" =~ ^[Yy]$ ]]; then
    echo "Aborting Terraform state bucket creation."
    # No exit here, setup might continue without TF state bucket if desired for local state testing
else
    # Check if GCS bucket exists (gsutil ls -b returns 0 if exists, non-zero otherwise)
    if gsutil ls -b gs://${TF_STATE_BUCKET}/ &> /dev/null; then
        echo "GCS bucket 'gs://${TF_STATE_BUCKET}/' for Terraform state already exists."
    else
        echo "Creating GCS bucket for Terraform state: ${TF_STATE_BUCKET}"
        # Use gsutil mb with -p project -l region and uniform bucket-level access
        gsutil mb -p ${GCP_PROJECT_ID} -l ${GCP_REGION} -b on gs://${TF_STATE_BUCKET}/
        # Enable versioning (good practice for state files)
        gsutil versioning set on gs://${TF_STATE_BUCKET}/
        echo "GCS bucket for Terraform state created."
    fi
    echo "---"
fi

echo "================================================="
echo "Initial GCP Setup Script Steps Completed."
echo "Next steps:"
echo "1. Ensure Cloud SQL instance '${SHARED_SQL_INSTANCE_NAME}' is fully created."
echo "2. Configure Terraform backend in infra/main.tf (if TF state bucket was created)."
echo "3. Run 'scripts/build_and_push_image.sh' to build and push the WP runtime image."
echo "4. Run 'scripts/run_control_plane.sh' to start the control plane API."
echo "   (This script handles Terraform authentication via GOOGLE_APPLICATION_CREDENTIALS)."
echo "5. Make API calls to the control plane (e.g., /poc/create-site/{tenant_id}) to deploy tenants."
echo "================================================="
