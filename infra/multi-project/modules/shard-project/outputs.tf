/**
 * Outputs for Shard Project Module
 */

output "project_id" {
  description = "The GCP project ID for this shard"
  value       = google_project.shard.project_id
}

output "project_number" {
  description = "The GCP project number for this shard"
  value       = google_project.shard.number
}

output "shard_id" {
  description = "The shard identifier"
  value       = var.shard_id
}

output "region" {
  description = "The region where shard resources are deployed"
  value       = var.region
}

output "control_plane_url" {
  description = "URL of the shard control plane service"
  value       = google_cloud_run_v2_service.shard_control_plane.uri
}

output "control_plane_service_account" {
  description = "Email of the shard control plane service account"
  value       = google_service_account.shard_control_plane.email
}

output "storage_bucket_name" {
  description = "Name of the WordPress files storage bucket"
  value       = google_storage_bucket.wordpress_files.name
}

output "storage_bucket_url" {
  description = "URL of the WordPress files storage bucket"
  value       = google_storage_bucket.wordpress_files.url
}

output "vpc_connector_id" {
  description = "ID of the VPC access connector"
  value       = google_vpc_access_connector.shard.id
}

output "database_secret_id" {
  description = "Secret Manager secret ID for database credentials"
  value       = google_secret_manager_secret.db_credentials.secret_id
}

output "monitoring_project" {
  description = "Project ID where monitoring data is sent"
  value       = var.shared_services_project_id
}

output "log_sink_writer_identity" {
  description = "Writer identity for the log sink"
  value       = google_logging_project_sink.shard_logs.writer_identity
}

output "budget_name" {
  description = "Name of the budget for this shard"
  value       = var.enable_budget_alerts ? google_billing_budget.shard_budget[0].display_name : null
}

output "cloud_build_trigger_id" {
  description = "ID of the Cloud Build trigger for CI/CD"
  value       = google_cloudbuild_trigger.shard_control_plane_deploy.trigger_id
}

# Resource summary for meta control plane
output "shard_info" {
  description = "Complete shard information for meta control plane registration"
  value = {
    shard_id            = var.shard_id
    project_id          = google_project.shard.project_id
    project_number      = google_project.shard.number
    region              = var.region
    control_plane_url   = google_cloud_run_v2_service.shard_control_plane.uri
    max_tenants         = var.max_tenants_per_shard
    storage_bucket      = google_storage_bucket.wordpress_files.name
    service_account     = google_service_account.shard_control_plane.email
    created_at          = google_project.shard.create_time
    labels              = local.common_labels
  }
}

# Health check endpoints
output "health_check_endpoints" {
  description = "Endpoints for health monitoring"
  value = {
    control_plane_health = "${google_cloud_run_v2_service.shard_control_plane.uri}/health"
    control_plane_metrics = "${google_cloud_run_v2_service.shard_control_plane.uri}/metrics"
  }
}

# Network information
output "network_info" {
  description = "Network configuration information"
  value = {
    shared_vpc_project  = var.shared_services_project_id
    shared_vpc_name     = var.shared_vpc_name
    shared_subnet_name  = var.shared_subnet_name
    vpc_connector_name  = google_vpc_access_connector.shard.name
  }
}

# Security information
output "security_info" {
  description = "Security configuration information"
  value = {
    service_account_email = google_service_account.shard_control_plane.email
    database_secret_name  = google_secret_manager_secret.db_credentials.secret_id
    iam_roles = [
      "roles/cloudsql.client",
      "roles/storage.admin",
      "roles/secretmanager.accessor",
      "roles/monitoring.metricWriter",
      "roles/logging.logWriter",
      "roles/cloudtrace.agent",
      "roles/cloudprofiler.agent",
      "roles/run.invoker"
    ]
  }
}
