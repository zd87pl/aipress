# AIPress - AI-Driven WordPress Hosting

## Overview

AIPress aims to be a highly scalable, performant, cost-effective, and user-friendly WordPress hosting platform built on Google Cloud Platform (GCP). It leverages a conversational AI interface (powered by Google Gemini) for site creation, management, and operational insights.

This Proof-of-Concept (PoC) establishes the core infrastructure provisioning mechanism using Terraform, orchestrated by a Control Plane API deployed on Cloud Run.

## Architecture

(See [ARCHITECTURE.md](ARCHITECTURE.md) for details.)

*   **Control Plane:** A FastAPI application deployed on Cloud Run (`aipress-control-plane`). Receives API requests (e.g., `/poc/create-site/{tenant_id}`) and uses Terraform within its container to manage tenant resources. Runs as the `terraform-sa` service account.
*   **Tenant WordPress Runtime:** Deployed as a dedicated Cloud Run service (`aipress-tenant-{tenant_id}`) per tenant. Uses a custom Docker image based on the official `wordpress:fpm` image (Debian-based), adding Nginx. A custom entrypoint script manages setup (core files, permissions) and starts Nginx and PHP-FPM. Connects to a dedicated Cloud SQL database (via Cloud Run's native integration, including socket support) and uses a dedicated GCS bucket for media uploads (intended for use with a stateless media plugin like WP Offload Media). Includes an environment-variable driven `wp-config.php` template. Runs as the `wp-runtime-sa` service account.
*   **Infrastructure as Code:**
    *   `infra-bootstrap/`: Terraform configuration to deploy the Control Plane Cloud Run service and enable project APIs. Applied manually once or via CI/CD.
    *   `infra/`: Terraform configuration containing only the `tenant_wordpress` module definition. This configuration is copied into the Control Plane image and used by the API to manage tenants within workspaces.
*   **Terraform State:** Stored in a GCS backend bucket. `infra-bootstrap` uses the default workspace (or a dedicated prefix if configured), while the main `infra` configuration uses workspaces per tenant (managed by the Control Plane).
*   **Shared Resources:** A shared Cloud SQL instance, Artifact Registry repository, and Service Accounts are bootstrapped using a setup script.

## Tech Stack

*   **Cloud Provider:** Google Cloud Platform (GCP)
*   **Compute:** Cloud Run
*   **Database:** Cloud SQL (MySQL 8.0)
*   **Storage:** Google Cloud Storage (GCS)
*   **Container Registry:** Artifact Registry
*   **IaC:** Terraform
*   **Languages/Frameworks:** Python (FastAPI) for Control Plane, PHP for WordPress.
*   **Containerization:** Docker

## Getting Started

**Prerequisites:**

*   `gcloud` CLI installed and authenticated with permissions in your target GCP project.
*   `docker` installed and running.
*   `terraform` CLI installed locally.
*   `gsutil` CLI installed (usually part of `gcloud`).
*   Ensure your GCP project ID is correctly set in `scripts/poc_gcp_setup.sh`.

### Minimal IAM Roles

`poc_gcp_setup.sh` now grants a reduced set of IAM roles to the Terraform
service account. These roles are sufficient for Terraform to manage the
resources used in the PoC without giving full project ownership:

* `roles/run.admin`
* `roles/storage.admin`
* `roles/secretmanager.admin`
* `roles/cloudsql.admin`
* `roles/artifactregistry.admin`
* `roles/iam.serviceAccountUser` (on the WordPress runtime service account)

**Setup & Deployment Workflow:**

1.  **Bootstrap Shared Resources:**
    *   Navigate to `scripts/`: `cd scripts`
    *   Run `./poc_gcp_setup.sh` interactively. Follow prompts for APIs, SAs (saving `terraform-key.json`), AR Repo, Cloud SQL, Secret, TF state bucket.
    *   Make scripts executable: `chmod +x ./*.sh`
2.  **Build & Push WordPress Runtime Image:**
    *   Run `./build_and_push_image.sh`
3.  **Build & Push Control Plane Image:**
    *   Run `./build_and_push_cp_image.sh`
4.  **Deploy Control Plane Service via Terraform:**
    *   Navigate to the *new* bootstrap directory: `cd ../infra-bootstrap`
    *   Authenticate Terraform locally: `export GOOGLE_APPLICATION_CREDENTIALS="../scripts/terraform-key.json"`
    *   Initialize Terraform: `terraform init -upgrade`
    *   Apply the bootstrap configuration (this deploys the Control Plane service):
        ```bash
        terraform apply \
          -var="gcp_project_id=YOUR_GCP_PROJECT_ID" \
          -var="wp_docker_image_url=YOUR_WP_IMAGE_URL" \
          -var="control_plane_docker_image_url=YOUR_CP_IMAGE_URL"
          # Optional: restrict who can invoke the control plane
          -var='control_plane_invoker_members=["user:you@example.com"]'
        ```
        (Replace variables with your project ID and the image URLs output by the build scripts).
5.  **Create a Tenant Site:**
    *   Find the URL of the deployed `aipress-control-plane` service in your GCP Cloud Run console (or Terraform outputs if configured).
    *   Make a POST request to the `/poc/create-site/{tenant_id}` endpoint:
        ```bash
        # Replace {CONTROL_PLANE_URL} and {your_tenant_id}
        curl -X POST "{CONTROL_PLANE_URL}/poc/create-site/{your_tenant_id}"
        ```
    *   The Control Plane (running on Cloud Run) will use the configuration in `/infra` (copied into its image) and run `terraform apply` in the appropriate workspace to provision the tenant resources.
    *   Access to each tenant's WordPress service is controlled via the `wordpress_invoker_members` variable. Pass a list of members when provisioning to restrict who can invoke the service.

## Project Structure

```
.
├── ARCHITECTURE.md      # Detailed architecture document
├── BACKLOG.md           # Project backlog (if used)
├── README.md            # This file
├── infra-bootstrap/     # Terraform for deploying the Control Plane service
│   ├── main.tf
│   └── variables.tf
├── infra/               # Terraform used BY Control Plane for tenants
│   ├── main.tf          # Defines provider, backend, and tenant module call
│   ├── variables.tf     # Variables needed by main.tf (inc. tenant vars)
│   └── modules/
│       └── tenant_wordpress/ # Module for tenant resources
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── scripts/             # Helper scripts
│   ├── poc_gcp_setup.sh # Interactive setup for shared GCP resources
│   ├── build_and_push_image.sh     # Builds/pushes WP runtime image
│   ├── build_and_push_cp_image.sh  # Builds/pushes Control Plane image
│   └── terraform-key.json   # (Generated by setup script, DO NOT COMMIT)
└── src/
    ├── control-plane/   # Control Plane API (FastAPI)
    │   ├── Dockerfile     # Dockerfile for Control Plane
    │   ├── main.py        # FastAPI application code
    │   └── requirements.txt # Python dependencies
    └── wordpress-runtime/ # WordPress runtime container setup
        ├── Dockerfile             # Dockerfile for WP runtime (based on official WP FPM)
        ├── docker-entrypoint.sh   # Custom entrypoint script handling setup & process start
        ├── wp-config-template.php # Template for env-var driven wp-config.php
        ├── nginx/                 # Nginx configuration
        │   ├── nginx.conf
        │   └── wordpress.conf
        ├── php-fpm/               # PHP-FPM configuration
        │   ├── 00-logging.conf    # Global logging config
        │   └── www.conf           # Pool config
```

## Contributing

*(To be filled in later - Guidelines for development, pull requests, code style, etc.)*
