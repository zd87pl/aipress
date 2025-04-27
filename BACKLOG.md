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

*Goal: Build the user-facing chat interface, admin portal, core control plane API, authentication, and basic site creation flow using Gemini as the conversational engine.*

*   **Epic: Authentication & Authorization (RBAC)**
    *   Feature: Choose and configure managed authentication provider (Firebase Auth recommended).
    *   Feature: Implement user signup/login flows (Google, Apple, GitHub, Email Link/Passwordless) using provider SDK.
    *   Feature: Define 'Tenant' and 'Admin' roles. Implement role assignment on first sign-up (default 'Tenant').
    *   Feature: Implement role management UI (Admin Portal).
    *   Feature: Utilize Custom Claims (if available) to embed roles in auth tokens.
    *   Feature: Implement token verification middleware in Chatbot Backend and Control Plane API.
    *   Feature: Implement endpoint-level authorization checks based on verified role and tenant ownership in both backends.
*   **Epic: Chatbot Frontend (React + TypeScript + Tailwind)**
    *   Feature: Set up React project using TypeScript and Tailwind CSS.
    *   Feature: Implement Design System components (light, clean aesthetic inspired by Apple/Uber):
        *   `Button.tsx`, `TextInput.tsx`, `Modal.tsx`, `ChatMessage.tsx`, `ChatLog.tsx`, `ChatInput.tsx`, `LogDisplay.tsx`, `DataTable.tsx`, `LoadingSpinner.tsx`.
    *   Feature: Implement core chat interface using the design system components.
    *   Feature: Integrate authentication provider SDK for login/signup/logout UI flows (`LoginButton` variants, user status display).
    *   Feature: Implement API client to communicate with Chatbot Backend (sending messages, handling responses). Attach auth token to requests.
*   **Epic: Chatbot Backend (FastAPI + Vertex AI)**
    *   Feature: Set up FastAPI project, including Dockerfile.
    *   Feature: Add dependencies: `google-cloud-aiplatform`, `google-auth`, `requests`.
    *   Feature: Implement `/chat` endpoint to handle incoming user messages.
    *   Feature: Integrate authentication token verification middleware.
    *   Feature: Implement Gemini integration using Vertex AI SDK.
    *   Feature: Develop robust prompt engineering strategy for Gemini:
        *   Define Gemini's role and capabilities.
        *   Include chat history, user context (tenant\_id).
        *   Define structured "Action" commands (e.g., `CREATE_SITE`, `GET_LOGS`, `DELETE_SITE`).
        *   Implement safety guidelines.
    *   Feature: Implement logic to interpret Gemini's response (text vs. Action).
    *   Feature: Implement action validation (permissions, parameters) based on authenticated user and recognized action.
    *   Feature: Implement client logic to call Control Plane API for validated actions.
    *   Feature: Implement logic to format Control Plane responses (or use Gemini) for user display.
*   **Epic: Control Plane API (Enhancements for Chatbot & Admin)**
    *   Feature: Enhance FastAPI service setup (authentication middleware, OpenAPI spec).
    *   Feature: Implement API endpoints for user management (`/users`, `/users/{id}` - Admin only).
    *   Feature: Implement API endpoints for tenant management/viewing (`/tenants`, `/tenants/{id}` - Admin/Tenant specific).
    *   Feature: Implement API endpoints for operational data (`/tenants/{id}/logs`, `/tenants/{id}/billing` - Admin/Tenant specific, RBAC enforced).
    *   Feature: Implement API endpoint for site deletion (`/tenants/{id}` DELETE - Admin/Tenant specific).
    *   Feature: Refine database schema (Firestore/Cloud SQL) to store user roles and tenant associations.
    *   Feature: Implement robust authorization logic within each endpoint based on verified token/role/ownership.
    *   Feature: Define secure mechanism for storing/retrieving tenant-specific credentials needed for operations (e.g., log access keys managed via Secret Manager, linked in DB).
*   **Epic: Control Plane Initial Configuration**
    *   Feature: Define mechanism for providing target GCP Project ID to Control Plane (e.g., Env Var, Config File).
    *   Feature: Ensure Control Plane service account has necessary permissions within the target project (including Billing API/BigQuery access, Secret Manager access).
    *   Feature: **Securely configure platform's Cloudflare API credentials (or other DNS provider) for Control Plane.**
*   **Epic: Billing Configuration**
    *   Feature: Enable detailed GCP Billing Export to a BigQuery dataset within the platform project.
    *   Feature: Define and **enforce mandatory labeling (`aipress-tenant-id`)** for all tenant-specific resources during provisioning.
*   **Epic: Tenant Configuration Interface (Admin UI - React)**
    *   Feature: Set up Admin Portal section within the React frontend (potentially separate route/entry point).
    *   Feature: Implement Design System components specific to Admin Portal:
        *   `AdminLayout.tsx`, `SidebarNav.tsx`, `UserTable.tsx`, `UserForm.tsx`, `TenantList.tsx`, `SecretInput.tsx`.
    *   Feature: Implement UI views for User Management, Tenant Listing/Details, using the design system components.
    *   Feature: Integrate Authentication provider SDK for Admin login. Ensure UI routes/components are protected based on 'Admin' role.
    *   Feature: Connect Admin UI views to relevant Control Plane API endpoints (fetching users/tenants, managing roles, potentially managing tenant config/secrets).
*   **Epic: Control Plane API (Tenant Env Var & Secure Config)**
    *   Feature: Implement API endpoints for Admin to manage tenant-specific configuration/secrets (e.g., service account keys for log access), storing securely (e.g., Secret Manager integration).

*   **(Moved DNS/CDN logic to later phase or integrate as needed for custom domains)**
    *   ~~Feature: API endpoint/logic for adding/updating DNS records for custom domains.~~
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
    *   **Feature: Cloud Run Right-Sizing Analysis:** Analyze tenant resource usage (CPU/Memory) to potentially use fractional vCPUs or smaller memory allocations for lower-tier/lower-traffic sites.
    *   **Feature: Cloud Run Concurrency Tuning:** Experiment with and document optimal concurrency settings based on typical WordPress workloads.
    *   **Feature: Implement Tiered `min-instances` Option:** Offer a higher performance tier with `min-instances=1` for reduced cold starts.
    *   **Feature: Evaluate ARM Architecture for Cloud Run:** Investigate building and deploying ARM64-based `wordpress-runtime` images for potential price/performance benefits.
    *   **Feature: Profile & Optimize `docker-entrypoint.sh`:** Reduce container startup latency by optimizing the entrypoint script.
    *   **Feature: Implement Full Page Caching Strategy:** Integrate and configure a robust WordPress page caching plugin (e.g., WP Super Cache, W3 Total Cache).
    *   **Feature: GCS Signed URLs for Media:** Ensure WP Offload Media (or equivalent) is configured to use Signed URLs for direct client uploads/downloads.
    *   **(If using `gcsfuse`): Feature: `gcsfuse` Performance Tuning:** Optimize mount options (`stat-cache-ttl`, `type-cache-ttl`, `--implicit-dirs`) if `gcsfuse` is used for themes/plugins.
    *   **Feature: Implement Cloud SQL Read Replicas Option:** Offer read replicas as a feature for high-traffic/read-heavy sites.
    *   **Feature: Provide Cloud SQL Query Insights Guidance:** Develop documentation or tooling to help tenants identify slow queries.
    *   Feature: Implement proactive asset optimization (existing).
    *   Feature: Advanced database tuning/read replicas (covered above, refined).
*   **Epic: Cost Optimization**
    *   **Feature: Analyze & Implement Committed Use Discounts (CUDs):** Regularly review sustained usage and purchase CUDs for Cloud Run, Cloud SQL, and Memorystore baseline needs.
    *   **Feature: Evaluate Shared Cloud SQL Instance Model:** Investigate using separate databases within shared Cloud SQL instances as a potential lower-cost tier.
    *   **Feature: Evaluate Shared Memorystore Instance Model:** Investigate using Redis namespaces within shared Memorystore instances as a potential lower-cost tier.
    *   **Feature: Implement GCS Lifecycle Policies:** Define and apply rules for transitioning objects to cheaper storage classes or deleting old backups/data.
    *   **Feature: Evaluate GCP Network Service Tiers:** Assess if Standard Tier networking is suitable for certain use cases or tenant tiers instead of Premium Tier.
    *   Feature: Implement smart Cloud Run/SQL tiering (existing, could be refined by above).
    *   Feature: Implement GCS lifecycle rules (covered above, refined).
*   **Epic: Advanced Caching & CDN**
    *   **Feature: Implement Tiered Caching Strategies:** Configure CDN with multiple cache layers if beneficial.
    *   **Feature: Leverage Advanced CDN Features:** Implement edge image optimization, advanced routing (e.g., Cloudflare Argo).
    *   **Feature: Explore Edge Compute Options:** Investigate Cloudflare Workers or similar for edge-side caching or logic.
*   **Epic: Feature Enhancements**
    *   Feature: Automated custom domain validation/setup.
    *   Feature: Backup & Restore functionality (via Control Plane/Chatbot).
    *   Feature: Staging environments.
    *   Feature: Pre-installed plugin/theme bundles.
*   **(New Epic): Database Enhancements**
    *   **Feature: Implement Robust Connection Pooling:** Ensure efficient PHP-FPM and Cloud SQL Auth Proxy connection handling.
    *   **Feature: Monitor & Alert on DB Connection Limits.**
    *   **Feature: Explore Serverless Database Options:** Keep Cloud SQL Serverless v2 / AlloyDB Omni under consideration for future needs.
