# AIPress Migration Plan: PoC to Production Architecture

## Executive Summary

This document outlines the step-by-step migration strategy from the current single-project PoC to a production-ready multi-project federation architecture capable of scaling to 50,000+ WordPress sites.

## Current State Assessment

### Existing Architecture (PoC)
```
Single GCP Project: aipress-project
├── Control Plane (Cloud Run)
├── WordPress Sites (Cloud Run, ~10 sites max tested)
├── Databases (Cloud SQL, 1 instance per tenant)
├── Storage (GCS, 1 bucket per tenant)
└── Networking (Basic Cloud Run routing)
```

### Target Architecture (Production)
```
Organization: aipress-hosting
├── Meta Control Plane Project
├── Shared Services Project  
├── 1,000 Shard Projects
│   ├── 50 WordPress Sites each
│   ├── 1 Shared Cloud SQL instance
│   └── Shared GCS bucket
└── Global Services
    ├── Cloud Spanner (metadata)
    ├── BigQuery (analytics)
    └── Cloud CDN (global)
```

## Migration Strategy

### Phase 0: Foundation Migration (Weeks 1-8)

#### Week 1-2: Assessment & Planning
**Goals**: Understand current state and plan migration
- [ ] **Inventory Current Resources**
  - Document all existing tenants and their configurations
  - Map current Terraform state files
  - Document custom configurations and secrets
  - Assess data volumes and traffic patterns

- [ ] **Architecture Design**
  - Finalize project hierarchy design
  - Define naming conventions for all resources
  - Plan network topology
  - Design service discovery mechanism

- [ ] **Risk Assessment**
  - Identify potential breaking changes
  - Plan rollback procedures
  - Define testing strategy
  - Create communication plan

#### Week 3-4: Infrastructure Preparation
**Goals**: Set up new infrastructure foundation
- [ ] **GCP Organization Setup**
  - Create `aipress-hosting` organization
  - Set up billing account hierarchy
  - Configure organization policies
  - Set up quota management

- [ ] **Core Projects Creation**
  ```bash
  # Meta Control Plane Project
  gcloud projects create aipress-control-meta --organization=ORGANIZATION_ID
  
  # Shared Services Project  
  gcloud projects create aipress-shared-services --organization=ORGANIZATION_ID
  
  # First Shard Project (pilot)
  gcloud projects create aipress-shard-001 --organization=ORGANIZATION_ID
  ```

- [ ] **Network Foundation**
  - Set up VPC networks in each project
  - Configure VPC peering between projects
  - Set up DNS zones
  - Configure firewall rules

#### Week 5-6: Meta Control Plane Development
**Goals**: Build the orchestration layer
- [ ] **Meta Control Plane Service**
  ```python
  # New FastAPI service structure
  src/meta-control-plane/
  ├── main.py              # FastAPI app with routing logic
  ├── models.py            # Tenant and shard data models
  ├── routing.py           # Consistent hashing implementation
  ├── project_manager.py   # GCP project management
  └── requirements.txt
  ```

- [ ] **Tenant Routing Logic**
  ```python
  def get_shard_for_tenant(tenant_id: str) -> str:
      """Implement consistent hashing"""
      tenant_hash = hashlib.sha256(tenant_id.encode()).hexdigest()
      shard_number = int(tenant_hash[:8], 16) % NUM_SHARDS + 1
      return f"aipress-shard-{shard_number:03d}"
  ```

- [ ] **Project Management APIs**
  - `/projects` - List and manage GCP projects
  - `/shards/{shard_id}` - Shard-specific operations
  - `/tenants/{tenant_id}/route` - Get routing information
  - `/health` - Cross-project health checks

#### Week 7-8: Database Architecture Migration
**Goals**: Move to shared database model
- [ ] **Shared Database Implementation**
  - Deploy shared Cloud SQL instance in first shard
  - Implement ProxySQL for connection pooling
  - Create database provisioning automation
  - Set up monitoring and alerting

- [ ] **Migration Tools**
  ```python
  # Database migration utility
  src/migration-tools/
  ├── db_migrator.py       # Main migration logic
  ├── data_validator.py    # Ensure data integrity
  ├── rollback.py          # Rollback procedures
  └── monitoring.py        # Migration monitoring
  ```

### Phase 1: Pilot Migration (Weeks 9-12)

#### Week 9-10: Pilot Tenant Migration
**Goals**: Migrate first 10 tenants to validate approach

- [ ] **Select Pilot Tenants**
  - Choose low-traffic, non-critical tenants
  - Document their current configurations
  - Get stakeholder approval
  - Set up monitoring for migration

- [ ] **Migration Execution**
  ```bash
  # Step-by-step migration process
  
  # 1. Create backup of current tenant
  ./scripts/backup_tenant.sh tenant-001
  
  # 2. Provision new infrastructure in shard
  ./scripts/provision_tenant_in_shard.sh tenant-001 shard-001
  
  # 3. Migrate database
  ./scripts/migrate_database.sh tenant-001 old-project shard-001
  
  # 4. Migrate files
  ./scripts/migrate_files.sh tenant-001 old-bucket new-bucket
  
  # 5. Update DNS routing
  ./scripts/update_routing.sh tenant-001 new-cloud-run-url
  
  # 6. Validate migration
  ./scripts/validate_migration.sh tenant-001
  ```

- [ ] **Validation & Testing**
  - Functional testing of migrated sites
  - Performance comparison
  - Data integrity verification
  - Rollback testing

#### Week 11-12: Optimization & Documentation
**Goals**: Refine process and document learnings

- [ ] **Process Optimization**
  - Automate manual steps
  - Improve error handling
  - Optimize migration speed
  - Enhance monitoring

- [ ] **Documentation Updates**
  - Migration runbooks
  - Troubleshooting guides
  - Architecture documentation
  - API documentation

### Phase 2: Full Migration (Weeks 13-20)

#### Week 13-16: Batch Migration
**Goals**: Migrate all existing tenants

- [ ] **Automated Migration Pipeline**
  ```yaml
  # Cloud Build pipeline for migrations
  steps:
    - name: 'gcr.io/${PROJECT_ID}/tenant-migrator'
      args: 
        - 'migrate-batch'
        - '--source-project=${OLD_PROJECT}'
        - '--target-shard=${TARGET_SHARD}'
        - '--tenant-list=${TENANT_LIST}'
        - '--dry-run=false'
  ```

- [ ] **Migration Batches**
  - Batch 1: Development/staging tenants (10 tenants)
  - Batch 2: Low-traffic production tenants (20 tenants)
  - Batch 3: Medium-traffic production tenants (50 tenants)
  - Batch 4: High-traffic production tenants (remaining)

- [ ] **Monitoring & Rollback**
  - Real-time migration monitoring
  - Automated rollback triggers
  - Performance impact assessment
  - Customer communication

#### Week 17-20: Legacy Cleanup
**Goals**: Clean up old infrastructure

- [ ] **Gradual Decommissioning**
  - Verify all tenants migrated successfully
  - Run parallel systems for 1 week
  - Gradually reduce old infrastructure
  - Archive old Terraform states

- [ ] **Final Validation**
  - End-to-end testing of new architecture
  - Performance benchmarking
  - Cost analysis comparison
  - Security audit

## Migration Tools & Scripts

### 1. Tenant Backup Script
```bash
#!/bin/bash
# backup_tenant.sh - Complete tenant backup

TENANT_ID=$1
BACKUP_LOCATION="gs://aipress-migration-backups/${TENANT_ID}"

# Backup database
gcloud sql export sql ${TENANT_ID}-db ${BACKUP_LOCATION}/database.sql

# Backup files
gsutil -m cp -r gs://${TENANT_ID}-media/* ${BACKUP_LOCATION}/files/

# Backup configuration
kubectl get configmap ${TENANT_ID}-config -o yaml > ${BACKUP_LOCATION}/config.yaml
```

### 2. Database Migration Script
```python
#!/usr/bin/env python3
# migrate_database.py - Database migration utility

import logging
from google.cloud import sql_v1
from google.cloud import secretmanager

class DatabaseMigrator:
    def __init__(self, source_project, target_project):
        self.source_project = source_project
        self.target_project = target_project
        
    def migrate_tenant_database(self, tenant_id):
        """Migrate tenant database to shared instance"""
        
        # 1. Export from source
        export_operation = self.export_database(tenant_id)
        
        # 2. Create database in shared instance
        self.create_tenant_database(tenant_id)
        
        # 3. Import to target
        import_operation = self.import_database(tenant_id)
        
        # 4. Validate data integrity
        self.validate_migration(tenant_id)
        
        return True
```

### 3. DNS Migration Script
```python
#!/usr/bin/env python3
# migrate_dns.py - DNS routing migration

from google.cloud import dns

class DNSMigrator:
    def __init__(self):
        self.dns_client = dns.Client()
        
    def update_tenant_routing(self, tenant_id, new_endpoint):
        """Update DNS to point to new Cloud Run service"""
        
        zone = self.dns_client.zone('aipress-zone')
        
        # Get current record
        old_record = zone.record(f"{tenant_id}.aipress.io", "A")
        
        # Create new record
        new_record = zone.record(f"{tenant_id}.aipress.io", "CNAME", [new_endpoint])
        
        # Atomic update
        changes = zone.changes()
        changes.delete_record_set(old_record)
        changes.add_record_set(new_record)
        changes.create()
```

## Risk Mitigation

### Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Data Loss | High | Complete backups before migration, parallel systems |
| Downtime | Medium | Blue/green deployment, DNS switching |
| Performance Issues | Medium | Load testing, gradual rollout |
| Migration Failures | High | Automated rollback, manual procedures |

### Business Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Customer Impact | High | Off-peak migrations, customer communication |
| Cost Overruns | Medium | Detailed cost monitoring, staged approach |
| Timeline Delays | Medium | Buffer time, parallel workstreams |

## Rollback Procedures

### Automatic Rollback Triggers
- Error rate > 5% during migration
- Response time increase > 50%
- Failed health checks > 3 consecutive
- Data integrity validation failures

### Manual Rollback Steps
```bash
# Emergency rollback procedure
./scripts/emergency_rollback.sh tenant-001

# Steps performed:
# 1. Switch DNS back to old infrastructure
# 2. Restore database from backup
# 3. Restore file storage
# 4. Validate old system functionality
# 5. Alert operations team
```

## Success Criteria

### Phase 0 (Foundation)
- [ ] Meta control plane deployed and functional
- [ ] First shard project operational
- [ ] Database migration tools tested
- [ ] Monitoring and alerting configured

### Phase 1 (Pilot)
- [ ] 10 pilot tenants migrated successfully
- [ ] Zero data loss
- [ ] <5 minutes downtime per tenant
- [ ] Performance maintained or improved

### Phase 2 (Full Migration)
- [ ] 100% of tenants migrated
- [ ] Old infrastructure decommissioned
- [ ] Cost reduction of 40%+ achieved
- [ ] New architecture validated at scale

## Communication Plan

### Stakeholders
- **Development Team**: Technical updates, blocker resolution
- **Operations Team**: Migration status, monitoring alerts
- **Customer Success**: Customer communications, support
- **Leadership**: Progress reports, risk assessment

### Communication Schedule
- **Daily**: Technical team standups during migration windows
- **Weekly**: Progress reports to stakeholders
- **Ad-hoc**: Emergency communications for issues

This migration plan provides a structured approach to transitioning from the current PoC to a production-ready architecture while minimizing risk and maintaining service quality.
