# src/tenant-autoscaler/main.py

import functions_framework
import os
import logging
import requests
import google.auth.transport.requests
import google.oauth2.id_token
from datetime import datetime, timedelta, timezone
from google.cloud import monitoring_v3
import base64 # Needed if using PubSub trigger data

# --- Configuration ---
GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID", "wp-engine-ziggy")
GCP_REGION = os.getenv("GCP_REGION", "us-central1") # Region where Cloud Run services are
# Construct Control Plane URL robustly from Cloud Run env vars if available
_cp_url_env = os.getenv("CONTROL_PLANE_URL")
if not _cp_url_env and os.getenv("K_SERVICE"): # Likely running in Cloud Run/Functions V2
    _control_plane_service_name = "aipress-control-plane" # Assume standard name
    _control_plane_region = GCP_REGION # Assume same region
    # Cannot reliably get the full URL automatically, best to set CONTROL_PLANE_URL env var during deployment
    CONTROL_PLANE_URL = f"https://{_control_plane_service_name}-{GCP_PROJECT_ID}.{_control_plane_region}.run.app" # Best guess
    logging.warning(f"CONTROL_PLANE_URL not set, constructed best guess: {CONTROL_PLANE_URL}")
else:
    CONTROL_PLANE_URL = _cp_url_env or "http://localhost:8000" # Fallback for local testing


# Tuning Profiles (Example - map profile names to env var settings)
TUNING_PROFILES = {
    "low": {
        "PHP_PM_MAX_CHILDREN": "5",
        "PHP_PM_START_SERVERS": "2",
        "PHP_PM_MIN_SPARE_SERVERS": "1",
        "PHP_PM_MAX_SPARE_SERVERS": "3",
    },
    "medium": { # Default profile matching entrypoint defaults
        "PHP_PM_MAX_CHILDREN": "10",
        "PHP_PM_START_SERVERS": "3",
        "PHP_PM_MIN_SPARE_SERVERS": "2",
        "PHP_PM_MAX_SPARE_SERVERS": "5",
    },
    "high": {
        "PHP_PM_MAX_CHILDREN": "20",
        "PHP_PM_START_SERVERS": "5",
        "PHP_PM_MIN_SPARE_SERVERS": "4",
        "PHP_PM_MAX_SPARE_SERVERS": "8",
    }
}

# Placeholder - Get this dynamically later (e.g., from Firestore)
# Ensure these IDs match actual deployed tenants
ACTIVE_TENANTS = ["test5566", "test3344"] # Add tenant IDs to monitor

# --- Logging ---
# Configure basic logging
# In Cloud Functions, standard library logging automatically goes to Cloud Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Helper Functions ---

def get_monitoring_metric(project_id: str, tenant_id: str) -> float:
    """
    Fetches average CPU utilization for a tenant's Cloud Run service over the last 5 mins.
    Returns the average utilization (0.0 to 1.0) or -1.0 on error.
    """
    logger.info(f"Fetching CPU metric for tenant {tenant_id}...")
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{project_id}"
        now = datetime.now(timezone.utc)
        interval = monitoring_v3.TimeInterval(
            {
                "end_time": {"seconds": int(now.timestamp()), "nanos": now.microsecond * 1000},
                "start_time": {"seconds": int((now - timedelta(minutes=5)).timestamp()), "nanos": now.microsecond * 1000},
            }
        )

        # Cloud Run CPU Utilization Metric
        # https://cloud.google.com/monitoring/api/metrics_gcp#gcp-run
        metric_type = "run.googleapis.com/container/cpu/utilization"
        # Filter by service name and revision (optional, might need adjustment if multiple revisions active)
        filter_str = f'metric.type = "{metric_type}" AND resource.labels.service_name = "aipress-tenant-{tenant_id}"'

        # Aggregation - Calculate the mean across the time interval
        aggregation = monitoring_v3.Aggregation(
            {
                "alignment_period": {"seconds": 300},  # 5 minutes
                "per_series_aligner": monitoring_v3.Aggregation.Aligner.ALIGN_MEAN,
                 # Optional: Reduce across time series if multiple revisions/instances
                "cross_series_reducer": monitoring_v3.Aggregation.Reducer.REDUCE_MEAN,
                "group_by_fields": ["resource.labels.service_name"], # Group by service to get one value
            }
        )

        results = client.list_time_series(
            request={
                "name": project_name,
                "filter": filter_str,
                "interval": interval,
                "view": monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL,
                "aggregation": aggregation,
            }
        )

        point_value = -1.0 # Default to error/no data
        count = 0
        for result in results:
            # Should ideally be only one point due to aggregation over 5 min alignment
            if result.points:
                point_value = result.points[0].value.double_value
                logger.info(f"Retrieved data point for {tenant_id}: {point_value:.3f}")
                count += 1
            # Log if multiple series found unexpectedly
            if count > 1:
                 logger.warning(f"Multiple time series found for tenant {tenant_id} after aggregation, using first value.")
                 break

        if count == 0:
            logger.warning(f"No CPU utilization data found for tenant {tenant_id} in the last 5 minutes.")
            return -1.0 # Indicate no data found

        return point_value

    except Exception as e:
        logger.error(f"Error fetching monitoring metric for {tenant_id}: {e}", exc_info=True)
        return -1.0 # Indicate error


def get_target_profile(cpu_util: float) -> str | None:
    """
    Simple rule-based logic to determine target profile based on CPU utilization.
    Returns profile name ('low', 'medium', 'high') or None if no change needed.
    """
    if cpu_util < 0: # Handle error case from metric fetching
        logger.warning("Invalid CPU metric received, cannot determine target profile.")
        return None

    logger.info(f"Evaluating CPU util: {cpu_util:.2f}")
    # TODO: Add hysteresis / check current profile to avoid flapping
    if cpu_util > 0.75: # Threshold for scaling up
        logger.info("Decision: Scale up (High profile)")
        return "high"
    elif cpu_util < 0.25: # Threshold for scaling down
        logger.info("Decision: Scale down (Low profile)")
        return "low"
    # Consider adding logic to revert to 'medium' if between thresholds?
    logger.info("Decision: No change needed")
    return None

def call_control_plane_tune_api(tenant_id: str, profile_name: str):
    """Calls the Control Plane API to apply tuning settings."""
    if profile_name not in TUNING_PROFILES:
        logger.error(f"Invalid profile name '{profile_name}' requested for tenant {tenant_id}.")
        return False

    env_vars_to_set = TUNING_PROFILES[profile_name]
    tuning_url = f"{CONTROL_PLANE_URL}/tune-site/{tenant_id}"
    logger.info(f"Calling Control Plane tune API for {tenant_id} at {tuning_url} with profile '{profile_name}' ({env_vars_to_set})")

    try:
        # Get authentication token for the Control Plane URL
        # Assumes the Cloud Function's runtime service account has permissions to invoke the Control Plane service
        auth_req = google.auth.transport.requests.Request()
        id_token = google.oauth2.id_token.fetch_id_token(auth_req, CONTROL_PLANE_URL)
        headers = {"Authorization": f"Bearer {id_token}", "Content-Type": "application/json"}

        response = requests.post(tuning_url, json={"environment_variables": env_vars_to_set}, headers=headers, timeout=90) # Increased timeout for Cloud Run API call
        response.raise_for_status() # Raise HTTPError for bad responses (4xx or 5xx)

        logger.info(f"Control Plane API call successful for {tenant_id}. Response: {response.json()}")
        return True

    except requests.exceptions.RequestException as e:
        logger.error(f"Error calling Control Plane API for {tenant_id}: {e}", exc_info=True)
        if e.response is not None:
             logger.error(f"Control Plane Response Status: {e.response.status_code}, Body: {e.response.text}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error during Control Plane API call for {tenant_id}: {e}", exc_info=True)
        return False

# --- Cloud Function Entry Point ---

# Triggered by Cloud Scheduler (Pub/Sub topic recommended)
@functions_framework.cloud_event
def run_autoscaler(cloud_event):
    """ Cloud Function entry point triggered by Pub/Sub. """
    # Log basic event data (optional)
    try:
        event_data = "No data"
        if cloud_event.data and "message" in cloud_event.data and "data" in cloud_event.data["message"]:
            event_data = base64.b64decode(cloud_event.data["message"]["data"]).decode()
        logger.info(f"Received Pub/Sub event ID: {cloud_event['id']}, Data: {event_data}")
    except Exception as e:
        logger.error(f"Error processing cloud event data: {e}")

    logger.info(f"Starting autoscaler run at {datetime.now(timezone.utc)}")

    # TODO: Get ACTIVE_TENANTS list dynamically
    if not ACTIVE_TENANTS:
        logger.warning("No active tenants configured to monitor.")
        return "OK: No tenants", 200

    for tenant_id in ACTIVE_TENANTS:
        logger.info(f"--- Processing tenant: {tenant_id} ---")
        try:
            avg_cpu = get_monitoring_metric(GCP_PROJECT_ID, tenant_id)
            target_profile = get_target_profile(avg_cpu)

            if target_profile:
                # TODO: Check current tenant profile before calling API to avoid redundant updates
                success = call_control_plane_tune_api(tenant_id, target_profile)
                if not success:
                    logger.error(f"Failed to apply tuning for tenant {tenant_id}")
                    # Continue to next tenant, but maybe implement retries or alerts later
            else:
                logger.info(f"No tuning action needed for tenant {tenant_id}.")

        except Exception as e:
            # Log error but continue processing other tenants
            logger.error(f"Failed to process tenant {tenant_id}: {e}", exc_info=True)

    logger.info("Autoscaler run finished.")
    return "OK", 200 # Return success for Pub/Sub trigger


# --- Optional: HTTP Trigger for Manual Testing ---
# Use a different function name to avoid conflicts if deploying both
# @functions_framework.http
# def run_autoscaler_http(request):
#     """ Cloud Function entry point triggered by HTTP. """
#     logger.info("Starting autoscaler run triggered by HTTP.")
#     # ... (call the same core logic as pubsub handler) ...
#     logger.info("Autoscaler run finished.")
#     return "OK", 200
