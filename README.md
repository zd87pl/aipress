# AIPress

AIPress is a scalable, multi-tenant WordPress hosting platform built on Google Cloud Platform (GCP). It automates site provisioning, management, and operations using a modern control plane, infrastructure-as-code, and (in progress) an AI-powered conversational interface and monitoring dashboard.

---

## Project Status

- **Backend, Infrastructure, and Control Plane:** Production-grade, ready for review and deployment.
- **AI Frontend Interface & Monitoring Dashboard:** In progress (not yet production-ready).

---

## Architecture Overview

- **Meta Control Plane:** Central FastAPI service for tenant-to-shard routing, project orchestration, and global health monitoring.
- **Shard Projects:** Each GCP project (shard) contains:
  - **Control Plane API:** FastAPI service for tenant provisioning and resource management.
  - **Tenant WordPress Runtimes:** Stateless WordPress sites on Cloud Run, each with a dedicated Cloud SQL database and GCS bucket.
  - **Plugin Installer Job:** Cloud Run Job for automated plugin management.
  - **Secret Manager:** Per-tenant secrets for DB credentials and WordPress salts.
- **Shared Services:**
  - **Backend:** FastAPI for chatbot and admin APIs.
  - **Autoscaler:** Cloud Function for monitoring and scaling tenant resources.
  - **Frontend:** React SPA with Firebase Auth (in progress).
- **Infrastructure as Code:** All resources managed via Terraform, with modular design for multi-project federation and tenant isolation.
- **CI/CD:** Cloud Build pipelines for build, test, deploy, and security scanning.

---

## Key Features

- **Automated Tenant Provisioning:** One-click or API-driven creation of isolated WordPress sites.
- **Strong Tenant Isolation:** Each tenant is isolated at the GCP project and resource level.
- **Secret Management:** All sensitive credentials are generated and stored in GCP Secret Manager.
- **Least Privilege IAM:** Service accounts are granted only the permissions required for their function.
- **No Public Endpoints by Default:** Cloud Run services are private unless explicitly allowed.
- **Scalable Architecture:** Designed to support 50,000+ WordPress sites.
- **Infrastructure as Code:** All infrastructure is reproducible and version-controlled.

---

## Quick Start

### Prerequisites

- Google Cloud SDK (`gcloud`)
- Terraform
- Docker
- Node.js & npm (for frontend)
- Python 3.11+ (for backend/control plane)

### Setup

1. **Clone the repository:**
   ```
   git clone <repo-url>
   cd aipress
   ```

2. **Configure GCP and Terraform:**
   - See `docs/` for detailed setup and environment configuration.
   - Run `deploy/aipress-deploy.sh` for orchestrated deployment.

3. **Build and Deploy Components:**
   - Use scripts in `scripts/` for building and pushing Docker images.
   - Use Terraform modules in `infra/` for infrastructure provisioning.

4. **Run Locally (Development):**
   - Backend: `cd src/control-plane && uvicorn main:app --reload`
   - Frontend: `cd src/chatbot-frontend && npm install && npm run dev`

---

## Documentation

- All detailed documentation is in the `docs/` directory.
  - [EXECUTIVE_SUMMARY.md](docs/EXECUTIVE_SUMMARY.md)
  - [ARCHITECTURE.md](docs/ARCHITECTURE.md)
  - [MIGRATION_PLAN.md](docs/MIGRATION_PLAN.md)
  - [SCALING_TO_50K_SITES.md](docs/SCALING_TO_50K_SITES.md)
  - [TENANT_AS_CODE_DESIGN.md](docs/TENANT_AS_CODE_DESIGN.md)
  - [IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md)
  - [BACKLOG.md](docs/BACKLOG.md)
  - [UNIFIED_ROADMAP.md](docs/UNIFIED_ROADMAP.md)
  - [DOCUMENTATION_INDEX.md](docs/DOCUMENTATION_INDEX.md)

---

## Security

- All secrets are managed via GCP Secret Manager.
- No hardcoded credentials in code or images.
- IAM follows least privilege principles.
- No public endpoints unless explicitly configured.
- See [Security Review Context](docs/EXECUTIVE_SUMMARY.md) for more details.

---

## Contributing

Contributions are welcome! Please see the [BACKLOG.md](docs/BACKLOG.md) and [UNIFIED_ROADMAP.md](docs/UNIFIED_ROADMAP.md) for open tasks and future plans.

---

## License

[MIT](LICENSE) (or your project's license)
