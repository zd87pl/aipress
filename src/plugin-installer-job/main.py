import os
import subprocess
import sys
import logging
import yaml
from google.cloud import storage
from google.cloud import secretmanager

# Configure basic logging
logging.basicConfig(level=logging.INFO, stream=sys.stdout, format='[Plugin Job] %(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# --- Configuration from Environment Variables ---
# These are expected to be passed to the Cloud Run Job
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
GCP_REGION = os.environ.get("GCP_REGION")
TENANT_ID = os.environ.get("TENANT_ID")
DB_USER = os.environ.get("DB_USER")
DB_NAME = os.environ.get("DB_NAME")
DB_HOST_SOCKET = os.environ.get("DB_HOST_SOCKET") # e.g., /cloudsql/project:region:instance
SITE_URL = os.environ.get("SITE_URL", "http://localhost") # Optional site URL context
PLUGINS_YAML_GCS_URI = os.environ.get("PLUGINS_YAML_GCS_URI") # e.g., gs://bucket-name/path/to/default-plugins.yaml
DB_PASSWORD_SECRET_NAME = os.environ.get("DB_PASSWORD_SECRET_NAME") # e.g., projects/PROJECT_ID/secrets/aipress-tenant-xyz-db-password/versions/latest

# --- Helper Functions ---

def access_secret_version(secret_version_name):
    """Accesses a secret version from Google Secret Manager."""
    try:
        client = secretmanager.SecretManagerServiceClient()
        response = client.access_secret_version(request={"name": secret_version_name})
        payload = response.payload.data.decode("UTF-8")
        return payload
    except Exception as e:
        logger.error(f"Failed to access secret {secret_version_name}: {e}", exc_info=True)
        raise

def download_gcs_yaml(gcs_uri):
    """Downloads a YAML file from GCS and parses it."""
    try:
        if not gcs_uri or not gcs_uri.startswith("gs://"):
            raise ValueError("Invalid GCS URI provided.")

        bucket_name, blob_name = gcs_uri.replace("gs://", "").split("/", 1)
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)

        logger.info(f"Downloading YAML from gs://{bucket_name}/{blob_name}")
        yaml_content = blob.download_as_string()
        logger.info("YAML file downloaded successfully.")

        data = yaml.safe_load(yaml_content)
        logger.info("YAML file parsed successfully.")
        return data
    except Exception as e:
        logger.error(f"Failed to download or parse YAML from {gcs_uri}: {e}", exc_info=True)
        raise

def run_install_script(db_host, db_name, db_user, db_password, plugin_name, activate, site_url):
    """Runs the install_plugins.sh script for a single plugin."""
    logger.info(f"Running installation script for plugin: {plugin_name} (Activate: {activate})")
    script_path = "./install_plugins.sh"
    activate_str = "true" if activate else "false"

    command = [
        script_path,
        db_host,
        db_name,
        db_user,
        db_password,
        plugin_name,
        activate_str,
        site_url
    ]

    try:
        process = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=True # Raise an exception if the script returns a non-zero exit code
        )
        logger.info(f"Script stdout for {plugin_name}:\n{process.stdout}")
        if process.stderr:
             logger.warning(f"Script stderr for {plugin_name}:\n{process.stderr}")
        logger.info(f"Successfully processed plugin: {plugin_name}")
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Install script failed for plugin {plugin_name} with exit code {e.returncode}.")
        logger.error(f"Stdout:\n{e.stdout}")
        logger.error(f"Stderr:\n{e.stderr}")
        return False
    except Exception as e:
        logger.error(f"An unexpected error occurred running install script for {plugin_name}: {e}", exc_info=True)
        return False

# --- Main Job Logic ---

def main():
    logger.info("Starting plugin installation job...")
    logger.info(f"Tenant ID: {TENANT_ID}")
    logger.info(f"Project ID: {GCP_PROJECT_ID}")
    logger.info(f"DB Name: {DB_NAME}")
    logger.info(f"DB User: {DB_USER}")
    logger.info(f"DB Host/Socket: {DB_HOST_SOCKET}")
    logger.info(f"Plugins YAML URI: {PLUGINS_YAML_GCS_URI}")
    logger.info(f"DB Password Secret: {DB_PASSWORD_SECRET_NAME}")

    # Basic validation
    required_vars = [
        GCP_PROJECT_ID, GCP_REGION, TENANT_ID, DB_USER, DB_NAME,
        DB_HOST_SOCKET, PLUGINS_YAML_GCS_URI, DB_PASSWORD_SECRET_NAME
    ]
    if not all(required_vars):
        logger.error("Missing one or more required environment variables. Exiting.")
        sys.exit(1)

    job_failed = False
    try:
        # 1. Fetch DB Password
        logger.info("Fetching database password from Secret Manager...")
        db_password = access_secret_version(DB_PASSWORD_SECRET_NAME)
        logger.info("Database password fetched successfully.")

        # 2. Download and parse YAML
        plugin_data = download_gcs_yaml(PLUGINS_YAML_GCS_URI)
        plugins_to_install = plugin_data.get('plugins', [])

        if not plugins_to_install:
            logger.warning("No plugins found in the YAML file. Nothing to install.")
            sys.exit(0)

        logger.info(f"Found {len(plugins_to_install)} plugins to process.")

        # 3. Iterate and install plugins
        for plugin in plugins_to_install:
            plugin_name = plugin.get('name')
            activate = plugin.get('activate', False) # Default to false if not specified

            if not plugin_name:
                logger.warning("Skipping plugin entry with no name.")
                continue

            # Run the install script for this plugin
            # Note: We use the socket path directly as the DB_HOST argument for the script
            success = run_install_script(
                DB_HOST_SOCKET, # Pass the socket path here
                DB_NAME,
                DB_USER,
                db_password,
                plugin_name,
                activate,
                SITE_URL
            )
            if not success:
                job_failed = True
                # Decide whether to continue with other plugins or stop on first failure
                logger.error(f"Stopping job due to failure installing {plugin_name}.")
                break # Stop on first failure for now

    except Exception as e:
        logger.error(f"Plugin installation job failed with an unexpected error: {e}", exc_info=True)
        job_failed = True

    if job_failed:
        logger.error("Plugin installation job finished with errors.")
        sys.exit(1) # Exit with non-zero code to indicate failure
    else:
        logger.info("Plugin installation job completed successfully.")
        sys.exit(0) # Exit successfully

if __name__ == "__main__":
    main()
