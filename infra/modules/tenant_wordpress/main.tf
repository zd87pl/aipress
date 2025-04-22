# --- Random Password for DB ---
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# --- Secret Manager for DB Password ---
resource "google_secret_manager_secret" "db_password_secret" {
  project   = var.gcp_project_id
  secret_id = "aipress-tenant-${var.tenant_id}-db-password"

  labels = {
    "aipress-tenant-id" = var.tenant_id # Label the secret itself
  }

  replication {
    auto {}
  }

  depends_on = [random_password.db_password]
}

resource "google_secret_manager_secret_version" "db_password_secret_version" {
  secret      = google_secret_manager_secret.db_password_secret.id
  secret_data = random_password.db_password.result
}

# Grant the WP Runtime SA access to THIS specific secret version
resource "google_secret_manager_secret_iam_member" "wp_runtime_secret_access" {
  project   = split("/", google_secret_manager_secret.db_password_secret.id)[1]
  secret_id = google_secret_manager_secret.db_password_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.wp_runtime_sa_email}"
}

# --- GCS Bucket for wp-content - REMOVED ---
# resource "google_storage_bucket" "wp_content" { ... }

# Grant the WP Runtime SA access to THIS specific bucket - REMOVED ---
# resource "google_storage_bucket_iam_member" "wp_runtime_bucket_access" { ... }

# --- Cloud SQL Database & User ---
resource "google_sql_database" "tenant_db" {
  project  = var.gcp_project_id
  instance = var.shared_sql_instance_name
  name     = replace("aipress_tenant_${var.tenant_id}", "-", "_") # Ensure valid DB name format (e.g., no hyphens)
}

resource "google_sql_user" "tenant_db_user" {
  project  = var.gcp_project_id
  instance = var.shared_sql_instance_name
  name     = replace("aipress_${var.tenant_id}", "-", "_") # Ensure valid user name format
  password = random_password.db_password.result
}

# --- Cloud Run Service ---
resource "google_cloud_run_v2_service" "wordpress" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = "aipress-tenant-${var.tenant_id}"

  labels = {
    "aipress-tenant-id" = var.tenant_id # Label the service for cost tracking etc.
  }

  template {
    service_account = var.wp_runtime_sa_email

    scaling {
      min_instance_count = 0 # Enable scale-to-zero
      max_instance_count = var.max_instances # Make configurable
    }

    # Consolidated containers block
    containers {
      image = var.wp_docker_image_url
      ports { container_port = 8080 }

      # Standard WP Env Vars
      env {
        name  = "WORDPRESS_DB_HOST"
        value = "/cloudsql/${var.gcp_project_id}:${var.gcp_region}:${var.shared_sql_instance_name}"
      }
      env {
        name  = "WORDPRESS_DB_NAME"
        value = google_sql_database.tenant_db.name
      }
      env {
        name  = "WORDPRESS_DB_USER"
        value = google_sql_user.tenant_db_user.name
      }
      env {
        name = "WORDPRESS_DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password_secret.secret_id
            version = "latest"
          }
        }
      }
      # GCS_BUCKET_NAME Env Var - REMOVED
      # env {
      #   name  = "GCS_BUCKET_NAME"
      #   value = google_storage_bucket.wp_content.name
      # }
      # TODO: Add env vars for WP Offload Media plugin if needed
      
      # Add volume mount within the same containers block
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
      # resources {
      #   limits = {
      #     cpu    = "1000m"
      #     memory = "512Mi"
      #   }
      # }
    } # End of single containers block

    # Mount the Cloud SQL connection
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = ["${var.gcp_project_id}:${var.gcp_region}:${var.shared_sql_instance_name}"]
      }
    }
  } # End of template block

  # depends_on block is a direct argument of the resource
  depends_on = [
    google_secret_manager_secret_iam_member.wp_runtime_secret_access,
    # google_storage_bucket_iam_member.wp_runtime_bucket_access, # REMOVED
    google_sql_user.tenant_db_user # Ensure DB user is created before service starts
  ]

} # End of google_cloud_run_v2_service resource

# Allow unauthenticated access to the WordPress service (for PoC)
resource "google_cloud_run_service_iam_binding" "wordpress_public_access" {
  project  = google_cloud_run_v2_service.wordpress.project
  location = google_cloud_run_v2_service.wordpress.location
  service  = google_cloud_run_v2_service.wordpress.name
  role     = "roles/run.invoker"
  members = [
    "allUsers",
  ]
} # End of google_cloud_run_service_iam_binding resource
