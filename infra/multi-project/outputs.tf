/**
 * Outputs for AIPress Multi-Project Infrastructure
 */

# Shared Services Project Information
output "shared_services_project_id" {
  description = "Project ID of the shared services project"
  value       = google_project.shared_services.project_id
}

output "shared_services_project_number" {
  description = "Project number of the shared services project"
  value       = google_project.shared_services.number
}

# Organization Information
output "organization_folder_id" {
  description = "ID of the organization folder (if created)"
  value       = var.use_organization ? google_folder.aipress_hosting[0].name : null
}

# Cloud Spanner Information
output "spanner_instance_id" {
  description = "ID of the Cloud Spanner instance"
  value       = var.enable_cloud_spanner ? google_spanner_instance.global_metadata[0].name : null
}

output "spanner_database_id" {
  description = "ID of the Cloud Spanner database"
  value       = var.enable_cloud_spanner ? google_spanner_database.metadata_db[0].name : null
}

# Network Information
output "shared_vpc_name" {
  description = "Name of the shared VPC network"
  value       = google_compute_network.shared_vpc.name
}

output "shared_vpc_self_link" {
  description = "Self-link of the shared VPC network"
  value       = google_compute_network.shared_vpc.self_link
}

output "shared_subnets" {
  description = "Information about shared subnets"
  value = {
    for region, subnet in google_compute_subnetwork.shared_subnet : region => {
      name           = subnet.name
      self_link      = subnet.self_link
      ip_cidr_range  = subnet.ip_cidr_range
      region         = subnet.region
    }
  }
}

# Meta Control Plane Information
output "meta_control_plane_service_account" {
  description = "Email of the meta control plane service account"
  value       = google_service_account.meta_control_plane.email
}

output "meta_control_plane_build_trigger" {
  description = "ID of the meta control plane Cloud Build trigger"
  value       = google_cloudbuild_trigger.meta_control_plane_deploy.trigger_id
}

# Shard Projects Information
output "shard_projects" {
  description = "Information about all created shard projects"
  value = {
    for shard_key, shard_module in module.shard_projects : shard_key => shard_module.shard_info
  }
}

output "shard_project_ids" {
  description = "List of all shard project IDs"
  value       = [for shard_module in module.shard_projects : shard_module.project_id]
}

output "shard_control_plane_urls" {
  description = "List of all shard control plane URLs"
  value = {
    for shard_key, shard_module in module.shard_projects : shard_key => shard_module.control_plane_url
  }
}

# Health Check Endpoints
output "health_check_endpoints" {
  description = "All health check endpoints for monitoring"
  value = {
    meta_control_plane = "https://meta-control-plane-${random_id.suffix.hex}.run.app/health"
    shards = {
      for shard_key, shard_module in module.shard_projects : shard_key => shard_module.health_check_endpoints
    }
  }
}

# Storage Information
output "storage_buckets" {
  description = "Storage buckets for each shard"
  value = {
    for shard_key, shard_module in module.shard_projects : shard_key => {
      name = shard_module.storage_bucket_name
      url  = shard_module.storage_bucket_url
    }
  }
}

# Budget Information
output "budget_names" {
  description = "Budget names for cost tracking"
  value = {
    for shard_key, shard_module in module.shard_projects : shard_key => shard_module.budget_name
  }
}

# Security Information
output "service_accounts" {
  description = "Service accounts for all components"
  value = {
    meta_control_plane = google_service_account.meta_control_plane.email
    shards = {
      for shard_key, shard_module in module.shard_projects : shard_key => shard_module.control_plane_service_account
    }
  }
}

# Federation Summary
output "federation_summary" {
  description = "Complete federation summary for operational dashboards"
  value = {
    total_projects        = length(module.shard_projects) + 1 # +1 for shared services
    total_shards         = length(module.shard_projects)
    max_total_tenants    = length(module.shard_projects) * var.max_tenants_per_shard
    deployment_regions   = var.deployment_regions
    shared_services = {
      project_id     = google_project.shared_services.project_id
      spanner_instance = var.enable_cloud_spanner ? google_spanner_instance.global_metadata[0].name : null
      vpc_network    = google_compute_network.shared_vpc.name
    }
    estimated_monthly_cost = length(module.shard_projects) * var.monthly_budget_per_shard
    created_at = timestamp()
  }
}

# Configuration for Meta Control Plane
output "meta_control_plane_config" {
  description = "Configuration to pass to meta control plane"
  value = {
    num_shards = length(module.shard_projects)
    target_shard_count = var.target_shard_count
    sites_per_shard = var.max_tenants_per_shard
    organization_id = var.organization_id
    billing_account = var.billing_account_id
    spanner_instance = var.enable_cloud_spanner ? google_spanner_instance.global_metadata[0].name : null
    spanner_database = var.enable_cloud_spanner ? google_spanner_database.metadata_db[0].name : null
    shared_services_project = google_project.shared_services.project_id
  }
  sensitive = true
}

# Terraform State Information
output "terraform_state_info" {
  description = "Information about Terraform state management"
  value = {
    workspace = terraform.workspace
    version   = "1.0.0"
    last_applied = timestamp()
    resources_created = {
      projects = length(module.shard_projects) + 1
      networks = 1
      subnets  = length(var.deployment_regions)
      service_accounts = length(module.shard_projects) + 1
      storage_buckets = length(module.shard_projects)
    }
  }
}

# Random suffix for unique naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Regional Distribution
output "regional_distribution" {
  description = "Distribution of shards across regions"
  value = {
    for region in var.deployment_regions : region => length([
      for shard_key, shard_module in module.shard_projects : shard_module.region
      if shard_module.region == region
    ])
  }
}

# URLs for Direct Access
output "access_urls" {
  description = "Direct access URLs for management"
  value = {
    cloud_console_organization = var.use_organization ? "https://console.cloud.google.com/home/dashboard?organizationId=${var.organization_id}" : null
    cloud_console_shared_services = "https://console.cloud.google.com/home/dashboard?project=${google_project.shared_services.project_id}"
    spanner_console = var.enable_cloud_spanner ? "https://console.cloud.google.com/spanner/instances/${google_spanner_instance.global_metadata[0].name}/databases/${google_spanner_database.metadata_db[0].name}/tables?project=${google_project.shared_services.project_id}" : null
    monitoring_dashboard = "https://console.cloud.google.com/monitoring?project=${google_project.shared_services.project_id}"
    logging_dashboard = "https://console.cloud.google.com/logs?project=${google_project.shared_services.project_id}"
  }
}
