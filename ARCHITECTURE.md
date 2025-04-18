# AIPress Platform Architecture Overview

## 1. Vision

AIPress aims to be a highly scalable, performant, cost-effective, and user-friendly WordPress hosting platform built on Google Cloud Platform (GCP). It leverages a conversational AI interface (powered by Google Gemini) for site creation, management, and operational insights.

## 2. Core Principles

*   **Scalability:** Utilizes GCP managed services like Cloud Run and Cloud SQL that scale automatically or on demand. Designed for multi-tenancy from the ground up.
*   **Performance:** Employs multiple layers of caching (CDN, Object Cache) and optimized container runtimes.
*   **Cost-Efficiency:** Leverages Cloud Run's scale-to-zero capability and pay-per-use model. Optimizes resource usage.
*   **Security:** Strong tenant isolation via dedicated resources (Cloud Run Service, DB, GCS Bucket), robust IAM, and secrets management.
*   **Statelessness:** WordPress runtime containers are stateless, with all persistent data (DB, `wp-content`) stored in external managed services (Cloud SQL, GCS).
*   **AI-Driven UX:** Simplifies complex operations through a natural language chatbot interface.

## 3. Key Components

*   **Chatbot Interface:**
    *   **Frontend:** Web-based chat UI (React/Vue/etc.).
    *   **Backend:** API Service (Cloud Run/Functions) handling user messages, state management.
    *   **AI Core:** Google Vertex AI (Gemini) for Natural Language Understanding (NLU), intent recognition, conversational flow, and querying operational data (tenant-specific or admin-specified).
    *   **Authentication & Authorization:** Integrates with Firebase Auth (or similar) for user sign-up/login. Implements Role-Based Access Control (RBAC) distinguishing between standard Tenants and Platform Administrators.
    *   **Tenant Configuration Interface (Admin Section):**
    *   **Frontend:** Secure web interface for tenants to manage site-specific configurations.
    *   **Functionality:**
        *   Manage environment variables/secrets for *third-party* integrations relevant to their site (e.g., analytics snippets, marketing tool API keys), *excluding* core infrastructure like Cloudflare managed by the platform. These are injected into their specific Cloud Run instance.
        *   View site status and basic configuration details.
    *   **Interaction:** Communicates with the Control Plane API to store/retrieve tenant-specific settings.
*   **Control Plane:**
    *   **Configuration:** Initialized with the specific GCP Project ID where all platform and tenant resources will be deployed (e.g., via environment variables or a config file for the Control Plane service itself).
    *   **API:** Central REST API (Cloud Run/GKE) acting as the orchestrator. Authenticates requests from Chatbot Backend and Tenant Configuration Interface.
    *   **Logic:**
        *   Manages tenant lifecycle.
        *   Uses its configured service account identity to provision/configure GCP resources via GCP APIs (using SDKs or Terraform) **within the single designated platform GCP project**.
        *   **Manages DNS records (e.g., via Cloudflare API using platform credentials) for custom domains pointed to the platform.**
        *   Updates platform database.
    *   **Database:** Firestore or Cloud SQL storing platform metadata (users, tenants, site configs, **references to tenant-specific environment variables/secrets for non-core integrations**).
*   **Tenant WordPress Runtime (Per Site):**
    *   **Deployment Target:** Provisioned within the **single designated platform GCP project**.
    *   **Compute:** Dedicated Google Cloud Run Service. Auto-scales based on traffic, including scale-to-zero.
    *   **Container:** Optimized Docker image containing WordPress core, PHP-FPM, Nginx, `gcsfuse`. Dynamically configured at startup, including tenant-specific environment variables from the Admin Section.
    *   **Database:** Dedicated Google Cloud SQL Database (MySQL/Postgres) within a shared or dedicated instance.
    *   **File Storage:** Dedicated Google Cloud Storage (GCS) Bucket/Prefix mounted via `gcsfuse` to `/wp-content`. Stores themes, plugins, uploads.
    *   **Object Cache:** Google Cloud Memorystore (Redis/Memcached) instance/namespace for WordPress object caching.
*   **Networking & Delivery:**
    *   **CDN:** Google Cloud CDN primarily. If Cloudflare is used (especially for custom domains), its configuration (DNS, potentially basic settings) is managed by the **Platform Control Plane** using platform credentials.
    *   **DNS:** Cloud DNS (or external) for mapping subdomains/custom domains.
*   **Monitoring & Operations:**
    *   **Logging:** Google Cloud Logging collecting logs from all services.
    *   **Metrics:** Google Cloud Monitoring collecting metrics.
    *   **Billing:**
        *   Google Cloud Billing Export to BigQuery (enabled for detailed, labeled cost data).
        *   Google Cloud Billing API (for potentially higher-level checks or budget alerts).

## 4. Core Workflows

*   **Site Creation:** User interacts with Chatbot -> Chatbot BE gathers info via Gemini -> Chatbot BE calls Control Plane API -> Control Plane provisions GCP resources (Cloud Run, SQL, GCS, etc.) -> Control Plane updates its DB -> Chatbot informs user.
*   **User Request:** User request hits CDN -> CDN serves cache or forwards to Cloud Run -> Cloud Run instance (stateless) serves request, interacting with Cloud SQL (DB), GCS (files via `gcsfuse`), and Memorystore (cache). All tenant resources are labeled (e.g., `aipress-tenant-id: ...`).
*   **Operational Query (Logs/Metrics - Tenant):** Tenant asks Chatbot ("show my logs") -> Chatbot BE (checks role) -> Uses Gemini -> Chatbot BE queries Logging/Monitoring API, filtering by *logged-in user's* tenant labels/resources -> Chatbot BE presents info.
*   **Operational Query (Logs/Metrics - Admin):** Admin asks Chatbot ("show logs for site xyz") -> Chatbot BE (checks role) -> Uses Gemini (extracts target tenant ID 'xyz') -> Chatbot BE queries Logging/Monitoring API, filtering by *specified tenant ID 'xyz'* labels/resources -> Chatbot BE presents info.
*   **Operational Query (Billing - Tenant):** Tenant asks Chatbot ("show my bill") -> Chatbot BE (checks role) -> Uses Gemini -> Calls Control Plane API `/tenants/{loggedInUserTenantId}/billing` -> Control Plane retrieves data -> Chatbot BE presents info.
*   **Operational Query (Billing - Admin):** Admin asks Chatbot ("show bill for tenant xyz") -> Chatbot BE (checks role) -> Uses Gemini (extracts target tenant ID 'xyz') -> Calls Control Plane API `/tenants/{specifiedTenantId}/billing` -> Control Plane retrieves data -> Chatbot BE presents info.

*(Consider adding the Mermaid diagram here once finalized)*
