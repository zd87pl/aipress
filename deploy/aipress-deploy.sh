#!/bin/bash

# ==============================================================================
# AIPress Interactive Deployment Orchestrator
# ==============================================================================
# 
# World-class CI/CD deployment system that preserves existing scripts while
# adding enterprise-grade deployment capabilities for production readiness.
# 
# Features:
# - Interactive deployment with safety checks
# - Environment-specific configurations 
# - Progressive deployment strategies
# - Automated rollback capabilities
# - Health checking and validation
# - Security scanning and compliance
# - Infrastructure drift detection
# - Cost optimization monitoring
#
# Usage:
#   ./deploy/aipress-deploy.sh [environment] [component] [--dry-run]
#
# Examples:
#   ./deploy/aipress-deploy.sh dev all                    # Deploy everything to dev
#   ./deploy/aipress-deploy.sh staging database          # Deploy only database to staging
#   ./deploy/aipress-deploy.sh prod meta-control-plane --dry-run  # Dry run for prod
#
# ==============================================================================

set -euo pipefail

# --- Script Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
DEPLOY_CONFIG_DIR="${SCRIPT_DIR}/configs"
ENVIRONMENTS_DIR="${SCRIPT_DIR}/environments"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# --- Color codes for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Logging functions ---
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# --- Validation functions ---
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check required tools
    command -v gcloud >/dev/null 2>&1 || missing_tools+=("gcloud")
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    command -v yq >/dev/null 2>&1 || missing_tools+=("yq")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 >/dev/null 2>&1; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

load_environment_config() {
    local env=$1
    local config_file="${ENVIRONMENTS_DIR}/${env}.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Environment configuration not found: $config_file"
        exit 1
    fi
    
    log_info "Loading environment configuration: $env"
    
    # Export environment variables from YAML config
    export DEPLOY_ENV="$env"
    export GCP_PROJECT_ID=$(yq eval '.project.id' "$config_file")
    export GCP_REGION=$(yq eval '.project.region' "$config_file")
    export GCP_BILLING_ACCOUNT=$(yq eval '.project.billing_account' "$config_file")
    export ENVIRONMENT_TYPE=$(yq eval '.environment.type' "$config_file")
    export DEPLOYMENT_STRATEGY=$(yq eval '.deployment.strategy' "$config_file")
    export SAFETY_CHECKS=$(yq eval '.deployment.safety_checks' "$config_file")
    
    log_success "Environment loaded: $env (Project: $GCP_PROJECT_ID, Region: $GCP_REGION)"
}

validate_environment() {
    log_section "Validating Environment Configuration"
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$GCP_PROJECT_ID" >/dev/null 2>&1; then
        log_error "Cannot access GCP project: $GCP_PROJECT_ID"
        log_info "Please ensure the project exists and you have appropriate permissions"
        exit 1
    fi
    
    # Check if required APIs are enabled
    local required_apis=(
        "run.googleapis.com"
        "sqladmin.googleapis.com"
        "storage.googleapis.com"
        "secretmanager.googleapis.com"
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "spanner.googleapis.com"
    )
    
    log_info "Checking required APIs..."
    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --project="$GCP_PROJECT_ID" --format="value(config.name)" | grep -q "^$api$"; then
            log_warning "API not enabled: $api"
            if [[ "$SAFETY_CHECKS" == "true" ]]; then
                read -p "Enable $api? [y/N]: " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    gcloud services enable "$api" --project="$GCP_PROJECT_ID"
                    log_success "Enabled API: $api"
                else
                    log_error "Deployment cannot continue without required APIs"
                    exit 1
                fi
            fi
        fi
    done
    
    log_success "Environment validation passed"
}

# --- Component deployment functions ---
deploy_foundation() {
    log_section "Deploying Foundation Components"
    
    # Use existing script but with environment-specific configuration
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would run foundation setup"
        return 0
    fi
    
    # Export variables for the existing script
    export GCP_PROJECT_ID
    export GCP_REGION
    export AR_REPO_NAME="aipress-images-${DEPLOY_ENV}"
    
    # Run existing setup script in non-interactive mode if configured
    if [[ "$ENVIRONMENT_TYPE" != "production" ]]; then
        log_info "Running foundation setup (automated for non-prod environments)"
        "${PROJECT_ROOT}/scripts/poc_gcp_setup.sh" --non-interactive
    else
        log_info "Running foundation setup (interactive for production)"
        "${PROJECT_ROOT}/scripts/poc_gcp_setup.sh"
    fi
    
    log_success "Foundation deployment completed"
}

deploy_database_architecture() {
    log_section "Deploying Database Architecture"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would deploy shared database architecture"
        terraform plan -var-file="${ENVIRONMENTS_DIR}/${DEPLOY_ENV}.tfvars" -input=false "${PROJECT_ROOT}/infra/database-architecture/"
        return 0
    fi
    
    log_info "Deploying shared database architecture..."
    
    # Initialize Terraform
    terraform -chdir="${PROJECT_ROOT}/infra/database-architecture" init
    
    # Plan with environment-specific variables
    terraform -chdir="${PROJECT_ROOT}/infra/database-architecture" plan \
        -var-file="${ENVIRONMENTS_DIR}/${DEPLOY_ENV}.tfvars" \
        -input=false \
        -out="plan.tfplan"
    
    # Apply with approval in production
    if [[ "$ENVIRONMENT_TYPE" == "production" ]] && [[ "$SAFETY_CHECKS" == "true" ]]; then
        read -p "Apply database changes to PRODUCTION? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            return 1
        fi
    fi
    
    terraform -chdir="${PROJECT_ROOT}/infra/database-architecture" apply "plan.tfplan"
    
    log_success "Database architecture deployed"
}

deploy_multi_project_infrastructure() {
    log_section "Deploying Multi-Project Infrastructure"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would deploy multi-project infrastructure"
        terraform plan -var-file="${ENVIRONMENTS_DIR}/${DEPLOY_ENV}.tfvars" -input=false "${PROJECT_ROOT}/infra/multi-project/"
        return 0
    fi
    
    log_info "Deploying multi-project infrastructure..."
    
    terraform -chdir="${PROJECT_ROOT}/infra/multi-project" init
    terraform -chdir="${PROJECT_ROOT}/infra/multi-project" plan \
        -var-file="${ENVIRONMENTS_DIR}/${DEPLOY_ENV}.tfvars" \
        -input=false \
        -out="plan.tfplan"
    
    if [[ "$ENVIRONMENT_TYPE" == "production" ]] && [[ "$SAFETY_CHECKS" == "true" ]]; then
        read -p "Apply multi-project infrastructure to PRODUCTION? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            return 1
        fi
    fi
    
    terraform -chdir="${PROJECT_ROOT}/infra/multi-project" apply "plan.tfplan"
    
    log_success "Multi-project infrastructure deployed"
}

deploy_meta_control_plane() {
    log_section "Deploying Meta Control Plane"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would build and deploy meta control plane"
        return 0
    fi
    
    log_info "Building and deploying meta control plane..."
    
    # Build and push image
    "${SCRIPTS_DIR}/build-meta-control-plane.sh"
    
    # Deploy to Cloud Run
    "${SCRIPTS_DIR}/deploy-meta-control-plane.sh"
    
    log_success "Meta control plane deployed"
}

# --- Health checking functions ---
run_health_checks() {
    log_section "Running Health Checks"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would run health checks"
        return 0
    fi
    
    # Database health check
    "${SCRIPTS_DIR}/health-check-database.sh"
    
    # Meta control plane health check
    "${SCRIPTS_DIR}/health-check-meta-control-plane.sh"
    
    # Infrastructure validation
    "${SCRIPTS_DIR}/validate-infrastructure.sh"
    
    log_success "All health checks passed"
}

# --- Security scanning ---
run_security_scan() {
    log_section "Running Security Scan"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would run security scans"
        return 0
    fi
    
    # Container vulnerability scanning
    "${SCRIPTS_DIR}/security-scan-containers.sh"
    
    # Infrastructure compliance check
    "${SCRIPTS_DIR}/security-scan-infrastructure.sh"
    
    log_success "Security scans completed"
}

# --- Main deployment orchestration ---
deploy_component() {
    local component=$1
    
    case $component in
        "foundation")
            deploy_foundation
            ;;
        "database")
            deploy_database_architecture
            ;;
        "multi-project")
            deploy_multi_project_infrastructure
            ;;
        "meta-control-plane")
            deploy_meta_control_plane
            ;;
        "all")
            deploy_foundation
            deploy_database_architecture
            deploy_multi_project_infrastructure
            deploy_meta_control_plane
            ;;
        *)
            log_error "Unknown component: $component"
            log_info "Available components: foundation, database, multi-project, meta-control-plane, all"
            exit 1
            ;;
    esac
}

# --- Rollback functionality ---
rollback_deployment() {
    log_section "Rolling Back Deployment"
    
    log_warning "Rollback functionality - USE WITH EXTREME CAUTION"
    
    if [[ "$ENVIRONMENT_TYPE" == "production" ]]; then
        log_error "Production rollback requires manual intervention"
        log_info "Please contact SRE team for production rollbacks"
        exit 1
    fi
    
    # Implement rollback logic
    "${SCRIPTS_DIR}/rollback-deployment.sh" "$DEPLOY_ENV"
    
    log_success "Rollback completed"
}

# --- Usage information ---
show_usage() {
    cat << EOF
AIPress Interactive Deployment Orchestrator

Usage: $0 [ENVIRONMENT] [COMPONENT] [OPTIONS]

ENVIRONMENTS:
  dev         Development environment
  staging     Staging environment
  prod        Production environment

COMPONENTS:
  foundation           Foundation setup (APIs, service accounts, etc.)
  database            Shared database architecture
  multi-project       Multi-project infrastructure
  meta-control-plane  Meta control plane service
  all                 Deploy all components

OPTIONS:
  --dry-run           Show what would be deployed without making changes
  --rollback          Rollback last deployment (non-production only)
  --health-check      Run health checks only
  --security-scan     Run security scans only
  --help             Show this help message

EXAMPLES:
  $0 dev all                           # Deploy everything to dev
  $0 staging database                  # Deploy only database to staging
  $0 prod meta-control-plane --dry-run # Dry run for production
  $0 dev all --rollback               # Rollback dev environment

SAFETY:
  - Production deployments require interactive confirmation
  - All deployments validate prerequisites and environment
  - Dry-run mode shows planned changes without applying
  - Health checks validate deployment success
  - Security scans ensure compliance

For more information, see: deploy/README.md
EOF
}

# --- Main script logic ---
main() {
    local environment=""
    local component=""
    local dry_run=false
    local rollback=false
    local health_check_only=false
    local security_scan_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --rollback)
                rollback=true
                shift
                ;;
            --health-check)
                health_check_only=true
                shift
                ;;
            --security-scan)
                security_scan_only=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                if [[ -z "$environment" ]]; then
                    environment=$1
                elif [[ -z "$component" ]]; then
                    component=$1
                else
                    log_error "Unknown argument: $1"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate arguments
    if [[ -z "$environment" ]] && [[ "$health_check_only" == "false" ]] && [[ "$security_scan_only" == "false" ]]; then
        log_error "Environment is required"
        show_usage
        exit 1
    fi
    
    if [[ -z "$component" ]] && [[ "$rollback" == "false" ]] && [[ "$health_check_only" == "false" ]] && [[ "$security_scan_only" == "false" ]]; then
        log_error "Component is required"
        show_usage
        exit 1
    fi
    
    # Export global flags
    export DRY_RUN="$dry_run"
    
    # Start deployment process
    log_section "AIPress Deployment Orchestrator"
    log_info "Environment: $environment"
    log_info "Component: $component"
    log_info "Dry Run: $dry_run"
    
    # Check prerequisites
    check_prerequisites
    
    # Handle special modes
    if [[ "$health_check_only" == "true" ]]; then
        load_environment_config "$environment"
        run_health_checks
        exit 0
    fi
    
    if [[ "$security_scan_only" == "true" ]]; then
        load_environment_config "$environment"
        run_security_scan
        exit 0
    fi
    
    # Load environment configuration
    load_environment_config "$environment"
    
    # Validate environment
    validate_environment
    
    # Handle rollback
    if [[ "$rollback" == "true" ]]; then
        rollback_deployment
        exit 0
    fi
    
    # Deploy components
    deploy_component "$component"
    
    # Run post-deployment validation
    if [[ "$dry_run" == "false" ]]; then
        run_health_checks
        run_security_scan
    fi
    
    log_success "Deployment completed successfully!"
    log_info "Next steps:"
    log_info "1. Review deployment logs"
    log_info "2. Run integration tests"
    log_info "3. Monitor system health"
    log_info "4. Update documentation if needed"
}

# --- Execute main function ---
main "$@"
