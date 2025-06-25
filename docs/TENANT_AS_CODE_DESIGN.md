# Tenant-as-Code Design Proposal

This document outlines a design for managing AIPress tenants using a declarative, "as-code" approach, leveraging GitOps principles. This approach aims to replace the current imperative API calls with version-controlled tenant definitions.

## 1. Overview

The core idea is to define each tenant's configuration (runtime settings, plugins, etc.) in a YAML or JSON file stored in a Git repository. A CI/CD pipeline will monitor this repository and automatically trigger the AIPress Control Plane API to create, update, or delete tenants based on changes to these definition files. The Control Plane will continue to use Terraform internally to manage the underlying GCP resources.

## 2. Tenant Definition Schema

A new schema (e.g., YAML) will define the structure for tenant configuration files.

```yaml
# Example: tenant-example.yaml
apiVersion: aipress.io/v1alpha1 # Use API versioning for future changes
kind: Tenant                  # Define the type of resource
metadata:
  name: tenant-example        # Unique tenant ID (maps to Terraform workspace & current tenant_id)
  displayName: "Example Tenant Site" # Optional friendly name
spec:
  runtime:
    image: "us-central1-docker.pkg.dev/aipress-project/aipress-images/wordpress-runtime:latest" # Optional: Specific WP image (defaults to control-plane config)
    environmentVariables: # Optional: Variables passed to the WP runtime container
      # Note: Sensitive values should still be handled via secrets.
      WP_DEBUG: "false"
    scaling: # Optional: Cloud Run specific scaling (defaults can be in Terraform module)
      minInstances: 0
      maxInstances: 3
  # database: # Potential future enhancement (currently uses shared SQL)
  #   tier: "standard"
  plugins: # Optional: Define desired plugins
    # Option A: List specific plugins (requires logic change in installer/control plane)
    # - name: "woocommerce"
    #   version: "latest"
    # Option B: Reference a specific GCS YAML file (closer to current setup)
    pluginsYamlGcsUri: "gs://<your-bucket>/tenant-example-plugins.yaml"
    # If omitted, could use the default configured in the control plane (e.g., src/default-plugins.yaml)
  # customDomains: # Potential future enhancement
  #   - "www.example-tenant.com"
```

**Key Schema Elements:**

*   **`apiVersion`, `kind`**: Standard resource identification and versioning.
*   **`metadata.name`**: The unique identifier for the tenant, used for the `tenant_id` and Terraform workspace name.
*   **`spec`**: Contains the desired configuration for the tenant, including runtime details and plugin setup.
*   **`spec.plugins.pluginsYamlGcsUri`**: (Recommended starting point) Links to a GCS file defining the plugins, similar to the current mechanism.

## 3. Control Plane API Modifications

The existing FastAPI Control Plane (`src/control-plane/main.py`) needs modifications:

*   **`POST /tenants` (New):**
    *   Accepts a Tenant Definition YAML/JSON in the request body.
    *   Validates the definition against the schema.
    *   Extracts `metadata.name` as `tenant_id`.
    *   Checks for existing Terraform workspace; errors if it exists (use PUT for updates).
    *   Generates a richer `tenant-{tenant_id}.auto.tfvars.json` file based on the `spec`.
    *   Runs `terraform workspace new {tenant_id}`.
    *   Runs `terraform apply` with generated variables.
    *   Triggers the plugin installation task (using `spec.plugins.pluginsYamlGcsUri` if provided, else default).
    *   Returns success/failure.
*   **`PUT /tenants/{tenant_id}` (New):**
    *   Accepts a full Tenant Definition YAML/JSON in the request body.
    *   Validates the definition.
    *   Ensures `metadata.name` matches the URL `tenant_id`.
    *   Checks for existing Terraform workspace; errors if it *doesn't* exist (use POST for creation).
    *   Generates `tfvars` based on the *new* definition.
    *   Runs `terraform workspace select {tenant_id}`.
    *   Runs `terraform apply` (Terraform handles the diff).
    *   Handles potential side-effects (e.g., re-triggering plugin install if `pluginsYamlGcsUri` changes).
    *   Returns success/failure.
*   **`DELETE /tenants/{tenant_id}` (Rename `/poc/destroy-site/{tenant_id}`):**
    *   Renamed for consistency.
    *   Functionality remains the same: select workspace, run `terraform destroy`, delete workspace.
*   **`GET /tenants/{tenant_id}` (Optional New):**
    *   Retrieves the current state/configuration of the tenant, potentially by reading Terraform state or querying GCP APIs.

## 4. Pipeline Integration (GitOps Flow)

A CI/CD pipeline orchestrates the process:

```mermaid
graph LR
    subgraph "Developer/Operator"
        A[Edits Tenant YAML/JSON] --> B(Git Repository for Tenant Definitions);
    end

    subgraph "CI/CD Pipeline (e.g., Cloud Build / GitHub Actions)"
        B -- Push Trigger --> C{Checkout Code};
        C --> D{Identify Changes (Add/Mod/Del)};
        D -- Add/Modify --> E[Validate Schema (Optional)];
        E -- Valid --> F[Call Control Plane API POST/PUT /tenants];
        D -- Delete --> G[Call Control Plane API DELETE /tenants/{id}];
        F & G --> H((End Pipeline Run));
    end

    subgraph "AIPress Control Plane (FastAPI App)"
        F --> I{Validate & Parse Definition};
        I --> J[Generate TF Vars];
        J --> K[Select/Create TF Workspace];
        K --> L[Run 'terraform apply'];
        L --> M[Trigger Plugin Install Task];
        G --> N[Select TF Workspace];
        N --> O[Run 'terraform destroy'];
        O --> P[Delete TF Workspace];
    end

    subgraph "GCP Infrastructure (Managed by Terraform)"
        L --> Q(Cloud Run Tenant Service);
        L --> R(Cloud SQL Tenant DB);
        L --> S(Secrets, IAM, etc.);
        M --> T(Plugin Installer Cloud Run Job);
    end

    style H fill:#dff,stroke:#333,stroke-width:2px
```

**Pipeline Steps:**

1.  **Trigger:** On Git push to the tenant definitions repository.
2.  **Checkout:** Get the latest definitions.
3.  **Detect Changes:** Identify added, modified, or deleted definition files.
4.  **Act:**
    *   **Add/Modify:** Validate schema (optional), call `POST /tenants` or `PUT /tenants/{tenant_id}` on the Control Plane API with the file content.
    *   **Delete:** Extract `tenant_id`, call `DELETE /tenants/{tenant_id}` on the Control Plane API.
    *   Use appropriate authentication (e.g., OIDC token) for API calls.

## 5. Advantages

*   **Declarative Configuration:** Tenant state defined as code.
*   **Version Control & Auditability:** Changes tracked in Git, easy rollbacks.
*   **Automation:** CI/CD pipeline automates provisioning and updates.
*   **Consistency:** Reduces manual errors and configuration drift.
*   **Leverages Existing Infrastructure:** Builds upon the current Terraform foundation within the Control Plane.

## 6. Next Steps

*   Finalize the Tenant Definition Schema (especially `spec.plugins`).
*   Implement the necessary changes in the Control Plane (`src/control-plane/main.py`).
*   Set up the Git repository for tenant definitions.
*   Configure the CI/CD pipeline.
