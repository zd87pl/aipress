# AIPress Platform Backlog

This backlog outlines the major phases, epics, and features required to build the AI-driven WordPress hosting platform.

## Phase 1: Foundational Setup

*Goal: Establish the core GCP environment, security baseline, and development infrastructure.*

*   **Epic: GCP Project & Networking**
    *   Feature: Create dedicated GCP Project.
    *   Feature: Set up VPC Network, Subnets, Firewall Rules (basic).
    *   Feature: Configure Cloud DNS (if managing platform domain).
*   **Epic: Identity & Access Management (IAM)**
    *   Feature: Define core IAM roles (Platform Admin, Control Plane Service Account, Tenant Runtime Service Account base).
    *   Feature: Set up initial user/group access.
*   **Epic: CI/CD Pipeline**
    *   Feature: Set up Git repository (e.g., GitHub, Cloud Source Repositories).
    *   Feature: Implement basic CI pipeline (e.g., Cloud Build) for linting/testing (initially).
    *   Feature: Implement basic CD pipeline skeleton for deploying control plane/chatbot backend.
*   **Epic: Secrets Management**
    *   Feature: Set up Google Secret Manager.
    *   Feature: Define initial secret structure (API keys, DB credentials patterns).

## Phase 2: MVP Chatbot & Control Plane API

*Goal: Build the user-facing chat interface, core control plane API, and basic site creation flow.*

*   **Epic: Authentication & Authorization (RBAC)**
    *   Feature: Implement user signup/login (Google, Apple, Email Link) using Firebase Auth or similar.
    *   Feature: Define and implement roles (e.g., 'Tenant', 'Admin') using custom claims or similar mechanism.
    *   Feature: Integrate Auth/Authz checks into Chatbot Frontend & Backend.
    *   Feature: Integrate Auth/Authz checks into Tenant Admin UI.
*   **Epic: Chatbot Frontend**
    *   Feature: Create basic web application structure (React, Vue, etc.).
    *   Feature: Implement chat message display interface.
    *   Feature: Implement message input component.
    *   Feature: Connect frontend to Chatbot Backend API.
*   **Epic: Chatbot Backend**
    *   Feature: Create API service (Cloud Run/Functions - Node.js/Python/Go).
    *   Feature: Implement WebSocket or polling for real-time chat feel.
    *   Feature: Basic API endpoint to receive messages & user context.
    *   Feature: Integrate with Vertex AI (Gemini) API.
    *   Feature: Implement Gemini prompting for basic intent recognition (site creation, operational queries).
    *   Feature: **Enhance Gemini prompting to extract target tenant identifiers from Admin requests.**
    *   Feature: Implement conversational flow logic (asking questions for site creation).
    *   Feature: **Implement RBAC checks within API handlers.**
    *   Feature: **Parameterize query logic to use logged-in tenant ID or admin-specified tenant ID.**
    *   Feature: Integrate with Control Plane API.
*   **Epic: Control Plane API (Core)**
    *   Feature: Create API service (Cloud Run/GKE - Node.js/Python/Go).
    *   Feature: Define initial API specification (OpenAPI).
    *   Feature: Implement endpoint for initiating site creation request.
    *   Feature: Set up database (Firestore/Cloud SQL) for storing tenant/site metadata.
    *   Feature: Basic API authentication/authorization (validating tokens from Chatbot BE / Tenant Admin FE).
    *   Feature: **Enhance API authorization to potentially restrict certain actions based on role.**
*   **Epic: Control Plane Initial Configuration**
    *   Feature: Define mechanism for providing target GCP Project ID to Control Plane (e.g., Env Var, Config File).
    *   Feature: Ensure Control Plane service account has necessary permissions within the target project (including Billing API/BigQuery access).
    *   Feature: **Securely configure platform's Cloudflare API credentials (or other DNS provider) for Control Plane.**
*   **Epic: Billing Configuration**
    *   Feature: Enable detailed GCP Billing Export to a BigQuery dataset within the platform project.
    *   Feature: Define and **enforce mandatory labeling (`aipress-tenant-id`)** for all tenant-specific resources during provisioning.
*   **Epic: Tenant Configuration Interface (Admin UI)**
    *   Feature: Create basic web application structure for Admin section (can reuse Chatbot FE structure/libs).
    *   Feature: Implement UI component for managing tenant-specific environment variables/secrets for *third-party integrations* (key-value pairs, marking sensitive values).
    *   Feature: Connect Admin UI to Control Plane API endpoints.
    *   Feature: Integrate Authentication with Admin UI.
*   **Epic: Control Plane API (Tenant Env Var Support)**
    *   Feature: API endpoint to securely store/retrieve tenant-specific environment variables/secrets for *third-party integrations* (linking to Secret Manager).
*   **Epic: Control Plane API (DNS/CDN Management)**
    *   Feature: Implement logic to interact with Cloudflare API (or other DNS provider) using platform credentials.
    *   Feature: API endpoint/logic for adding/updating DNS records for custom domains.
    *   Feature: API endpoint/logic for potentially configuring basic CDN settings via API.

## Phase 3: Tenant WordPress Runtime

*Goal: Implement the actual WordPress hosting infrastructure components provisioned by the Control Plane.*

*   **Epic: WordPress Container Image**
    *   Feature: Create Dockerfile with base OS, PHP, Nginx/Apache.
    *   Feature: Install specific WordPress version.
    *   Feature: Install and configure `gcsfuse`.
    *   Feature: Implement entrypoint script for dynamic `wp-config.php` generation / GCS mount.
    *   Feature: Integrate Memorystore (Redis) client/extensions.
    *   Feature: Optimize image size and performance.
*   **Epic: Resource Provisioning Logic (Control Plane - Single Project)**
    *   Feature: Implement GCP API calls (Terraform or SDK) to create Cloud Run service per tenant within the configured project.
    *   Feature: Implement GCP API calls to create Cloud SQL database (or DB within shared instance) within the configured project.
    *   Feature: Implement GCP API calls to create GCS bucket/prefix per tenant within the configured project.
    *   Feature: Implement secure injection of standard secrets (DB credentials, etc.) into Cloud Run via Secret Manager.
    *   Feature: Implement **secure injection of tenant-specific *third-party* environment variables/secrets (from Admin UI) into the specific tenant's Cloud Run service**.
    *   Feature: Implement provisioning of Memorystore namespace/instance within the configured project.
    *   Feature: Implement basic Google Cloud CDN configuration for Cloud Run service.
    *   Feature: **Integrate Control Plane logic to configure DNS (via platform API keys) when custom domains are used.**
    *   Feature: Update tenant metadata DB upon successful provisioning.
*   **Epic: Domain Management (MVP)**
    *   Feature: Assign platform subdomain (`tenant-name.aipress.com`) via DNS (if applicable).
    *   Feature: Provide DNS instructions for custom domains.

## Phase 4: Operational Features (Chatbot SRE)**

*Goal: Enable the chatbot to provide basic operational insights.*

*   **Epic: Logging Integration (RBAC)**
    *   Feature: Configure Cloud Run/WordPress to send structured logs to Cloud Logging.
    *   Feature: Chatbot Backend logic to query Cloud Logging, **filtering by logged-in tenant ID or admin-specified tenant ID based on role**.
    *   Feature: Gemini prompting to understand log query requests, including target tenant for admins.
*   **Epic: Metrics Integration (RBAC)**
    *   Feature: Ensure Cloud Run/Cloud SQL metrics are sent to Cloud Monitoring.
    *   Feature: Chatbot Backend logic to query Cloud Monitoring, **filtering by logged-in tenant ID or admin-specified tenant ID based on role**.
    *   Feature: Gemini prompting to understand metrics requests, including target tenant for admins.
*   **Epic: Cost Aggregation & Reporting**
    *   Feature: Create backend process (Cloud Function/Run) to query BigQuery billing export data.
    *   Feature: Implement BigQuery SQL query to aggregate costs per `aipress-tenant-id` label.
    *   Feature: Store aggregated tenant cost data in Control Plane database (Firestore/Cloud SQL).
    *   Feature: Schedule the aggregation process to run periodically (e.g., daily).
    *   Feature: Control Plane API endpoint (`/tenants/{tenant_id}/billing`) to retrieve aggregated cost data.
*   **Epic: Cost Integration (Chatbot - RBAC)**
    *   Feature: Chatbot Backend logic to call the Control Plane billing API endpoint, **using logged-in tenant ID or admin-specified tenant ID based on role**.
    *   Feature: Gemini prompting to understand billing inquiries, including target tenant for admins.
*   **Epic: Basic Site Management**
    *   Feature: Control Plane API endpoint for deleting a site (resource cleanup within the platform project).
    *   Feature: Chatbot integration for site deletion requests.

## Phase 5: Enhancements & Scalability

*Goal: Improve performance, security, cost-efficiency, and add advanced features.*

*   **Epic: Advanced Caching**
    *   Feature: Implement tiered caching strategies.
    *   Feature: Explore edge compute options.
*   **Epic: Security Hardening**
    *   Feature: Implement Cloud Armor WAF rules.
    *   Feature: Explore runtime security monitoring (Falco/SCC).
    *   Feature: Implement automated vulnerability scanning.
*   **Epic: Performance Optimization**
    *   Feature: Implement proactive asset optimization.
    *   Feature: Advanced database tuning/read replicas.
*   **Epic: Cost Optimization**
    *   Feature: Implement smart Cloud Run/SQL tiering.
    *   Feature: Implement GCS lifecycle rules.
*   **Epic: Feature Enhancements**
    *   Feature: Automated custom domain validation/setup.
    *   Feature: Backup & Restore functionality (via Control Plane/Chatbot).
    *   Feature: Staging environments.
    *   Feature: Pre-installed plugin/theme bundles.
