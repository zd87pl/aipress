/**
 * Outputs for AIPress Shared Database Architecture
 */

# Database Instance Information
output "shared_database_instances" {
  description = "Information about shared Cloud SQL instances"
  value = {
    for instance_key, instance in google_sql_database_instance.shared_instances : instance_key => {
      name               = instance.name
      connection_name    = instance.connection_name
      private_ip_address = instance.private_ip_address
      region            = instance.region
      tier              = instance.settings[0].tier
      database_version  = instance.database_version
      self_link         = instance.self_link
    }
  }
}

output "read_replica_instances" {
  description = "Information about read replica instances"
  value = var.enable_read_replicas ? {
    for replica_key, replica in google_sql_database_instance.read_replicas : replica_key => {
      name               = replica.name
      connection_name    = replica.connection_name
      private_ip_address = replica.private_ip_address
      region            = replica.region
      tier              = replica.settings[0].tier
      master_instance    = replica.master_instance_name
    }
  } : {}
}

# ProxySQL Information
output "proxysql_services" {
  description = "ProxySQL connection pooling service URLs"
  value = {
    for region, service in google_cloud_run_v2_service.proxysql : region => {
      url    = service.uri
      region = service.location
      name   = service.name
    }
  }
}

# Database Capacity Information
output "database_capacity" {
  description = "Database capacity information across all regions"
  value = {
    total_instances           = length(google_sql_database_instance.shared_instances)
    databases_per_instance    = local.databases_per_instance
    total_database_capacity   = local.total_database_capacity
    regions                   = var.deployment_regions
    shared_instances_per_region = var.shared_instances_per_region
  }
}

# Cost Optimization Information
output "cost_optimization_summary" {
  description = "Cost optimization summary and projections"
  value = {
    estimated_monthly_cost_per_instance = "~$400" # Based on db-custom-8-32768
    estimated_cost_per_database        = "~$4"    # $400/100 databases
    cost_savings_vs_dedicated           = "~$84"   # $88-$4 per database
    total_estimated_monthly_savings     = "${local.total_database_capacity * 84}" # Projected savings
    break_even_point_databases          = 100     # Break-even at 100 databases per instance
  }
}

# Security Information
output "database_security" {
  description = "Database security configuration"
  value = {
    ssl_required              = true
    private_network_only      = true
    vpc_network              = var.shared_vpc_self_link
    credential_secret_id     = google_secret_manager_secret.db_credentials.secret_id
    proxysql_admin_secret_id = google_secret_manager_secret.proxysql_admin.secret_id
    user_types               = ["app_user", "readonly_user", "admin_user"]
  }
}

# Automation Information
output "database_automation" {
  description = "Database automation and provisioning information"
  value = {
    provisioner_function_name = google_cloudfunctions2_function.db_provisioner.name
    provisioner_trigger_topic = google_pubsub_topic.db_provisioning_requests.name
    service_account_email     = google_service_account.db_provisioner.email
    source_bucket            = google_storage_bucket.db_provisioner_source.name
  }
}

# Monitoring and Alerting
output "monitoring_configuration" {
  description = "Monitoring and alerting configuration"
  value = {
    dashboard_id = google_monitoring_dashboard.database_overview.id
    alert_policies = {
      for instance_key, alert in google_monitoring_alert_policy.db_cpu_high : instance_key => {
        name = alert.display_name
        id   = alert.name
      }
    }
    notification_channels = var.notification_channels
  }
}

# Connection Information for Applications
output "database_connection_info" {
  description = "Connection information for applications (excluding sensitive data)"
  value = {
    proxysql_endpoints = {
      for region, service in google_cloud_run_v2_service.proxysql : region => {
        host = service.uri
        port = 6033
      }
    }
    direct_connections = {
      for instance_key, instance in google_sql_database_instance.shared_instances : instance_key => {
        host = instance.private_ip_address
        port = 3306
      }
    }
    credential_secret = google_secret_manager_secret.db_credentials.secret_id
  }
  sensitive = true
}

# Performance Metrics
output "performance_configuration" {
  description = "Database performance configuration"
  value = {
    max_connections_per_instance = var.max_connections_per_instance
    max_connections_per_tenant   = var.max_connections_per_tenant
    connection_timeout          = var.connection_timeout
    query_timeout              = var.query_timeout
    database_flags = {
      innodb_buffer_pool_size = "70%"
      max_connections        = var.max_connections_per_instance
      slow_query_log         = "enabled"
      long_query_time        = "2s"
    }
  }
}

# Backup Configuration
output "backup_configuration" {
  description = "Database backup and recovery configuration"
  value = {
    backup_enabled               = true
    backup_start_time           = "03:00 UTC"
    point_in_time_recovery      = true
    backup_retention_days       = 30
    transaction_log_retention   = 7
    cross_region_backup         = var.backup_config.cross_region_backup
  }
}

# Network Configuration
output "network_configuration" {
  description = "Database network configuration"
  value = {
    private_network      = var.shared_vpc_self_link
    private_ip_range     = google_compute_global_address.private_ip_address.address
    vpc_connector        = var.vpc_connector_name
    ssl_enforcement      = true
    public_ip_disabled   = true
  }
}

# Migration Support
output "migration_support" {
  description = "Database migration support information"
  value = {
    migration_mode_enabled = var.migration_config.enable_migration_mode
    batch_size            = var.migration_config.batch_size
    rollback_enabled      = var.migration_config.rollback_enabled
    dry_run_mode         = var.migration_config.dry_run_mode
    migration_windows    = var.migration_config.migration_window_hours
  }
}

# Regional Distribution
output "regional_distribution" {
  description = "Database instance distribution across regions"
  value = {
    for region in var.deployment_regions : region => {
      shared_instances = var.shared_instances_per_region
      read_replicas   = var.enable_read_replicas ? 1 : 0
      total_capacity  = var.shared_instances_per_region * var.databases_per_instance
      proxysql_instances = "${var.proxysql_min_instances}-${var.proxysql_max_instances}"
    }
  }
}

# Feature Flags Status
output "feature_flags" {
  description = "Current status of database feature flags"
  value = var.feature_flags
}

# Terraform State Information
output "terraform_state" {
  description = "Terraform state information for database architecture"
  value = {
    last_applied = timestamp()
    resources_created = {
      shared_instances    = length(google_sql_database_instance.shared_instances)
      read_replicas      = var.enable_read_replicas ? length(google_sql_database_instance.read_replicas) : 0
      proxysql_services  = length(google_cloud_run_v2_service.proxysql)
      secrets           = 2
      cloud_functions   = 1
      monitoring_alerts = length(google_monitoring_alert_policy.db_cpu_high)
    }
    configuration = {
      database_version           = var.database_version
      high_availability         = var.high_availability
      deletion_protection       = var.deletion_protection
      environment               = var.environment
    }
  }
}

# URLs for Management Access
output "management_urls" {
  description = "URLs for database management and monitoring"
  value = {
    cloud_sql_console = "https://console.cloud.google.com/sql/instances?project=${var.shared_services_project_id}"
    monitoring_dashboard = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.database_overview.id}?project=${var.shared_services_project_id}"
    secret_manager = "https://console.cloud.google.com/security/secret-manager?project=${var.shared_services_project_id}"
    cloud_functions = "https://console.cloud.google.com/functions/list?project=${var.shared_services_project_id}"
    pubsub_topics = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.shared_services_project_id}"
  }
}
