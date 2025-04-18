variable "gcp_project_id" {
  description = "The GCP project ID where resources will be deployed."
  type        = string
  # No default, should be provided explicitly or via tfvars
}

variable "gcp_region" {
  description = "The GCP region where resources will be deployed."
  type        = string
  # Example default, adjust as needed
  default = "us-central1"
}

variable "shared_sql_instance_name" {
  description = "The name of the shared Cloud SQL instance."
  type        = string
  default     = "aipress-poc-db-shared" # Default matches setup script
}

variable "wp_runtime_sa_name" {
  description = "The name (not email) of the service account used by WordPress runtime containers."
  type        = string
  default     = "wp-runtime-sa" # Default matches setup script
}

variable "wp_docker_image_url" {
  description = "The full URL of the WordPress runtime Docker image in Artifact Registry."
  type        = string
  # Leave blank, expect it to be passed or set via tfvars/env
}

variable "tf_sa_name" {
  description = "The name (not email) of the service account used by Terraform (and potentially the Control Plane)."
  type        = string
  default     = "terraform-sa" # Default matches setup script
}

variable "control_plane_docker_image_url" {
  description = "The full URL of the Control Plane Docker image in Artifact Registry."
  type        = string
  # Leave blank, expect it to be passed or set via tfvars/env
}

variable "enable_apis" {
  description = "List of GCP APIs to enable."
  type        = list(string)
  default = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",        # Optional but useful
    "cloudresourcemanager.googleapis.com"
  ]
}

# Variables for the tenant module instance (will be overridden by Control Plane)
variable "tenant_id" {
  description = "ID for the specific tenant instance being managed by this apply."
  type        = string
  default     = "default-tenant-id" # Dummy default, always overridden
}

variable "wp_runtime_sa_email" {
  description = "Email for the specific tenant's runtime service account."
  type        = string
  default     = "dummy-sa@example.com" # Dummy default, always overridden
}
