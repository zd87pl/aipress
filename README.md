# AIPress - AI-Driven WordPress Hosting

## Overview

AIPress aims to be a highly scalable, performant, cost-effective, and user-friendly WordPress hosting platform built on Google Cloud Platform (GCP). It leverages a conversational AI interface (powered by Google Gemini) for site creation, management, and operational insights.

This Proof-of-Concept (PoC) establishes the core infrastructure provisioning mechanism using Terraform, orchestrated by a Control Plane API deployed on Cloud Run.

## Architecture

(See [ARCHITECTURE.md](ARCHITECTURE.md) for details.)

*   **Control Plane:** A FastAPI application deployed on Cloud Run (`aipress-control-plane`). Receives API requests (e.g., `/poc/create-site/{tenant_id}`) and uses Terraform within its container to manage tenant resources. Runs as the `terraform-sa` service account.
*   **Tenant WordPress Runtime:** Deployed as a dedicated Cloud Run service (`aipress-tenant-{tenant_id}`) per tenant. Uses a custom Docker image (Debian-based, Nginx, PHP-FPM, Supervisor, gcsfuse). Connects to a dedicated Cloud SQL database and uses a dedicated GCS bucket for `wp-content`. Runs as the `wp-runtime-sa` service account.
*   **Infrastructure as Code:** Terraform manages the Control Plane Cloud Run service and the underlying tenant resources (Cloud Run, SQL DB/User, GCS Bucket, Secrets) via a module (`infra/modules/tenant_wordpress`). State is stored in a GCS backend bucket.
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
*   `terraform` CLI installed locally (for initial Control Plane deployment).
*   `gsutil` CLI installed (usually part of `gcloud`).
*   Ensure your GCP project ID is correctly set in `scripts/poc_gcp_setup.sh`.

**Setup & Deployment Workflow:**

1.  **Bootstrap Shared Resources:**
    *   Navigate to the `scripts` directory: `cd scripts`
    *   Run the interactive setup script: `./poc_gcp_setup.sh`
    *   Follow the prompts to enable APIs, create SAs (saving `terraform-key.json`), create Artifact Registry, create shared Cloud SQL (enter root password), create Secret, and create TF state bucket.
2.  **Build & Push WordPress Runtime Image:**
    *   Ensure the script is executable: `chmod +x ./build_and_push_image.sh`
    *   Run the script: `./build_and_push_image.sh`
3.  **Build & Push Control Plane Image:**
    *   Ensure the script is executable: `chmod +x ./build_and_push_cp_image.sh`
    *   Run the script: `./build_and_push_cp_image.sh`
4.  **Deploy Control Plane Service via Terraform:**
    *   Navigate to the `infra` directory: `cd ../infra`
    *   Authenticate Terraform locally using the generated key: `export GOOGLE_APPLICATION_CREDENTIALS="../scripts/terraform-key.json"`
    *   Initialize Terraform: `terraform init -upgrade`
    *   Apply the configuration (this deploys the Control Plane service):
        ```bash
        terraform apply \
          -var="gcp_project_id=YOUR_GCP_PROJECT_ID" \
          -var="wp_docker_image_url=YOUR_WP_IMAGE_URL" \
          -var="control_plane_docker_image_url=YOUR_CP_IMAGE_URL" 
        ```
        (Replace variables with your project ID and the image URLs output by the build scripts).
5.  **Create a Tenant Site:**
    *   Find the URL of the deployed `aipress-control-plane` service in your GCP Cloud Run console.
    *   Make a POST request to the `/poc/create-site/{tenant_id}` endpoint:
        ```bash
        # Replace {CONTROL_PLANE_URL} and {your_tenant_id}
        curl -X POST "{CONTROL_PLANE_URL}/poc/create-site/{your_tenant_id}"
        ```
    *   The Control Plane will run `terraform apply` in the appropriate workspace to provision the tenant resources.

## Project Structure

```
.
├── ARCHITECTURE.md      # Detailed architecture document
├── BACKLOG.md           # Project backlog (if used)
├── README.md            # This file
├── infra/               # Terraform code
│   ├── main.tf          # Root config (Control Plane service, API enablement)
│   ├── variables.tf     # Root variables
│   └── modules/
│       └── tenant_wordpress/ # Module for tenant resources
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── scripts/             # Helper scripts
│   ├── poc_gcp_setup.sh # Interactive setup for shared GCP resources
│   ├── build_and_push_image.sh     # Builds/pushes WP runtime image
│   ├── build_and_push_cp_image.sh  # Builds/pushes Control Plane image
│   ├── run_control_plane.sh # (Deprecated) Runs Control Plane locally
│   └── terraform-key.json   # (Generated by setup script, DO NOT COMMIT)
└── src/
    ├── control-plane/   # Control Plane API (FastAPI)
    │   ├── Dockerfile     # Dockerfile for Control Plane
    │   ├── main.py        # FastAPI application code
    │   └── requirements.txt # Python dependencies
    └── wordpress-runtime/ # WordPress runtime container setup
        ├── Dockerfile     # Dockerfile for WP runtime (Debian based)
        ├── entrypoint.sh  # Entrypoint script (gcsfuse mount)
        ├── nginx/         # Nginx configuration
        │   ├── nginx.conf
        │   └── wordpress.conf
        └── supervisor/    # Supervisor configuration
            └── supervisord.conf
```

## Contributing

*(To be filled in later - Guidelines for development, pull requests, code style, etc.)*
