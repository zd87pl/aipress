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

  # Correct syntax based on consistent validation errors
  replication {
    auto {}
  }

  # Ensure random password is created first (usually implicit, but can be explicit)
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

# --- GCS Bucket for wp-content ---
resource "google_storage_bucket" "wp_content" {
  project       = var.gcp_project_id
  name          = "aipress-tenant-${var.tenant_id}-wp-content" # Ensure globally unique naming convention
  location      = var.gcp_region
  force_destroy = true # WARNING: Only for PoC/dev, remove for production

  uniform_bucket_level_access = true

  labels = {
    "aipress-tenant-id" = var.tenant_id # Label the bucket
  }

  # Add lifecycle rules, versioning etc. for production later
}

# Grant the WP Runtime SA access to THIS specific bucket
resource "google_storage_bucket_iam_member" "wp_runtime_bucket_access" {
  bucket = google_storage_bucket.wp_content.name
  role   = "roles/storage.objectAdmin" # Allows read, write, delete within the bucket
  member = "serviceAccount:${var.wp_runtime_sa_email}"
}

# --- Cloud SQL Database & User ---
resource "google_sql_database" "tenant_db" {
  project  = var.gcp_project_id
  instance = var.shared_sql_instance_name
  name     = replace("aipress_tenant_${var.tenant_id}", "-", "_") # Ensure valid DB name format (e.g., no hyphens)

  # No labels on database resource itself, inherits instance labels if needed for filtering costs
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

    containers {
      image = var.wp_docker_image_url
      ports { container_port = 8080 } # Assuming container listens on 8080

      # Standard WP Env Vars + GCS Bucket Name
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
            version = "latest" # Use latest version of the password secret
          }
        }
      }
      env {
        name  = "GCS_BUCKET_NAME"
        value = google_storage_bucket.wp_content.name
      }
      # TODO: Add other necessary WP env vars (salts - ideally from secrets, table prefix, etc.)
      # Example for Salts (generate random ones or pull from secrets)
      # env {
      #   name  = "WORDPRESS_AUTH_KEY"
      #   value = random_string.auth_key.result
      # }
      # ... etc for other salts
    }

    # Mount the Cloud SQL connection
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = ["${var.gcp_project_id}:${var.gcp_region}:${var.shared_sql_instance_name}"]
      }
    }
    # Re-declare containers block just to add the volume mount (Terraform quirk)
    # Must include required 'image' argument here too
    containers {
      image = var.wp_docker_image_url # Add required image argument
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
      # Add resource limits if needed
      # resources {
      #   limits = {
      #     cpu    = "1000m"
      #     memory = "512Mi"
      #   }
      # }
    }

    # TODO: Add VPC Access Connector if using Private IP for Cloud SQL
    # vpc_access {
    #   connector = "your-vpc-connector-id"
    #   egress    = "all-traffic" # Or "private-ranges-only"
    # }
  }

  # Public access is configured via google_cloud_run_service_iam_binding below

  depends_on = [
    google_secret_manager_secret_iam_member.wp_runtime_secret_access,
    google_storage_bucket_iam_member.wp_runtime_bucket_access,
    google_sql_user.tenant_db_user # Ensure DB user is created before service starts
  ]
}

# Allow unauthenticated access to the WordPress service (for PoC)
# WARNING: Remove this for production and use authenticated access (e.g., IAP)
resource "google_cloud_run_service_iam_binding" "wordpress_public_access" {
  project  = google_cloud_run_v2_service.wordpress.project
  location = google_cloud_run_v2_service.wordpress.location
  service  = google_cloud_run_v2_service.wordpress.name
  role     = "roles/run.invoker"
  members = [
    "allUsers",
  ]
}


# Placeholder for Random Salts (if not using secrets)
/*
resource "random_string" "auth_key" { length = 64 }
resource "random_string" "secure_auth_key" { length = 64 }
resource "random_string" "logged_in_key" { length = 64 }
resource "random_string" "nonce_key" { length = 64 }
resource "random_string" "auth_salt" { length = 64 }
resource "random_string" "secure_auth_salt" { length = 64 }
resource "random_string" "logged_in_salt" { length = 64 }
resource "random_string" "nonce_salt" { length = 64 }
*/
