/**
 * AIPress Multi-Project Infrastructure
 * 
 * This Terraform configuration sets up the multi-project federation
 * architecture for scaling to 50,000+ WordPress sites across 1,000 GCP projects.
 * 
 * Based on the architecture specified in SCALING_TO_50K_SITES.md
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
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.organization_project_id
  region  = var.default_region
}

provider "google-beta" {
  project = var.organization_project_id
  region  = var.default_region
}

# Local variables for consistent naming
locals {
  organization_name = "aipress-hosting"
  project_prefix    = "aipress-shard"
  
  # Calculate shard project IDs
  shard_projects = {
    for i in range(1, var.initial_shard_count + 1) : 
    format("%s-%03d", local.project_prefix, i) => {
      shard_id    = format("aipress-shard-%03d", i)
      project_id  = format("%s-%03d", local.project_prefix, i)
      region      = var.default_region
      shard_index = i
    }
  }
  
  # Common labels for all resources
  common_labels = {
    environment   = var.environment
    project       = "aipress"
    managed_by    = "terraform"
    architecture  = "multi-project-federation"
  }
}

# Organization folder for AIPress hosting (if using organization)
resource "google_folder" "aipress_hosting" {
  count        = var.use_organization ? 1 : 0
  display_name = local.organization_name
  parent       = "organizations/${var.organization_id}"
  
  lifecycle {
    prevent_destroy = true
  }
}

# Shared services project for meta control plane and global resources
resource "google_project" "shared_services" {
  name                = "AIPress Shared Services"
  project_id          = var.shared_services_project_id
  billing_account     = var.billing_account_id
  folder_id           = var.use_organization ? google_folder.aipress_hosting[0].name : null
  auto_create_network = false
  
  labels = merge(local.common_labels, {
    component = "shared-services"
    role      = "meta-control-plane"
  })
  
  lifecycle {
    prevent_destroy = true
  }
}

# Enable required APIs for shared services project
resource "google_project_service" "shared_services_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudsql.googleapis.com",
    "spanner.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "dns.googleapis.com"
  ])
  
  project = google_project.shared_services.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Cloud Spanner instance for global metadata
resource "google_spanner_instance" "global_metadata" {
  count            = var.enable_cloud_spanner ? 1 : 0
  project          = google_project.shared_services.project_id
  config           = "regional-${var.default_region}"
  display_name     = "AIPress Global Metadata"
  name             = "aipress-metadata"
  processing_units = var.spanner_processing_units
  
  labels = merge(local.common_labels, {
    component = "metadata-storage"
  })
  
  depends_on = [google_project_service.shared_services_apis]
}

# Cloud Spanner database for metadata
resource "google_spanner_database" "metadata_db" {
  count    = var.enable_cloud_spanner ? 1 : 0
  project  = google_project.shared_services.project_id
  instance = google_spanner_instance.global_metadata[0].name
  name     = "aipress-db"
  
  ddl = [
    <<-EOF
      CREATE TABLE tenants (
        tenant_id STRING(MAX) NOT NULL,
        shard_id STRING(MAX) NOT NULL,
        project_id STRING(MAX) NOT NULL,
        created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
        last_seen TIMESTAMP OPTIONS (allow_commit_timestamp=true),
        metadata JSON,
      ) PRIMARY KEY (tenant_id)
    EOF
    ,
    <<-EOF
      CREATE TABLE shards (
        shard_id STRING(MAX) NOT NULL,
        project_id STRING(MAX) NOT NULL,
        region STRING(MAX) NOT NULL,
        control_plane_url STRING(MAX),
        tenant_count INT64 NOT NULL DEFAULT (0),
        max_tenants INT64 NOT NULL DEFAULT (50),
        health STRING(MAX) NOT NULL DEFAULT ('unknown'),
        last_health_check TIMESTAMP OPTIONS (allow_commit_timestamp=true),
        created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
        metadata JSON,
      ) PRIMARY KEY (shard_id)
    EOF
    ,
    <<-EOF
      CREATE TABLE projects (
        project_id STRING(MAX) NOT NULL,
        project_name STRING(MAX) NOT NULL,
        shard_id STRING(MAX),
        status STRING(MAX) NOT NULL,
        region STRING(MAX) NOT NULL,
        billing_account STRING(MAX) NOT NULL,
        organization_id STRING(MAX),
        created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
        resource_usage JSON,
        cost_data JSON,
      ) PRIMARY KEY (project_id)
    EOF
    ,
    <<-EOF
      CREATE TABLE audit_events (
        event_id STRING(MAX) NOT NULL,
        event_type STRING(MAX) NOT NULL,
        timestamp TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
        user_id STRING(MAX),
        tenant_id STRING(MAX),
        shard_id STRING(MAX),
        project_id STRING(MAX),
        details JSON,
        success BOOL NOT NULL,
        error_message STRING(MAX),
      ) PRIMARY KEY (event_id)
    EOF
  ]
  
  depends_on = [google_spanner_instance.global_metadata]
}

# Shared VPC network for cross-project communication
resource "google_compute_network" "shared_vpc" {
  project                 = google_project.shared_services.project_id
  name                    = "aipress-shared-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460
  
  depends_on = [google_project_service.shared_services_apis]
}

# Shared VPC subnet for each region
resource "google_compute_subnetwork" "shared_subnet" {
  for_each = toset(var.deployment_regions)
  
  project       = google_project.shared_services.project_id
  name          = "aipress-subnet-${each.value}"
  network       = google_compute_network.shared_vpc.name
  region        = each.value
  ip_cidr_range = cidrsubnet("10.0.0.0/8", 8, index(var.deployment_regions, each.value))
  
  # Enable private Google access
  private_ip_google_access = true
  
  # Secondary ranges for GKE clusters
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = cidrsubnet("172.16.0.0/12", 4, index(var.deployment_regions, each.value))
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet("192.168.0.0/16", 8, index(var.deployment_regions, each.value))
  }
}

# Firewall rules for shared VPC
resource "google_compute_firewall" "allow_internal" {
  project = google_project.shared_services.project_id
  name    = "aipress-allow-internal"
  network = google_compute_network.shared_vpc.name
  
  allow {
    protocol = "tcp"
  }
  
  allow {
    protocol = "udp"
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  
  direction = "INGRESS"
}

resource "google_compute_firewall" "allow_ssh" {
  project = google_project.shared_services.project_id
  name    = "aipress-allow-ssh"
  network = google_compute_network.shared_vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["35.235.240.0/20"] # Google Cloud IAP
  target_tags   = ["ssh-allowed"]
  
  direction = "INGRESS"
}

resource "google_compute_firewall" "allow_health_checks" {
  project = google_project.shared_services.project_id
  name    = "aipress-allow-health-checks"
  network = google_compute_network.shared_vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["8080", "80", "443"]
  }
  
  source_ranges = [
    "130.211.0.0/22",  # Google Load Balancer health checks
    "35.191.0.0/16"    # Google Load Balancer health checks
  ]
  
  direction = "INGRESS"
}

# Create shard projects using the module
module "shard_projects" {
  source = "./modules/shard-project"
  
  for_each = local.shard_projects
  
  # Project configuration
  project_id      = each.value.project_id
  shard_id        = each.value.shard_id
  region          = each.value.region
  billing_account = var.billing_account_id
  
  # Organization setup
  folder_id         = var.use_organization ? google_folder.aipress_hosting[0].name : null
  organization_id   = var.organization_id
  
  # Shared services
  shared_services_project_id = google_project.shared_services.project_id
  shared_vpc_name           = google_compute_network.shared_vpc.name
  shared_subnet_name        = google_compute_subnetwork.shared_subnet[each.value.region].name
  
  # Configuration
  max_tenants_per_shard = var.max_tenants_per_shard
  environment          = var.environment
  
  # Labels
  labels = merge(local.common_labels, {
    component   = "shard"
    shard_id    = each.value.shard_id
    shard_index = tostring(each.value.shard_index)
  })
  
  depends_on = [
    google_project_service.shared_services_apis,
    google_compute_network.shared_vpc,
    google_compute_subnetwork.shared_subnet
  ]
}

# Service account for meta control plane
resource "google_service_account" "meta_control_plane" {
  project      = google_project.shared_services.project_id
  account_id   = "meta-control-plane"
  display_name = "AIPress Meta Control Plane Service Account"
  description  = "Service account for the meta control plane to manage shard projects"
  
  depends_on = [google_project_service.shared_services_apis]
}

# IAM binding for meta control plane to manage projects
resource "google_organization_iam_member" "meta_control_plane_project_creator" {
  count  = var.use_organization ? 1 : 0
  org_id = var.organization_id
  role   = "roles/resourcemanager.projectCreator"
  member = "serviceAccount:${google_service_account.meta_control_plane.email}"
}

resource "google_organization_iam_member" "meta_control_plane_billing_user" {
  count  = var.use_organization ? 1 : 0
  org_id = var.organization_id
  role   = "roles/billing.user"
  member = "serviceAccount:${google_service_account.meta_control_plane.email}"
}

# Project-level IAM for meta control plane
resource "google_project_iam_member" "meta_control_plane_shared_services" {
  for_each = toset([
    "roles/spanner.databaseAdmin",
    "roles/monitoring.admin",
    "roles/logging.admin",
    "roles/storage.admin"
  ])
  
  project = google_project.shared_services.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.meta_control_plane.email}"
}

# Cloud Build trigger for meta control plane deployment
resource "google_cloudbuild_trigger" "meta_control_plane_deploy" {
  project  = google_project.shared_services.project_id
  name     = "meta-control-plane-deploy"
  location = var.default_region
  
  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^main$"
    }
  }
  
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "gcr.io/${google_project.shared_services.project_id}/meta-control-plane:$COMMIT_SHA",
        "-f", "src/meta-control-plane/Dockerfile",
        "src/meta-control-plane"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "gcr.io/${google_project.shared_services.project_id}/meta-control-plane:$COMMIT_SHA"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "run", "deploy", "meta-control-plane",
        "--image", "gcr.io/${google_project.shared_services.project_id}/meta-control-plane:$COMMIT_SHA",
        "--region", var.default_region,
        "--platform", "managed",
        "--service-account", google_service_account.meta_control_plane.email,
        "--set-env-vars", "NUM_SHARDS=${var.target_shard_count},GCP_ORGANIZATION_ID=${var.organization_id},GCP_BILLING_ACCOUNT=${var.billing_account_id}"
      ]
    }
  }
  
  depends_on = [google_project_service.shared_services_apis]
}
