variable "tenant_id" {
  description = "Unique identifier for the tenant."
  type        = string
  # Add validation if needed
}

variable "gcp_project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region."
  type        = string
}

variable "shared_sql_instance_name" {
  description = "Name of the shared Cloud SQL instance."
  type        = string
}

variable "wp_runtime_sa_email" {
  description = "Email of the service account the Cloud Run service will use."
  type        = string
}

variable "wp_docker_image_url" {
  description = "Full URL of the WordPress runtime Docker image."
  type        = string
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances for scaling."
  type        = number
  default     = 10 # Default, adjust as needed
}

# List of IAM members allowed to invoke the tenant's WordPress service. Leave
# empty to restrict access until bindings are explicitly added (recommended for
# production to avoid public exposure).
variable "invoker_members" {
  description = "IAM members granted the Cloud Run invoker role for this service"
  type        = list(string)
  default     = []
}

# Add other variables as needed, e.g., CPU/Memory limits, custom env vars later
