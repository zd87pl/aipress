terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.36.0" # Pin to a specific recent 5.x version
    }
  }
  # Optional: Configure backend for this bootstrap config if desired
  # backend "gcs" {
  #   bucket  = "aipress-tf-state-aipress-project" # Same bucket as main infra
  #   prefix  = "infra-bootstrap" # Separate prefix
  # }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  # Credentials should be handled via Application Default Credentials (ADC)
  # or by setting the GOOGLE_APPLICATION_CREDENTIALS environment variable
}

# --- API Enablement Resource ---
# Enable necessary APIs for the project
resource "google_project_service" "apis" {
  for_each = toset(var.enable_apis)
  project  = var.gcp_project_id
  service  = each.key
  disable_dependent_services = false
}

# --- Control Plane Cloud Run Service ---


resource "google_cloud_run_v2_service" "control_plane" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = "aipress-control-plane" # Name for the control plane service

  template {
    # Use the Terraform SA for this service
    service_account = "${var.tf_sa_name}@${var.gcp_project_id}.iam.gserviceaccount.com"
    # Increase timeout to allow for longer Terraform operations
    timeout = "900s" # Correct argument name is 'timeout', value is string like "900s"

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = var.control_plane_docker_image_url
      ports { container_port = 8000 }

      # Pass necessary environment variables to the control plane container
      env {
        name  = "GCP_PROJECT_ID"
        value = var.gcp_project_id
      }
      env {
        name  = "GCP_REGION"
        value = var.gcp_region
      }
      env {
        name  = "SHARED_SQL_INSTANCE_NAME"
        value = var.shared_sql_instance_name
      }
      env {
        name  = "WP_RUNTIME_SA_NAME"
        value = var.wp_runtime_sa_name
      }
      env {
        name  = "WP_DOCKER_IMAGE_URL"
        value = var.wp_docker_image_url
      }
      env {
        name  = "CONTROL_PLANE_DOCKER_IMAGE_URL"
        value = var.control_plane_docker_image_url
      }
      env {
        name  = "FORCE_REDEPLOY_TIMESTAMP" # Dummy variable to force update
        value = timestamp()
      }
      # TF_MAIN_PATH is handled inside the container relative to /app
      # GOOGLE_APPLICATION_CREDENTIALS is not needed when using service account identity
    }
  }

  depends_on = [google_project_service.apis]
}

# Grant the Cloud Run invoker role on the control plane service to specified
# members. By default no bindings are created, keeping the service private until
# access is explicitly granted.
resource "google_cloud_run_service_iam_member" "control_plane_invoker" {
  for_each = toset(var.control_plane_invoker_members)

  project  = google_cloud_run_v2_service.control_plane.project
  location = google_cloud_run_v2_service.control_plane.location
  service  = google_cloud_run_v2_service.control_plane.name
  role     = "roles/run.invoker"
  member   = each.key
}
