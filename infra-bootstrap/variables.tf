variable "gcp_project_id" {
  description = "The GCP project ID where resources will be deployed."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region where resources will be deployed."
  type        = string
  default     = "us-central1"
}

variable "tf_sa_name" {
  description = "The name (not email) of the service account used by Terraform and the Control Plane."
  type        = string
  default     = "terraform-sa" # Default matches setup script
}

variable "control_plane_docker_image_url" {
  description = "The full URL of the Control Plane Docker image in Artifact Registry."
  type        = string
  # Expect this to be passed via -var flag during apply
}

variable "wp_docker_image_url" {
  description = "The full URL of the WordPress runtime Docker image (needed for CP env var)."
  type        = string
  # Expect this to be passed via -var flag during apply
}

variable "wp_runtime_sa_name" {
  description = "The name (not email) of the service account used by WordPress runtime containers (needed for CP env var)."
  type        = string
  default     = "wp-runtime-sa" # Default matches setup script
}

variable "shared_sql_instance_name" {
  description = "The name of the shared Cloud SQL instance (needed for CP env var)."
  type        = string
  default     = "aipress-poc-db-shared" # Default matches setup script
}

# Members allowed to invoke the Control Plane Cloud Run service. Leaving this
# empty keeps the service private until explicit access is granted.
variable "control_plane_invoker_members" {
  description = "IAM members granted Cloud Run invoker on the control plane"
  type        = list(string)
  default     = []
}

variable "enable_apis" {
  description = "List of GCP APIs to enable for the project."
  type        = list(string)
  default = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
}
