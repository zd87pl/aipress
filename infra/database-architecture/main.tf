/**
 * AIPress Shared Database Architecture
 * 
 * Implements the shared Cloud SQL architecture with connection pooling
 * to achieve the $2.64/site/month cost target (down from $7/site/month).
 * 
 * Key components:
 * - Shared Cloud SQL instances with database-per-tenant
 * - ProxySQL for connection pooling and read/write splitting
 * - Regional read replicas for performance
 * - Automated database provisioning via Cloud Functions
 * 
 * Based on database architecture from SCALING_TO_50K_SITES.md
 */

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Local variables for consistent naming and configuration
locals {
  # Database configuration
  shared_instances_per_region = var.shared_instances_per_region
  databases_per_instance      = var.databases_per_instance
  max_databases_per_region    = local.shared_instances_per_region * local.databases_per_instance
  
  # Calculate total capacity
  total_database_capacity = local.max_databases_per_region * length(var.deployment_regions)
  
  # Instance naming
  instance_prefix = "aipress-shared-db"
  
  # Connection pooling configuration
  proxysql_config = {
    max_connections_per_tenant = var.max_connections_per_tenant
    connection_timeout         = var.connection_timeout
    query_timeout             = var.query_timeout
    max_query_size            = var.max_query_size
  }
  
  # Common labels
  common_labels = merge(var.additional_labels, {
    environment     = var.environment
    project         = "aipress"
    component       = "database-architecture"
    managed_by      = "terraform"
    cost_center     = "shared-infrastructure"
  })
}

# Random password for shared database instances
resource "random_password" "db_master_password" {
  for_each = toset(var.deployment_regions)
  
  length  = 32
  special = true
}

# Shared Cloud SQL instances (one per region)
resource "google_sql_database_instance" "shared_instances" {
  for_each = {
    for i in range(local.shared_instances_per_region) :
    "${var.deployment_regions[0]}-${i}" => {
      region = var.deployment_regions[0]
      index  = i
    }
    # Add more regions as needed
  }
  
  project          = var.shared_services_project_id
  name             = "${local.instance_prefix}-${each.value.region}-${each.value.index}"
  database_version = var.database_version
  region           = each.value.region
  
  settings {
    tier                        = var.database_tier
    disk_type                   = "PD_SSD"
    disk_size                   = var.database_disk_size
    disk_autoresize            = true
    disk_autoresize_limit      = var.database_max_disk_size
    availability_type          = var.high_availability ? "REGIONAL" : "ZONAL"
    deletion_protection_enabled = var.deletion_protection
    
    # Performance optimizations
    database_flags {
      name  = "innodb_buffer_pool_size"
      value = "70"  # 70% of memory
    }
    
    database_flags {
      name  = "max_connections"
      value = tostring(var.max_connections_per_instance)
    }
    
    database_flags {
      name  = "innodb_lock_wait_timeout"
      value = "50"
    }
    
    database_flags {
      name  = "wait_timeout"
      value = "300"
    }
    
    database_flags {
      name  = "interactive_timeout"
      value = "300"
    }
    
    # Enable slow query log
    database_flags {
      name  = "slow_query_log"
      value = "on"
    }
    
    database_flags {
      name  = "long_query_time"
      value = "2"
    }
    
    # Backup configuration
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"  # 3 AM UTC
      location                       = each.value.region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }
    
    # IP configuration
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.shared_vpc_self_link
      enable_private_path_for_google_cloud_services = true
      require_ssl                                   = true
    }
    
    # Maintenance window
    maintenance_window {
      day          = 1  # Sunday
      hour         = 4  # 4 AM UTC
      update_track = "stable"
    }
    
    # Insights configuration
    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
      record_client_address   = true
    }
  }
  
  # Root password
  root_password = random_password.db_master_password[each.value.region].result
  
  depends_on = [
    google_service_networking_connection.private_vpc_connection
  ]
  
  lifecycle {
    prevent_destroy = true
  }
}

# Read replicas for performance
resource "google_sql_database_instance" "read_replicas" {
  for_each = var.enable_read_replicas ? {
    for region in var.deployment_regions :
    region => google_sql_database_instance.shared_instances["${region}-0"]
  } : {}
  
  project             = var.shared_services_project_id
  name               = "${local.instance_prefix}-${each.key}-replica"
  database_version   = var.database_version
  region             = each.key
  master_instance_name = each.value.name
  
  settings {
    tier                   = var.replica_tier
    disk_type             = "PD_SSD"
    disk_size             = var.database_disk_size
    availability_type     = "ZONAL"  # Replicas are typically zonal
    
    # IP configuration (same as master)
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.shared_vpc_self_link
      enable_private_path_for_google_cloud_services = true
      require_ssl                                   = true
    }
    
    # Replica configuration
    replica_configuration {
      failover_target = false
    }
  }
  
  depends_on = [
    google_sql_database_instance.shared_instances
  ]
}

# Private service networking connection
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.shared_vpc_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# Reserved IP range for private services
resource "google_compute_global_address" "private_ip_address" {
  project       = var.shared_services_project_id
  name          = "aipress-db-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.shared_vpc_self_link
}

# Database users for different access patterns
resource "google_sql_user" "app_users" {
  for_each = toset(["app_user", "readonly_user", "admin_user"])
  
  project  = var.shared_services_project_id
  name     = each.value
  instance = values(google_sql_database_instance.shared_instances)[0].name
  password = random_password.db_users[each.value].result
  
  # Different privileges for different user types
  dynamic "password_policy" {
    for_each = each.value == "admin_user" ? [1] : []
    content {
      allowed_failed_attempts      = 3
      password_expiration_duration = "2160h" # 90 days
      enable_failed_attempts_check = true
    }
  }
}

# Random passwords for database users
resource "random_password" "db_users" {
  for_each = toset(["app_user", "readonly_user", "admin_user"])
  
  length  = 24
  special = true
}

# ProxySQL instances for connection pooling
resource "google_cloud_run_v2_service" "proxysql" {
  for_each = toset(var.deployment_regions)
  
  project  = var.shared_services_project_id
  name     = "proxysql-${each.value}"
  location = each.value
  
  template {
    scaling {
      min_instance_count = var.proxysql_min_instances
      max_instance_count = var.proxysql_max_instances
    }
    
    containers {
      image = var.proxysql_image
      
      resources {
        limits = {
          cpu    = var.proxysql_cpu_limit
          memory = var.proxysql_memory_limit
        }
      }
      
      # ProxySQL configuration
      env {
        name  = "MYSQL_HOST"
        value = google_sql_database_instance.shared_instances["${each.value}-0"].private_ip_address
      }
      
      env {
        name  = "MYSQL_PORT"
        value = "3306"
      }
      
      env {
        name = "MYSQL_USER"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_credentials.secret_id
            version = "latest"
          }
        }
      }
      
      env {
        name = "MYSQL_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_credentials.secret_id
            version = "latest"
          }
        }
      }
      
      env {
        name  = "PROXYSQL_ADMIN_USER"
        value = "admin"
      }
      
      env {
        name = "PROXYSQL_ADMIN_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.proxysql_admin.secret_id
            version = "latest"
          }
        }
      }
      
      env {
        name  = "MAX_CONNECTIONS_PER_TENANT"
        value = tostring(local.proxysql_config.max_connections_per_tenant)
      }
      
      env {
        name  = "CONNECTION_TIMEOUT"
        value = tostring(local.proxysql_config.connection_timeout)
      }
      
      env {
        name  = "QUERY_TIMEOUT"
        value = tostring(local.proxysql_config.query_timeout)
      }
      
      # Health check
      liveness_probe {
        http_get {
          path = "/health"
          port = 6032
        }
        initial_delay_seconds = 30
        period_seconds       = 10
      }
      
      # Startup probe
      startup_probe {
        http_get {
          path = "/health"
          port = 6032
        }
        initial_delay_seconds = 10
        period_seconds       = 5
        failure_threshold    = 30
      }
      
      ports {
        name           = "mysql"
        container_port = 6033
      }
      
      ports {
        name           = "admin"
        container_port = 6032
      }
    }
    
    # VPC access
    vpc_access {
      connector = var.vpc_connector_name
      egress    = "ALL_TRAFFIC"
    }
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [
    google_sql_database_instance.shared_instances
  ]
}

# Database credentials in Secret Manager
resource "google_secret_manager_secret" "db_credentials" {
  project   = var.shared_services_project_id
  secret_id = "shared-database-credentials"
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_credentials" {
  secret = google_secret_manager_secret.db_credentials.id
  
  secret_data = jsonencode({
    instances = {
      for region, instance in google_sql_database_instance.shared_instances : region => {
        host     = instance.private_ip_address
        port     = 3306
        users = {
          for user_type, user in google_sql_user.app_users : user_type => {
            username = user.name
            password = random_password.db_users[user_type].result
          }
        }
      }
    }
    read_replicas = var.enable_read_replicas ? {
      for region, replica in google_sql_database_instance.read_replicas : region => {
        host = replica.private_ip_address
        port = 3306
      }
    } : {}
  })
}

# ProxySQL admin credentials
resource "google_secret_manager_secret" "proxysql_admin" {
  project   = var.shared_services_project_id
  secret_id = "proxysql-admin-credentials"
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
}

resource "random_password" "proxysql_admin" {
  length  = 32
  special = true
}

resource "google_secret_manager_secret_version" "proxysql_admin" {
  secret      = google_secret_manager_secret.proxysql_admin.id
  secret_data = random_password.proxysql_admin.result
}

# Cloud Function for automated database provisioning
resource "google_cloudfunctions2_function" "db_provisioner" {
  project  = var.shared_services_project_id
  name     = "database-provisioner"
  location = var.deployment_regions[0]
  
  build_config {
    runtime     = "python311"
    entry_point = "provision_database"
    
    source {
      storage_source {
        bucket = google_storage_bucket.db_provisioner_source.name
        object = google_storage_bucket_object.db_provisioner_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "512Mi"
    timeout_seconds       = 300
    service_account_email = google_service_account.db_provisioner.email
    
    environment_variables = {
      SHARED_SERVICES_PROJECT = var.shared_services_project_id
      DB_CREDENTIALS_SECRET   = google_secret_manager_secret.db_credentials.secret_id
      MAX_DATABASES_PER_INSTANCE = tostring(local.databases_per_instance)
    }
  }
  
  event_trigger {
    trigger_region = var.deployment_regions[0]
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.db_provisioning_requests.id
  }
  
  depends_on = [
    google_storage_bucket_object.db_provisioner_source
  ]
}

# Service account for database provisioner
resource "google_service_account" "db_provisioner" {
  project      = var.shared_services_project_id
  account_id   = "database-provisioner"
  display_name = "Database Provisioner Service Account"
  description  = "Service account for automated database provisioning"
}

# IAM bindings for database provisioner
resource "google_project_iam_member" "db_provisioner_roles" {
  for_each = toset([
    "roles/cloudsql.admin",
    "roles/secretmanager.secretAccessor",
    "roles/pubsub.subscriber"
  ])
  
  project = var.shared_services_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.db_provisioner.email}"
}

# Pub/Sub topic for database provisioning requests
resource "google_pubsub_topic" "db_provisioning_requests" {
  project = var.shared_services_project_id
  name    = "database-provisioning-requests"
  
  labels = local.common_labels
}

# Storage bucket for Cloud Function source code
resource "google_storage_bucket" "db_provisioner_source" {
  project  = var.shared_services_project_id
  name     = "${var.shared_services_project_id}-db-provisioner-source"
  location = var.deployment_regions[0]
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
}

# Placeholder source code for database provisioner
resource "google_storage_bucket_object" "db_provisioner_source" {
  name   = "db-provisioner-source.zip"
  bucket = google_storage_bucket.db_provisioner_source.name
  source = data.archive_file.db_provisioner_source.output_path
}

# Archive the database provisioner source code
data "archive_file" "db_provisioner_source" {
  type        = "zip"
  output_path = "/tmp/db-provisioner-source.zip"
  
  source {
    content = templatefile("${path.module}/src/database_provisioner.py", {
      max_databases_per_instance = local.databases_per_instance
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/src/requirements.txt")
    filename = "requirements.txt"
  }
}

# Monitoring alerts for database health
resource "google_monitoring_alert_policy" "db_cpu_high" {
  for_each = google_sql_database_instance.shared_instances
  
  project      = var.shared_services_project_id
  display_name = "High CPU Usage - ${each.value.name}"
  combiner     = "OR"
  
  conditions {
    display_name = "CPU usage above 80%"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${var.shared_services_project_id}:${each.value.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.8
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "604800s" # 7 days
  }
}

# Monitoring dashboard for database metrics
resource "google_monitoring_dashboard" "database_overview" {
  project        = var.shared_services_project_id
  dashboard_json = templatefile("${path.module}/dashboards/database_overview.json", {
    project_id = var.shared_services_project_id
  })
}
