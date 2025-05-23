terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.36.0" # Pin to a specific recent 5.x version
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  # Configure Terraform backend using GCS bucket created by setup script
  backend "gcs" {
    bucket  = "aipress-tf-state-wp-engine-ziggy" # !!! UPDATE MANUALLY if project ID changes from setup script !!!
    prefix  = "infra/poc" # Tenants will use workspaces within this prefix
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  # Credentials assumed to be handled by the environment (e.g., Cloud Run SA)
}

# --- Tenant Module Invocation Placeholder ---
# The Control Plane will override tenant_id and wp_runtime_sa_email via -var flags
# when applying this configuration within a specific tenant workspace.
module "tenant_wordpress_instance" {
  source = "./modules/tenant_wordpress"

  # These variables will be overridden by the control plane's -var flags
  tenant_id                = var.tenant_id           # Use variable
  wp_runtime_sa_email      = var.wp_runtime_sa_email # Use variable

  # These are consistent across tenants for this PoC
  gcp_project_id           = var.gcp_project_id
  gcp_region               = var.gcp_region
  shared_sql_instance_name = var.shared_sql_instance_name
  wp_docker_image_url      = var.wp_docker_image_url # Passed via -var to root

  # Cloud Run IAM members allowed to invoke the tenant service
  invoker_members = var.wordpress_invoker_members

  # sql_password_secret_id - Module generates this
}
