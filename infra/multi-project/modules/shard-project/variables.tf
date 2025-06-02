/**
 * Variables for Shard Project Module
 */

# Project Configuration
variable "project_id" {
  description = "GCP Project ID for the shard"
  type        = string
}

variable "shard_id" {
  description = "Unique identifier for this shard (e.g., aipress-shard-001)"
  type        = string
}

variable "region" {
  description = "GCP region for the shard resources"
  type        = string
}

variable "billing_account" {
  description = "GCP Billing Account ID"
  type        = string
}

variable "folder_id" {
  description = "GCP Folder ID for project organization"
  type        = string
  default     = null
}

variable "organization_id" {
  description = "GCP Organization ID"
  type        = string
  default     = null
}

# Shared Services Configuration
variable "shared_services_project_id" {
  description = "Project ID of the shared services project"
  type        = string
}

variable "shared_vpc_name" {
  description = "Name of the shared VPC network"
  type        = string
}

variable "shared_subnet_name" {
  description = "Name of the shared subnet in the region"
  type        = string
}

# Shard Configuration
variable "max_tenants_per_shard" {
  description = "Maximum number of tenants this shard can host"
  type        = number
  default     = 50
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# Resource Configuration
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# Budget Configuration
variable "enable_budget_alerts" {
  description = "Enable budget alerts for this shard"
  type        = bool
  default     = true
}

variable "monthly_budget" {
  description = "Monthly budget for this shard in USD"
  type        = number
  default     = 150
}

variable "budget_pubsub_topic" {
  description = "Pub/Sub topic for budget alerts"
  type        = string
  default     = null
}

# CI/CD Configuration
variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

# Networking Configuration
variable "additional_firewall_rules" {
  description = "Additional firewall rules for the shard"
  type = list(object({
    name = string
    allow = list(object({
      protocol = string
      ports    = optional(list(string))
    }))
    source_ranges = list(string)
  }))
  default = []
}

# Feature Flags
variable "enable_cloudsql" {
  description = "Enable Cloud SQL instance for this shard"
  type        = bool
  default     = false
}

variable "enable_redis" {
  description = "Enable Redis instance for caching"
  type        = bool
  default     = false
}

variable "enable_gke" {
  description = "Enable GKE cluster for container workloads"
  type        = bool
  default     = false
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for static content"
  type        = bool
  default     = false
}

# Control Plane Configuration
variable "control_plane_config" {
  description = "Configuration for the shard control plane"
  type = object({
    cpu_limit      = optional(string, "2")
    memory_limit   = optional(string, "4Gi")
    min_instances  = optional(number, 1)
    max_instances  = optional(number, 10)
    timeout        = optional(string, "900s")
  })
  default = {}
}

# Storage Configuration
variable "storage_config" {
  description = "Configuration for storage resources"
  type = object({
    bucket_location           = optional(string)
    enable_versioning        = optional(bool, true)
    lifecycle_age_days       = optional(number, 30)
    lifecycle_version_count  = optional(number, 3)
  })
  default = {}
}

# Monitoring Configuration
variable "monitoring_config" {
  description = "Configuration for monitoring and alerting"
  type = object({
    enable_custom_metrics     = optional(bool, true)
    enable_uptime_checks     = optional(bool, true)
    enable_error_reporting   = optional(bool, true)
    log_retention_days       = optional(number, 30)
  })
  default = {}
}

# Security Configuration
variable "security_config" {
  description = "Security configuration for the shard"
  type = object({
    enable_binary_authorization = optional(bool, false)
    enable_pod_security_policy  = optional(bool, false)
    enable_workload_identity    = optional(bool, true)
    enable_private_nodes        = optional(bool, true)
  })
  default = {}
}
