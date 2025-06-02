"""
Data models for the AIPress Meta Control Plane

Defines all the data structures used for tenant routing, project management,
and health monitoring across the multi-project federation architecture.
"""

from datetime import datetime
from typing import Dict, List, Optional, Any
from enum import Enum
from pydantic import BaseModel, Field


class ShardHealth(str, Enum):
    """Health status for shards"""
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"
    UNKNOWN = "unknown"


class ProjectStatus(str, Enum):
    """GCP project status"""
    ACTIVE = "active"
    CREATING = "creating"
    DELETING = "deleting"
    SUSPENDED = "suspended"
    ERROR = "error"


# Core entity models
class Tenant(BaseModel):
    """Tenant model"""
    tenant_id: str
    shard_id: str
    project_id: str
    created_at: datetime
    last_seen: Optional[datetime] = None
    metadata: Dict[str, Any] = {}


class Shard(BaseModel):
    """Shard model representing a project managing 50 sites"""
    shard_id: str
    project_id: str
    region: str
    control_plane_url: str
    tenant_count: int = 0
    max_tenants: int = 50
    health: ShardHealth = ShardHealth.UNKNOWN
    last_health_check: Optional[datetime] = None
    created_at: datetime
    metadata: Dict[str, Any] = {}


class ProjectInfo(BaseModel):
    """GCP Project information"""
    project_id: str
    project_name: str
    shard_id: Optional[str] = None
    status: ProjectStatus
    region: str
    billing_account: str
    organization_id: str
    created_at: datetime
    resource_usage: Dict[str, Any] = {}
    cost_data: Dict[str, Any] = {}


# Request/Response models
class TenantCreateRequest(BaseModel):
    """Request to create a new tenant"""
    tenant_id: str = Field(..., description="Unique tenant identifier")
    requirements: Optional[Dict[str, Any]] = Field(default={}, description="Tenant-specific requirements")
    metadata: Optional[Dict[str, Any]] = Field(default={}, description="Additional tenant metadata")


class TenantRouteResponse(BaseModel):
    """Response with tenant routing information"""
    tenant_id: str
    shard_id: str
    project_id: str
    control_plane_url: str
    region: str


class ShardStatus(BaseModel):
    """Detailed shard status information"""
    shard_id: str
    project_id: str
    region: str
    health: ShardHealth
    tenant_count: int
    max_tenants: int
    utilization_percent: float
    control_plane_url: str
    control_plane_healthy: bool
    database_healthy: bool
    storage_healthy: bool
    last_health_check: datetime
    response_time_ms: Optional[float] = None
    error_rate_percent: Optional[float] = None
    resource_usage: Dict[str, Any] = {}


class HealthStatus(BaseModel):
    """Meta Control Plane health status"""
    status: str
    timestamp: datetime
    meta_control_plane: bool = True
    active_shards: int
    total_tenants: int
    healthy_shards: int = 0
    degraded_shards: int = 0
    unhealthy_shards: int = 0


class GlobalMetrics(BaseModel):
    """Global platform metrics"""
    timestamp: datetime
    total_projects: int
    total_shards: int
    total_tenants: int
    active_tenants: int
    
    # Performance metrics
    avg_response_time_ms: float
    p99_response_time_ms: float
    global_error_rate_percent: float
    
    # Capacity metrics
    total_capacity: int  # Max tenants across all shards
    used_capacity: int   # Current tenants
    utilization_percent: float
    
    # Health metrics
    healthy_shards: int
    degraded_shards: int
    unhealthy_shards: int
    
    # Cost metrics
    estimated_monthly_cost: float
    cost_per_tenant: float
    
    # Regional distribution
    regional_distribution: Dict[str, int] = {}


class ShardResourceUsage(BaseModel):
    """Resource usage for a shard"""
    shard_id: str
    cpu_utilization_percent: float
    memory_utilization_percent: float
    storage_used_gb: float
    storage_available_gb: float
    network_ingress_gb: float
    network_egress_gb: float
    database_connections: int
    database_max_connections: int
    timestamp: datetime


class CapacityReport(BaseModel):
    """Capacity planning report"""
    timestamp: datetime
    current_shards: int
    projected_shards_needed: int
    current_utilization_percent: float
    projected_growth_rate: float
    
    # Recommendations
    should_create_new_shards: bool
    recommended_new_shards: int
    estimated_months_to_capacity: Optional[float] = None
    
    # Per-region capacity
    regional_capacity: Dict[str, Dict[str, Any]] = {}
    
    # Cost projections
    current_monthly_cost: float
    projected_monthly_cost: float


class TenantMigrationRequest(BaseModel):
    """Request to migrate a tenant between shards"""
    tenant_id: str
    source_shard_id: str
    target_shard_id: str
    reason: str
    scheduled_time: Optional[datetime] = None
    dry_run: bool = False


class LoadBalancingConfig(BaseModel):
    """Load balancing configuration"""
    algorithm: str = "consistent_hashing"
    max_tenants_per_shard: int = 50
    rebalance_threshold_percent: float = 80.0
    preferred_regions: List[str] = []
    avoid_cross_region_placement: bool = True


class AlertConfig(BaseModel):
    """Alerting configuration"""
    error_rate_threshold_percent: float = 5.0
    response_time_threshold_ms: float = 1000.0
    utilization_threshold_percent: float = 80.0
    health_check_interval_seconds: int = 300
    alert_cooldown_minutes: int = 15


class ShardCreateRequest(BaseModel):
    """Request to create a new shard"""
    region: str = Field(..., description="GCP region for the shard")
    initial_capacity: int = Field(default=50, description="Initial tenant capacity")
    metadata: Optional[Dict[str, Any]] = Field(default={}, description="Shard metadata")


class RoutingDebugInfo(BaseModel):
    """Debug information for routing decisions"""
    tenant_id: str
    tenant_hash: str
    shard_id: str
    algorithm: str
    num_shards: int
    shard_selection_reason: str
    alternative_shards: List[str] = []


# Event models for audit logging
class EventType(str, Enum):
    """Types of events to log"""
    TENANT_CREATED = "tenant_created"
    TENANT_DELETED = "tenant_deleted"
    TENANT_MIGRATED = "tenant_migrated"
    SHARD_CREATED = "shard_created"
    SHARD_DELETED = "shard_deleted"
    HEALTH_CHECK_FAILED = "health_check_failed"
    CAPACITY_WARNING = "capacity_warning"
    REBALANCING_TRIGGERED = "rebalancing_triggered"


class AuditEvent(BaseModel):
    """Audit event for logging"""
    event_id: str
    event_type: EventType
    timestamp: datetime
    user_id: Optional[str] = None
    tenant_id: Optional[str] = None
    shard_id: Optional[str] = None
    project_id: Optional[str] = None
    details: Dict[str, Any] = {}
    success: bool = True
    error_message: Optional[str] = None
