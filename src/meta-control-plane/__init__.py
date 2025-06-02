"""
AIPress Meta Control Plane

Central orchestrator for managing 50,000+ WordPress sites across
1,000+ GCP project shards.

This module implements the meta control plane architecture specified
in SCALING_TO_50K_SITES.md and ARCHITECTURE.md.

Key components:
- TenantRouter: Consistent hashing for tenant-to-shard routing
- ProjectManager: GCP project lifecycle management  
- HealthMonitor: Cross-shard health monitoring and metrics
- MetadataStorage: Global metadata with Cloud Spanner backend
"""

__version__ = "1.0.0"
__author__ = "AIPress Team"

from .models import (
    Tenant,
    Shard, 
    ProjectInfo,
    TenantCreateRequest,
    TenantRouteResponse,
    ShardStatus,
    HealthStatus,
    GlobalMetrics
)

from .routing import TenantRouter
from .project_manager import ProjectManager
from .health_monitor import HealthMonitor
from .storage import MetadataStorage, create_storage

__all__ = [
    # Core models
    "Tenant",
    "Shard",
    "ProjectInfo", 
    "TenantCreateRequest",
    "TenantRouteResponse",
    "ShardStatus",
    "HealthStatus",
    "GlobalMetrics",
    
    # Core services
    "TenantRouter",
    "ProjectManager", 
    "HealthMonitor",
    "MetadataStorage",
    "create_storage"
]
