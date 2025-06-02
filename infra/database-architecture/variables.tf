/**
 * Variables for AIPress Shared Database Architecture
 * 
 * Configures the shared Cloud SQL setup with connection pooling
 * for cost optimization and scaling to 50,000+ WordPress sites.
 */

# Project Configuration
variable "shared_services_project_id" {
  description = "Project ID for shared services"
  type        = string
}

variable "deployment_regions" {
  description = "List of regions for database deployment"
  type        = list(string)
  default = [
    "us-central1",
    "us-east1",
    "europe-west1",
    "asia-southeast1"
  ]
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Network Configuration
variable "shared_vpc_self_link" {
  description = "Self-link of the shared VPC network"
  type        = string
}

variable "vpc_connector_name" {
  description = "Name of the VPC connector for Cloud Run services"
  type        = string
}

# Database Instance Configuration
variable "shared_instances_per_region" {
  description = "Number of shared Cloud SQL instances per region"
  type        = number
  default     = 2
  
  validation {
    condition     = var.shared_instances_per_region >= 1 && var.shared_instances_per_region <= 10
    error_message = "Shared instances per region must be between 1 and 10."
  }
}

variable "databases_per_instance" {
  description = "Maximum number of databases per Cloud SQL instance"
  type        = number
  default     = 100
  
  validation {
    condition     = var.databases_per_instance >= 10 && var.databases_per_instance <= 200
    error_message = "Databases per instance must be between 10 and 200."
  }
}

variable "database_version" {
  description = "MySQL version for Cloud SQL instances"
  type        = string
  default     = "MYSQL_8_0"
  
  validation {
    condition     = contains(["MYSQL_8_0", "MYSQL_5_7"], var.database_version)
    error_message = "Database version must be MYSQL_8_0 or MYSQL_5_7."
  }
}

variable "database_tier" {
  description = "Machine type for Cloud SQL instances"
  type        = string
  default     = "db-custom-8-32768" # 8 vCPUs, 32GB RAM
  
  validation {
    condition     = can(regex("^db-(custom|standard|highmem)", var.database_tier))
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "database_disk_size" {
  description = "Initial disk size in GB for Cloud SQL instances"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.database_disk_size >= 100 && var.database_disk_size <= 10000
    error_message = "Database disk size must be between 100GB and 10TB."
  }
}

variable "database_max_disk_size" {
  description = "Maximum disk size in GB for auto-resize"
  type        = number
  default     = 5000
  
  validation {
    condition     = var.database_max_disk_size >= var.database_disk_size
    error_message = "Maximum disk size must be >= initial disk size."
  }
}

variable "high_availability" {
  description = "Enable high availability (regional) for Cloud SQL instances"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for Cloud SQL instances"
  type        = bool
  default     = true
}

# Connection and Performance Configuration
variable "max_connections_per_instance" {
  description = "Maximum connections per Cloud SQL instance"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.max_connections_per_instance >= 100 && var.max_connections_per_instance <= 4000
    error_message = "Max connections per instance must be between 100 and 4000."
  }
}

variable "max_connections_per_tenant" {
  description = "Maximum connections per tenant (via ProxySQL)"
  type        = number
  default     = 20
  
  validation {
    condition     = var.max_connections_per_tenant >= 5 && var.max_connections_per_tenant <= 100
    error_message = "Max connections per tenant must be between 5 and 100."
  }
}

variable "connection_timeout" {
  description = "Connection timeout in seconds"
  type        = number
  default     = 30
}

variable "query_timeout" {
  description = "Query timeout in seconds"
  type        = number
  default     = 300
}

variable "max_query_size" {
  description = "Maximum query size in bytes"
  type        = number
  default     = 16777216 # 16MB
}

# Read Replica Configuration
variable "enable_read_replicas" {
  description = "Enable read replicas for performance"
  type        = bool
  default     = true
}

variable "replica_tier" {
  description = "Machine type for read replicas"
  type        = string
  default     = "db-custom-4-16384" # 4 vCPUs, 16GB RAM
}

# ProxySQL Configuration
variable "proxysql_image" {
  description = "Docker image for ProxySQL"
  type        = string
  default     = "gcr.io/aipress-shared-services/proxysql:latest"
}

variable "proxysql_min_instances" {
  description = "Minimum ProxySQL instances per region"
  type        = number
  default     = 2
}

variable "proxysql_max_instances" {
  description = "Maximum ProxySQL instances per region"
  type        = number
  default     = 20
}

variable "proxysql_cpu_limit" {
  description = "CPU limit for ProxySQL containers"
  type        = string
  default     = "2"
}

variable "proxysql_memory_limit" {
  description = "Memory limit for ProxySQL containers"
  type        = string
  default     = "4Gi"
}

# Cost Optimization
variable "cost_optimization_config" {
  description = "Configuration for cost optimization features"
  type = object({
    enable_automatic_scaling   = optional(bool, true)
    scale_down_threshold      = optional(number, 0.3)
    scale_up_threshold        = optional(number, 0.7)
    min_idle_connections      = optional(number, 10)
    max_idle_connections      = optional(number, 100)
    connection_idle_timeout   = optional(number, 300)
  })
  default = {}
}

# Monitoring and Alerting
variable "notification_channels" {
  description = "List of notification channels for alerts"
  type        = list(string)
  default     = []
}

variable "monitoring_config" {
  description = "Monitoring and alerting configuration"
  type = object({
    cpu_threshold             = optional(number, 0.8)
    memory_threshold          = optional(number, 0.85)
    disk_threshold           = optional(number, 0.9)
    connection_threshold     = optional(number, 0.85)
    slow_query_threshold     = optional(number, 2.0)
    enable_performance_insights = optional(bool, true)
  })
  default = {}
}

# Security Configuration
variable "security_config" {
  description = "Security configuration for databases"
  type = object({
    require_ssl                = optional(bool, true)
    enable_audit_logging      = optional(bool, true)
    password_validation       = optional(bool, true)
    min_password_length       = optional(number, 12)
    encryption_at_rest        = optional(bool, true)
  })
  default = {}
}

# Backup and Recovery Configuration
variable "backup_config" {
  description = "Backup and recovery configuration"
  type = object({
    backup_start_time         = optional(string, "03:00")
    backup_retention_days     = optional(number, 30)
    enable_point_in_time_recovery = optional(bool, true)
    transaction_log_retention_days = optional(number, 7)
    cross_region_backup       = optional(bool, false)
  })
  default = {}
}

# Migration Configuration
variable "migration_config" {
  description = "Configuration for migrating from dedicated instances"
  type = object({
    enable_migration_mode     = optional(bool, false)
    batch_size               = optional(number, 10)
    migration_window_hours   = optional(list(number), [2, 3, 4])
    rollback_enabled         = optional(bool, true)
    dry_run_mode            = optional(bool, true)
  })
  default = {}
}

# Labels and Tagging
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# Feature Flags
variable "feature_flags" {
  description = "Feature flags for experimental or optional features"
  type = object({
    enable_query_optimization = optional(bool, true)
    enable_connection_pooling = optional(bool, true)
    enable_read_write_split   = optional(bool, true)
    enable_cache_warming      = optional(bool, false)
    enable_auto_failover      = optional(bool, true)
    enable_schema_migration   = optional(bool, false)
  })
  default = {}
}

# Development and Testing
variable "development_config" {
  description = "Configuration for development and testing environments"
  type = object({
    enable_debug_logging      = optional(bool, false)
    enable_query_logging      = optional(bool, false)
    enable_performance_testing = optional(bool, false)
    test_data_generation     = optional(bool, false)
  })
  default = {}
}

# Capacity Planning
variable "capacity_planning" {
  description = "Capacity planning configuration"
  type = object({
    expected_growth_rate      = optional(number, 0.2) # 20% monthly growth
    peak_load_multiplier     = optional(number, 3.0)  # 3x normal load during peaks
    seasonal_adjustment      = optional(number, 1.5)  # 1.5x during busy seasons
    buffer_percentage        = optional(number, 0.25) # 25% buffer capacity
  })
  default = {}
}
