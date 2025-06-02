/**
 * Shard Project Module
 * 
 * Creates and configures a single shard project capable of hosting
 * up to 50 WordPress sites with shared infrastructure.
 */

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

# Local variables
locals {
  # APIs required for each shard project
  required_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudsql.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "cloudtrace.googleapis.com",
    "cloudprofiler.googleapis.com"
  ]
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    shard_id = var.shard_id
    region   = var.region
  })
}

# Create the shard project
resource "google_project" "shard" {
  name                = "AIPress Shard ${var.shard_id}"
  project_id          = var.project_id
  billing_account     = var.billing_account
  folder_id           = var.folder_id
  auto_create_network = false
  
  labels = local.common_labels
  
  lifecycle {
    prevent_destroy = true
  }
}

# Enable required APIs
resource "google_project_service" "shard_apis" {
  for_each = toset(local.required_apis)
  
  project = google_project.shard.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Shared VPC attachment
resource "google_compute_shared_vpc_service_project" "shard" {
  host_project    = var.shared_services_project_id
  service_project = google_project.shard.project_id
  
  depends_on = [google_project_service.shard_apis]
}

# Service account for shard control plane
resource "google_service_account" "shard_control_plane" {
  project      = google_project.shard.project_id
  account_id   = "shard-control-plane"
  display_name = "Shard Control Plane Service Account"
  description  = "Service account for the shard control plane"
  
  depends_on = [google_project_service.shard_apis]
}

# IAM bindings for shard control plane
resource "google_project_iam_member" "shard_control_plane_roles" {
  for_each = toset([
    "roles/cloudsql.client",
    "roles/storage.admin",
    "roles/secretmanager.accessor",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/cloudtrace.agent",
    "roles/cloudprofiler.agent",
    "roles/run.invoker"
  ])
  
  project = google_project.shard.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.shard_control_plane.email}"
}

# Cloud Run service for shard control plane
resource "google_cloud_run_v2_service" "shard_control_plane" {
  project  = google_project.shard.project_id
  name     = "shard-control-plane"
  location = var.region
  
  template {
    service_account = google_service_account.shard_control_plane.email
    
    scaling {
      min_instance_count = 1
      max_instance_count = 10
    }
    
    containers {
      # Placeholder image - will be updated by CI/CD
      image = "gcr.io/cloudrun/hello"
      
      resources {
        limits = {
          cpu    = "2"
          memory = "4Gi"
        }
      }
      
      env {
        name  = "SHARD_ID"
        value = var.shard_id
      }
      
      env {
        name  = "PROJECT_ID"
        value = google_project.shard.project_id
      }
      
      env {
        name  = "REGION"
        value = var.region
      }
      
      env {
        name  = "MAX_TENANTS"
        value = tostring(var.max_tenants_per_shard)
      }
      
      env {
        name  = "SHARED_SERVICES_PROJECT"
        value = var.shared_services_project_id
      }
      
      ports {
        container_port = 8080
      }
    }
    
    vpc_access {
      connector = google_vpc_access_connector.shard.id
      egress    = "ALL_TRAFFIC"
    }
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [
    google_project_service.shard_apis,
    google_vpc_access_connector.shard
  ]
}

# VPC Access Connector for Cloud Run
resource "google_vpc_access_connector" "shard" {
  project = google_project.shard.project_id
  name    = "shard-connector"
  region  = var.region
  
  subnet {
    name       = var.shared_subnet_name
    project_id = var.shared_services_project_id
  }
  
  machine_type   = "e2-micro"
  min_instances  = 2
  max_instances  = 3
  
  depends_on = [
    google_project_service.shard_apis,
    google_compute_shared_vpc_service_project.shard
  ]
}

# Cloud Storage bucket for WordPress files
resource "google_storage_bucket" "wordpress_files" {
  project  = google_project.shard.project_id
  name     = "${var.project_id}-wordpress-files"
  location = var.region
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 30
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.shard_apis]
}

# Budget alert for cost management
resource "google_billing_budget" "shard_budget" {
  count = var.enable_budget_alerts ? 1 : 0
  
  billing_account = var.billing_account
  display_name    = "AIPress Shard ${var.shard_id} Budget"
  
  budget_filter {
    projects = ["projects/${google_project.shard.number}"]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_budget)
    }
  }
  
  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }
  
  all_updates_rule {
    pubsub_topic                     = var.budget_pubsub_topic
    schema_version                   = "1.0"
    disable_default_iam_recipients   = true
  }
}

# Log sink for centralized logging
resource "google_logging_project_sink" "shard_logs" {
  project = google_project.shard.project_id
  name    = "shard-logs-sink"
  
  destination = "bigquery.googleapis.com/projects/${var.shared_services_project_id}/datasets/aipress_logs"
  
  filter = "resource.type=\"cloud_run_revision\" OR resource.type=\"gce_instance\" OR resource.type=\"cloudsql_database\""
  
  unique_writer_identity = true
  
  depends_on = [google_project_service.shard_apis]
}

# Monitoring workspace (linked to shared services)
resource "google_monitoring_monitored_project" "shard" {
  metrics_scope = var.shared_services_project_id
  name          = google_project.shard.project_id
  
  depends_on = [google_project_service.shard_apis]
}

# Secret for database credentials (placeholder)
resource "google_secret_manager_secret" "db_credentials" {
  project   = google_project.shard.project_id
  secret_id = "database-credentials"
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.shard_apis]
}

# Cloud Build trigger for shard control plane deployment
resource "google_cloudbuild_trigger" "shard_control_plane_deploy" {
  project  = google_project.shard.project_id
  name     = "shard-control-plane-deploy"
  location = var.region
  
  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^main$"
    }
  }
  
  included_files = ["src/control-plane/**"]
  
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "gcr.io/${google_project.shard.project_id}/shard-control-plane:$COMMIT_SHA",
        "-f", "src/control-plane/Dockerfile",
        "src/control-plane"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "gcr.io/${google_project.shard.project_id}/shard-control-plane:$COMMIT_SHA"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "run", "deploy", "shard-control-plane",
        "--image", "gcr.io/${google_project.shard.project_id}/shard-control-plane:$COMMIT_SHA",
        "--region", var.region,
        "--platform", "managed",
        "--service-account", google_service_account.shard_control_plane.email,
        "--set-env-vars", "SHARD_ID=${var.shard_id},PROJECT_ID=${google_project.shard.project_id},REGION=${var.region}"
      ]
    }
  }
  
  depends_on = [google_project_service.shard_apis]
}

# Firewall rules for shard-specific traffic (if needed)
resource "google_compute_firewall" "shard_specific" {
  count   = length(var.additional_firewall_rules)
  project = var.shared_services_project_id
  
  name    = "shard-${var.shard_id}-${var.additional_firewall_rules[count.index].name}"
  network = var.shared_vpc_name
  
  dynamic "allow" {
    for_each = var.additional_firewall_rules[count.index].allow
    content {
      protocol = allow.value.protocol
      ports    = try(allow.value.ports, null)
    }
  }
  
  source_ranges = var.additional_firewall_rules[count.index].source_ranges
  target_tags   = [var.shard_id]
  
  direction = "INGRESS"
}
