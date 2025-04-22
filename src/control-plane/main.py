from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel
import subprocess
import os
import json
import logging
import sys

# Configure basic logging
logging.basicConfig(level=logging.INFO, stream=sys.stdout)
logger = logging.getLogger(__name__)

app = FastAPI(title="AIPress Control Plane PoC")

# --- Configuration ---
# These should ideally come from environment variables or a config management system
TF_MAIN_PATH = os.getenv("TF_MAIN_PATH", "../../infra") # Relative path from src/control-plane to infra
GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID", "aipress-poc-project") # Should match setup script
GCP_REGION = os.getenv("GCP_REGION", "us-central1") # Should match setup script
SHARED_SQL_INSTANCE_NAME = os.getenv("SHARED_SQL_INSTANCE_NAME", "aipress-poc-db-shared") # Should match setup script
WP_RUNTIME_SA_NAME = os.getenv("WP_RUNTIME_SA_NAME", "wp-runtime-sa") # Should match setup script
WP_DOCKER_IMAGE_URL = os.getenv("WP_DOCKER_IMAGE_URL", f"{GCP_REGION}-docker.pkg.dev/{GCP_PROJECT_ID}/aipress-images/wordpress-runtime:latest") # Construct default if not set

# When running inside the container, the infra dir is copied to /infra
# Use this directly as the absolute path for Terraform commands
TF_MAIN_PATH_ABS = "/infra" # Absolute path inside the container

class SiteCreationResponse(BaseModel):
    message: str
    tenant_id: str
    service_url: str | None = None
    logs: str | None = None


# --- Helper Functions ---
def run_terraform_command(command: list[str], working_dir: str) -> tuple[bool, str, str]:
    """Runs a Terraform command and captures output."""
    try:
        # Ensure Terraform authentication is handled (e.g., via GOOGLE_APPLICATION_CREDENTIALS env var)
        logger.info(f"Running command: {' '.join(command)} in {working_dir}")
        process = subprocess.run(
            command,
            cwd=working_dir,
            capture_output=True,
            text=True,
            check=True,
            env=os.environ, # Pass environment variables
        )
        logger.info(f"Terraform stdout:\n{process.stdout}")
        return True, process.stdout, process.stderr
    except subprocess.CalledProcessError as e:
        logger.error(f"Terraform error stderr:\n{e.stderr}")
        return False, e.stdout, e.stderr
    except FileNotFoundError:
        logger.error("Terraform command not found. Is Terraform installed and in PATH?")
        return False, "", "Terraform command not found."
    except Exception as e:
        logger.error(f"An unexpected error occurred: {str(e)}")
        return False, "", str(e)

# --- API Endpoints ---

@app.on_event("startup")
async def startup_event():
    logger.info("Initializing Terraform...")
    # Run terraform init on startup
    success, stdout, stderr = run_terraform_command(["terraform", "init", "-upgrade"], TF_MAIN_PATH_ABS)
    if not success:
        logger.error(f"Terraform init failed on startup: {stderr}")
        # Depending on requirements, might want to prevent startup
    else:
        logger.info("Terraform initialized successfully.")


@app.post("/poc/create-site/{tenant_id}",
          response_model=SiteCreationResponse,
          status_code=status.HTTP_202_ACCEPTED)
async def create_site_poc(tenant_id: str):
    """
    Initiates the creation of WordPress site resources for a given tenant_id using Terraform.
    This is asynchronous in spirit; the request returns accepted, but TF runs inline for PoC.
    """
    logger.info(f"Received request to create site for tenant: {tenant_id}")

    # Basic input validation
    if not tenant_id or not tenant_id.isalnum(): # Simple check
         raise HTTPException(status_code=400, detail="Invalid tenant_id format (alphanumeric required).")

    # Define the path for the tenant-specific tfvars file
    tf_vars_file_name = f"tenant-{tenant_id}.auto.tfvars.json" # .auto.tfvars.json files are loaded automatically
    tf_vars_file_path = os.path.join(TF_MAIN_PATH_ABS, tf_vars_file_name)

    # Construct tfvars content
    # Note: The module now generates secrets, so we don't pass password here.
    # We reference the service account *email* which depends on the project ID.
    wp_runtime_sa_email = f"{WP_RUNTIME_SA_NAME}@{GCP_PROJECT_ID}.iam.gserviceaccount.com"
    tf_vars = {
        "tenant_id": tenant_id,
        "gcp_project_id": GCP_PROJECT_ID,
        "gcp_region": GCP_REGION,
        "shared_sql_instance_name": SHARED_SQL_INSTANCE_NAME,
        "wp_runtime_sa_email": wp_runtime_sa_email,
        "wp_docker_image_url": WP_DOCKER_IMAGE_URL,
        # "max_instances": 1 # Optionally override module default for PoC
    }

    # Write the tfvars file
    try:
        with open(tf_vars_file_path, 'w') as f:
            json.dump(tf_vars, f, indent=2)
        logger.info(f"Created tfvars file: {tf_vars_file_path}")
    except IOError as e:
        logger.error(f"Failed to write tfvars file {tf_vars_file_path}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to write Terraform config: {e}")

    # Run terraform apply (targeting the module instance might be better later)
    # For PoC with .auto.tfvars.json, a simple apply might suffice if only one tenant is tested at a time.
    # Using workspaces is a better approach for concurrent runs.
    # Let's create a workspace for this tenant.
    ws_success, _, ws_stderr = run_terraform_command(["terraform", "workspace", "new", tenant_id], TF_MAIN_PATH_ABS)
    # Ignore error if workspace already exists
    if not ws_success and "already exists" not in ws_stderr:
         logger.error(f"Failed to create/select Terraform workspace {tenant_id}: {ws_stderr}")
         # Cleanup tfvars file before raising error
         os.remove(tf_vars_file_path)
         raise HTTPException(status_code=500, detail=f"Failed to create/select Terraform workspace: {ws_stderr}")
    elif ws_success or "already exists" in ws_stderr:
         logger.info(f"Using Terraform workspace: {tenant_id}")


    # Construct the apply command with necessary -var flags for root variables
    apply_command = [
        "terraform",
        "apply",
        "-auto-approve",
        # No longer need -target as this config only contains the module now
        # "-target=module.tenant_wordpress_instance", 
        f"-var=gcp_project_id={GCP_PROJECT_ID}",
        f"-var=gcp_region={GCP_REGION}",
        f"-var=wp_docker_image_url={WP_DOCKER_IMAGE_URL}",
        f"-var=control_plane_docker_image_url={os.getenv('CONTROL_PLANE_DOCKER_IMAGE_URL', WP_DOCKER_IMAGE_URL)}", # Get from env var passed by Terraform
        # Pass the specific tenant variables needed by the root module's tenant_wordpress_instance block
        f"-var=tenant_id={tenant_id}",
        f"-var=wp_runtime_sa_email={wp_runtime_sa_email}",
        # Pass other required root vars if they don't have defaults or need overriding
        f"-var=shared_sql_instance_name={SHARED_SQL_INSTANCE_NAME}",
        f"-var=tf_sa_name={os.getenv('TF_SA_NAME', 'terraform-sa')}",
        # e.g., f"-var=wp_runtime_sa_name={WP_RUNTIME_SA_NAME}"
    ]

    # Run apply in the selected workspace
    apply_success, apply_stdout, apply_stderr = run_terraform_command(
        apply_command,
        TF_MAIN_PATH_ABS
    )

    # Clean up the tfvars file regardless of success/failure
    try:
        os.remove(tf_vars_file_path)
        logger.info(f"Removed tfvars file: {tf_vars_file_path}")
    except OSError as e:
        logger.warning(f"Could not remove tfvars file {tf_vars_file_path}: {e}")


    if not apply_success:
        logger.error(f"Terraform apply failed for tenant {tenant_id}")
        raise HTTPException(status_code=500, detail=f"Terraform apply failed: {apply_stderr}")

    # If successful, try to get the output (Cloud Run URL)
    # This requires the module output to be exposed in the main config or use terraform output -json
    # For PoC, we'll just construct a placeholder
    # TODO: Parse actual output
    service_url_placeholder = f"https://aipress-tenant-{tenant_id}-XYZ.a.run.app" # Replace XYZ
    logger.info(f"Terraform apply successful for tenant {tenant_id}.")

    return SiteCreationResponse(
        message=f"Site creation initiated and potentially completed for {tenant_id}.",
        tenant_id=tenant_id,
        service_url=service_url_placeholder,
        logs=f"TF Stdout:\n{apply_stdout}\nTF Stderr:\n{apply_stderr}" # Include logs for debugging PoC
    )

# Optional: Add a destroy endpoint for PoC cleanup
@app.delete("/poc/destroy-site/{tenant_id}", status_code=status.HTTP_202_ACCEPTED)
async def destroy_site_poc(tenant_id: str):
    logger.info(f"Received request to destroy site for tenant: {tenant_id}")

    if not tenant_id or not tenant_id.isalnum():
         raise HTTPException(status_code=400, detail="Invalid tenant_id format.")

    # Select the workspace
    ws_success, _, ws_stderr = run_terraform_command(["terraform", "workspace", "select", tenant_id], TF_MAIN_PATH_ABS)
    if not ws_success:
         # If workspace doesn't exist, it might already be deleted or never created.
         # Consider returning success or a specific message instead of 500.
         logger.warning(f"Failed to select Terraform workspace {tenant_id} (might not exist): {ws_stderr}")
         # For PoC, let's allow destroy attempt even if select fails, TF destroy will likely fail cleanly if state missing.
         # raise HTTPException(status_code=500, detail=f"Failed to select Terraform workspace: {ws_stderr}")
         logger.info(f"Attempting destroy even though workspace selection failed for {tenant_id}")


    # Define tfvars file path (needed for destroy?) - Usually not needed if state exists
    tf_vars_file_name = f"tenant-{tenant_id}.auto.tfvars.json"
    tf_vars_file_path = os.path.join(TF_MAIN_PATH_ABS, tf_vars_file_name)

    # Construct the destroy command with necessary -var flags for root variables
    # These are needed for Terraform to parse the configuration, even during destroy
    # Construct wp_runtime_sa_email needed for parsing
    wp_runtime_sa_email = f"{WP_RUNTIME_SA_NAME}@{GCP_PROJECT_ID}.iam.gserviceaccount.com"
    destroy_command = [
        "terraform",
        "destroy",
        "-auto-approve",
        # Target only the tenant module instance to avoid trying to destroy project APIs
        "-target=module.tenant_wordpress_instance", 
        f"-var=gcp_project_id={GCP_PROJECT_ID}",
        f"-var=gcp_region={GCP_REGION}",
        f"-var=wp_docker_image_url={WP_DOCKER_IMAGE_URL}",
        f"-var=control_plane_docker_image_url={os.getenv('CONTROL_PLANE_DOCKER_IMAGE_URL', WP_DOCKER_IMAGE_URL)}",
        f"-var=tenant_id={tenant_id}", # Needed to parse module
        f"-var=wp_runtime_sa_email={wp_runtime_sa_email}", # Needed to parse module
        f"-var=shared_sql_instance_name={SHARED_SQL_INSTANCE_NAME}",
        f"-var=tf_sa_name={os.getenv('TF_SA_NAME', 'terraform-sa')}",
    ]
    destroy_success, destroy_stdout, destroy_stderr = run_terraform_command(
        destroy_command,
        TF_MAIN_PATH_ABS
    )

    # Attempt to remove the workspace after destroy
    if destroy_success:
         logger.info(f"Terraform destroy successful for {tenant_id}, removing workspace...")
         # Switch back to default before deleting tenant workspace
         run_terraform_command(["terraform", "workspace", "select", "default"], TF_MAIN_PATH_ABS)
         run_terraform_command(["terraform", "workspace", "delete", tenant_id], TF_MAIN_PATH_ABS)
    else:
         # If destroy failed BUT workspace selection also failed earlier, maybe workspace gone?
         if not ws_success:
             logger.warning(f"Terraform destroy failed for {tenant_id}, but workspace selection also failed. Assuming already destroyed/cleaned.")
             # Return success message here as it's likely already gone
             return {"message": f"Site destruction attempt for {tenant_id} finished (likely already destroyed).", "logs": f"TF Stdout:\n{destroy_stdout}\nTF Stderr:\n{destroy_stderr}"}
         else:
             logger.error(f"Terraform destroy failed for tenant {tenant_id}")
             raise HTTPException(status_code=500, detail=f"Terraform destroy failed: {destroy_stderr}")

    # Clean up tfvars file if it somehow still exists
    if os.path.exists(tf_vars_file_path):
        try:
            os.remove(tf_vars_file_path)
            logger.info(f"Removed tfvars file: {tf_vars_file_path}")
        except OSError as e:
            logger.warning(f"Could not remove tfvars file {tf_vars_file_path}: {e}")


    return {"message": f"Site destruction initiated and potentially completed for {tenant_id}.", "logs": f"TF Stdout:\n{destroy_stdout}\nTF Stderr:\n{destroy_stderr}"}


if __name__ == "__main__":
    import uvicorn
    # Run locally using: uvicorn src.control-plane.main:app --reload --port 8000
    uvicorn.run(app, host="0.0.0.0", port=8000)
