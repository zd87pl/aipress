# --- Random Password for DB ---
resource "random_password" "db_password" {
  length           = 16
  # Removed special = true and override_special
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

# --- WordPress Salts/Keys Generation and Secret Storage ---
locals {
  wp_salt_keys = [
    "auth_key",
    "secure_auth_key",
    "logged_in_key",
    "nonce_key",
    "auth_salt",
    "secure_auth_salt",
    "logged_in_salt",
    "nonce_salt",
  ]
}

resource "random_password" "wp_salts" {
  for_each = toset(local.wp_salt_keys)
  length   = 64
  special  = true
  # Use a broader special character set suitable for WP salts
  override_special = "!@#$%^&*()-_=+[]{};:,./<>?~"
}

resource "google_secret_manager_secret" "wp_salt_secrets" {
  for_each  = toset(local.wp_salt_keys)
  project   = var.gcp_project_id
  secret_id = "aipress-tenant-${var.tenant_id}-wp-${replace(each.key, "_", "-")}" # e.g., aipress-tenant-xyz-wp-auth-key

  labels = {
    "aipress-tenant-id" = var.tenant_id
    "aipress-secret-type" = "wp-salt"
  }

  replication {
    auto {}
  }

  depends_on = [random_password.wp_salts] # Ensure random value is generated first
}

resource "google_secret_manager_secret_version" "wp_salt_secret_versions" {
  for_each    = google_secret_manager_secret.wp_salt_secrets
  secret      = each.value.id
  secret_data = random_password.wp_salts[each.key].result
}

# Grant the WP Runtime SA access to EACH salt secret
resource "google_secret_manager_secret_iam_member" "wp_runtime_salt_secret_access" {
  for_each  = google_secret_manager_secret.wp_salt_secrets
  project   = split("/", each.value.id)[1]
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.wp_runtime_sa_email}"
}


# --- GCS Bucket for Stateless Plugin ---
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "stateless_media" {
  project       = var.gcp_project_id
  # Bucket names must be globally unique
  name          = "aipress-${var.tenant_id}-media-${random_id.bucket_suffix.hex}"
  location      = var.gcp_region
  force_destroy = false # Set to true only for non-prod/testing
  uniform_bucket_level_access = true

  labels = {
    "aipress-tenant-id" = var.tenant_id
  }
}

# Grant the WP Runtime SA access to THIS specific bucket
resource "google_storage_bucket_iam_member" "stateless_media_rw" {
  bucket = google_storage_bucket.stateless_media.name
  role   = "roles/storage.objectAdmin" # Allows read/write/delete objects
  member = "serviceAccount:${var.wp_runtime_sa_email}"
}

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
  host     = "%" # Allow connection from any host (incl. Cloud SQL Proxy)
  password = random_password.db_password.result
}


# --- Cloud Run Service ---
resource "google_cloud_run_v2_service" "wordpress" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = "aipress-tenant-${var.tenant_id}"

  labels = {
    "aipress-tenant-id" = var.tenant_id # Label the service for cost tracking etc.
    # "dummy-redeployment-trigger" = "2" # Removing dummy label
  }

  template {
    service_account = var.wp_runtime_sa_email

    scaling {
      min_instance_count = 0 # Enable scale-to-zero
      max_instance_count = var.max_instances # Make configurable
    }

    # Mount Cloud SQL socket
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = ["${var.gcp_project_id}:${var.gcp_region}:${var.shared_sql_instance_name}"]
      }
    }

    containers {
      image = var.wp_docker_image_url
      ports { container_port = 8080 }

      # Mount the Cloud SQL socket volume
      volume_mounts {
        name      = "cloudsql" # Must match the volume name above
        mount_path = "/cloudsql"
      }

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

      # Env Vars for WP Offload Media (S3 Compatibility Mode)
      # Assumes plugin is configured to use env vars and S3 provider with GCS endpoint/creds
      env {
        name = "AS3CF_PROVIDER"
        value = "aws" # Use 'aws' provider for S3 compatibility
      }
      env {
        name = "AS3CF_BUCKET"
        value = google_storage_bucket.stateless_media.name
      }
      env {
        name = "AS3CF_REGION"
        value = var.gcp_region # GCS region
      }
      env {
        name = "AS3CF_SETTINGS" # JSON string for other settings if needed
        value = jsonencode({
          "use-server-roles" : true, # Use attached Service Account
          "enable-object-prefix": true, # Recommended: Store files under wp-content/uploads prefix
          "object-prefix": "wp-content/uploads/",
          "copy-to-s3": true, # Upload files
          "serve-from-s3": true, # Serve files from GCS
          # "force-https": true # Optional
        })
      }
      # Add standard WordPress salts/keys from dynamically created secrets
      env {
        name = "WORDPRESS_AUTH_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.wp_salt_secrets["auth_key"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "WORDPRESS_SECURE_AUTH_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.wp_salt_secrets["secure_auth_key"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "WORDPRESS_LOGGED_IN_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.wp_salt_secrets["logged_in_key"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "WORDPRESS_NONCE_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.wp_salt_secrets["nonce_key"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "WORDPRESS_AUTH_SALT"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.wp_salt_secrets["auth_salt"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "WORDPRESS_SECURE_AUTH_SALT"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.wp_salt_secrets["secure_auth_salt"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "WORDPRESS_LOGGED_IN_SALT"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.wp_salt_secrets["logged_in_salt"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "WORDPRESS_NONCE_SALT"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.wp_salt_secrets["nonce_salt"].secret_id
            version = "latest"
          }
        }
      }
      env {
         name = "WORDPRESS_DEBUG" # Optional: control WP_DEBUG
         value = "false" # Set to "true" for debugging if needed
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
    } # End of single containers block

  } # End of template block

  # depends_on block is a direct argument of the resource
  depends_on = [
    google_secret_manager_secret_iam_member.wp_runtime_secret_access, # For DB password
    google_secret_manager_secret_iam_member.wp_runtime_salt_secret_access, # For WP salts/keys
    google_storage_bucket_iam_member.stateless_media_rw, # Ensure bucket permission is set
    google_sql_user.tenant_db_user # Ensure DB user is created before service starts
  ]

} # End of google_cloud_run_v2_service resource


# Grant the Cloud Run invoker role to specified IAM members. By default no
# members are bound, meaning the service requires authentication and access must
# be explicitly granted.
resource "google_cloud_run_service_iam_member" "wordpress_invoker" {
  for_each = toset(var.invoker_members)

  project  = google_cloud_run_v2_service.wordpress.project
  location = google_cloud_run_v2_service.wordpress.location
  service  = google_cloud_run_v2_service.wordpress.name
  role     = "roles/run.invoker"
  member   = each.key
}
