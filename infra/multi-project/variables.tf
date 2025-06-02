/**
 * Variables for AIPress Multi-Project Infrastructure
 * 
 * These variables configure the multi-project federation setup
 * for scaling to 50,000+ WordPress sites.
 */

# Organization and Project Configuration
variable "organization_id" {
  description = "GCP Organization ID for AIPress hosting"
  type        = string
  default     = null
}

variable "organization_project_id" {
  description = "GCP Project ID for organization-level resources"
  type        = string
}

variable "shared_services_project_id" {
  description = "Project ID for shared services (meta control plane, Spanner, etc.)"
  type        = string
  default     = "aipress-shared-services"
}

variable "billing_account_id" {
  description = "GCP Billing Account ID"
  type        = string
}

variable "use_organization" {
  description = "Whether to use GCP Organization for project management"
  type        = bool
  default     = true
}

# Regional Configuration
variable "default_region" {
  description = "Default GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "deployment_regions" {
  description = "List of GCP regions to deploy infrastructure"
  type        = list(string)
  default = [
    "us-central1",
    "us-east1",
    "europe-west1",
    "asia-southeast1"
  ]
}

# Shard Configuration
variable "initial_shard_count" {
  description = "Number of initial shard projects to create"
  type        = number
  default     = 3
  
  validation {
    condition     = var.initial_shard_count >= 1 && var.initial_shard_count <= 100
    error_message = "Initial shard count must be between 1 and 100."
  }
}

variable "target_shard_count" {
  description = "Target number of shards for full scale (up to 1000)"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.target_shard_count >= 1 && var.target_shard_count <= 1000
    error_message = "Target shard count must be between 1 and 1000."
  }
}

variable "max_tenants_per_shard" {
  description = "Maximum number of tenants (WordPress sites) per shard"
  type        = number
  default     = 50
  
  validation {
    condition     = var.max_tenants_per_shard >= 1 && var.max_tenants_per_shard <= 100
    error_message = "Max tenants per shard must be between 1 and 100."
  }
}

# Cloud Spanner Configuration
variable "enable_cloud_spanner" {
  description = "Whether to deploy Cloud Spanner for global metadata"
  type        = bool
  default     = true
}

variable "spanner_processing_units" {
  description = "Processing units for Cloud Spanner instance"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.spanner_processing_units >= 1000
    error_message = "Spanner processing units must be at least 1000."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# GitHub Configuration for CI/CD
variable "github_owner" {
  description = "GitHub repository owner/organization"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

# Network Configuration
variable "shared_vpc_cidr" {
  description = "CIDR block for shared VPC network"
  type        = string
  default     = "10.0.0.0/8"
}

variable "enable_private_google_access" {
  description = "Enable private Google access for subnets"
  type        = bool
  default     = true
}

# Security Configuration
variable "allowed_source_ranges" {
  description = "CIDR ranges allowed for SSH access"
  type        = list(string)
  default     = ["35.235.240.0/20"] # Google Cloud IAP
}

# Database Configuration
variable "enable_shared_cloudsql" {
  description = "Whether to deploy shared Cloud SQL instances"
  type        = bool
  default     = false # Will be enabled in database architecture phase
}

variable "cloudsql_tier" {
  description = "Cloud SQL instance tier for shared databases"
  type        = string
  default     = "db-custom-4-16384" # 4 vCPUs, 16GB RAM
}

variable "cloudsql_disk_size" {
  description = "Disk size in GB for Cloud SQL instances"
  type        = number
  default     = 500
}

# Monitoring and Logging
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for all projects"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for all projects"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
}

# Cost Management
variable "enable_budget_alerts" {
  description = "Enable budget alerts for cost management"
  type        = bool
  default     = true
}

variable "monthly_budget_per_shard" {
  description = "Monthly budget per shard in USD"
  type        = number
  default     = 150 # Target: $150/month per shard (50 sites = $3/site)
}

# Backup Configuration
variable "enable_automated_backups" {
  description = "Enable automated backup system"
  type        = bool
  default     = false # Will be enabled in backup phase
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
}

# Development Configuration
variable "enable_development_features" {
  description = "Enable development and debugging features"
  type        = bool
  default     = false
}

variable "create_test_tenants" {
  description = "Create test tenants for validation"
  type        = bool
  default     = false
}

# Resource Labels
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# Feature Flags
variable "feature_flags" {
  description = "Feature flags for experimental features"
  type = object({
    enable_cloud_armor      = bool
    enable_cdn             = bool
    enable_ssl_certificates = bool
    enable_load_balancing  = bool
    enable_autoscaling     = bool
  })
  default = {
    enable_cloud_armor      = false
    enable_cdn             = false
    enable_ssl_certificates = false
    enable_load_balancing  = false
    enable_autoscaling     = false
  }
}

# Meta Control Plane Configuration
variable "meta_control_plane_config" {
  description = "Configuration for meta control plane deployment"
  type = object({
    cpu_limit      = string
    memory_limit   = string
    min_instances  = number
    max_instances  = number
    timeout        = string
  })
  default = {
    cpu_limit      = "2"
    memory_limit   = "4Gi"
    min_instances  = 1
    max_instances  = 10
    timeout        = "900s"
  }
}

# Validation Configuration
variable "validation_config" {
  description = "Configuration for infrastructure validation"
  type = object({
    enable_health_checks    = bool
    health_check_interval  = string
    enable_smoke_tests     = bool
    enable_load_tests      = bool
  })
  default = {
    enable_health_checks    = true
    health_check_interval  = "300s"
    enable_smoke_tests     = true
    enable_load_tests      = false
  }
}
