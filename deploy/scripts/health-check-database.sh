#!/bin/bash

# ==============================================================================
# Database Architecture Health Check
# ==============================================================================

set -euo pipefail

# --- Configuration ---
GCP_PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID must be set}"
GCP_REGION="${GCP_REGION:?GCP_REGION must be set}"
DEPLOY_ENV="${DEPLOY_ENV:?DEPLOY_ENV must be set}"

echo "Running database architecture health checks..."
echo "Project: $GCP_PROJECT_ID"
echo "Environment: $DEPLOY_ENV"

# --- Check Cloud SQL Instance ---
echo "Checking Cloud SQL instances..."
SHARED_INSTANCE_NAME="aipress-shared-db-${DEPLOY_ENV}"

if gcloud sql instances describe "$SHARED_INSTANCE_NAME" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
    echo "✅ Cloud SQL instance '$SHARED_INSTANCE_NAME' exists"
    
    # Check instance state
    INSTANCE_STATE=$(gcloud sql instances describe "$SHARED_INSTANCE_NAME" --project="$GCP_PROJECT_ID" --format="value(state)")
    if [[ "$INSTANCE_STATE" == "RUNNABLE" ]]; then
        echo "✅ Cloud SQL instance is running"
    else
        echo "❌ Cloud SQL instance state: $INSTANCE_STATE"
        exit 1
    fi
else
    echo "❌ Cloud SQL instance '$SHARED_INSTANCE_NAME' not found"
    exit 1
fi

# --- Check ProxySQL Connection Pool ---
echo "Checking ProxySQL deployment..."
PROXYSQL_SERVICE="proxysql-${DEPLOY_ENV}"

if gcloud run services describe "$PROXYSQL_SERVICE" --region="$GCP_REGION" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
    echo "✅ ProxySQL service exists"
    
    # Check service status
    SERVICE_URL=$(gcloud run services describe "$PROXYSQL_SERVICE" --region="$GCP_REGION" --project="$GCP_PROJECT_ID" --format="value(status.url)")
    if curl -f "$SERVICE_URL/health" >/dev/null 2>&1; then
        echo "✅ ProxySQL health endpoint responding"
    else
        echo "⚠️  ProxySQL health endpoint not responding (might be expected if service is private)"
    fi
else
    echo "❌ ProxySQL service not found"
    exit 1
fi

# --- Check Database Provisioning Function ---
echo "Checking database provisioning function..."
DB_FUNCTION_NAME="provision-database-${DEPLOY_ENV}"

if gcloud functions describe "$DB_FUNCTION_NAME" --region="$GCP_REGION" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
    echo "✅ Database provisioning function exists"
else
    echo "❌ Database provisioning function not found"
    exit 1
fi

# --- Check Monitoring Dashboard ---
echo "Checking monitoring dashboard..."
DASHBOARD_NAME="Database Architecture - $DEPLOY_ENV"

# Note: This is a basic check - in practice you'd check Cloud Monitoring API
echo "ℹ️  Monitoring dashboard check: Manual verification required"

echo "✅ Database architecture health checks completed successfully!"
