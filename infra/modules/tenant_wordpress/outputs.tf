output "cloud_run_service_url" {
  description = "The URL of the deployed WordPress Cloud Run service."
  value       = google_cloud_run_v2_service.wordpress.uri
}

output "tenant_db_name" {
  description = "The name of the database created for the tenant."
  value       = google_sql_database.tenant_db.name
}

output "tenant_db_user" {
  description = "The username created for the tenant database."
  value       = google_sql_user.tenant_db_user.name
}

output "tenant_db_password_secret_version_id" {
  description = "The resource ID of the Secret Manager secret version containing the DB password."
  value       = google_secret_manager_secret_version.db_password_secret_version.id
  sensitive   = true # Mark the output itself as sensitive, though the value is just the ID
}

output "wp_content_bucket_name" {
  description = "The name of the GCS bucket created for wp-content."
  value       = google_storage_bucket.wp_content.name
}
