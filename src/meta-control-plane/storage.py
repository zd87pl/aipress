"""
Metadata Storage Module for AIPress Meta Control Plane

Provides abstraction layer for storing tenant, shard, and project metadata.
Designed to be backed by Cloud Spanner for global consistency across regions.

Based on the global metadata requirements from SCALING_TO_50K_SITES.md
"""

import logging
import asyncio
from typing import Dict, List, Optional, Any
from datetime import datetime
from abc import ABC, abstractmethod

from .models import Tenant, Shard, ProjectInfo, AuditEvent


logger = logging.getLogger(__name__)


class MetadataStorage(ABC):
    """Abstract base class for metadata storage implementations"""
    
    @abstractmethod
    async def initialize(self):
        """Initialize the storage backend"""
        pass
    
    @abstractmethod
    async def close(self):
        """Close storage connections"""
        pass
    
    # Tenant operations
    @abstractmethod
    async def save_tenant(self, tenant: Tenant):
        """Save tenant metadata"""
        pass
    
    @abstractmethod
    async def get_tenant(self, tenant_id: str) -> Optional[Tenant]:
        """Get tenant by ID"""
        pass
    
    @abstractmethod
    async def get_all_tenants(self) -> List[Tenant]:
        """Get all tenants"""
        pass
    
    @abstractmethod
    async def delete_tenant(self, tenant_id: str):
        """Delete tenant metadata"""
        pass
    
    @abstractmethod
    async def get_tenants_by_shard(self, shard_id: str) -> List[Tenant]:
        """Get all tenants in a specific shard"""
        pass
    
    # Shard operations
    @abstractmethod
    async def save_shard(self, shard: Shard):
        """Save shard metadata"""
        pass
    
    @abstractmethod
    async def get_shard(self, shard_id: str) -> Optional[Shard]:
        """Get shard by ID"""
        pass
    
    @abstractmethod
    async def get_all_shards(self) -> List[Shard]:
        """Get all shards"""
        pass
    
    @abstractmethod
    async def delete_shard(self, shard_id: str):
        """Delete shard metadata"""
        pass
    
    # Project operations
    @abstractmethod
    async def save_project(self, project: ProjectInfo):
        """Save project metadata"""
        pass
    
    @abstractmethod
    async def get_project(self, project_id: str) -> Optional[ProjectInfo]:
        """Get project by ID"""
        pass
    
    @abstractmethod
    async def get_all_projects(self) -> List[ProjectInfo]:
        """Get all projects"""
        pass
    
    @abstractmethod
    async def delete_project(self, project_id: str):
        """Delete project metadata"""
        pass
    
    # Audit operations
    @abstractmethod
    async def save_audit_event(self, event: AuditEvent):
        """Save audit event"""
        pass
    
    @abstractmethod
    async def get_audit_events(self, limit: int = 100, offset: int = 0) -> List[AuditEvent]:
        """Get audit events with pagination"""
        pass


class InMemoryStorage(MetadataStorage):
    """
    In-memory implementation for development and testing.
    
    In production, this would be replaced with CloudSpannerStorage
    that provides global consistency across regions.
    """
    
    def __init__(self):
        self._tenants: Dict[str, Tenant] = {}
        self._shards: Dict[str, Shard] = {}
        self._projects: Dict[str, ProjectInfo] = {}
        self._audit_events: List[AuditEvent] = []
        self._initialized = False
        
        # Indexes for efficient queries
        self._tenants_by_shard: Dict[str, List[str]] = {}
    
    async def initialize(self):
        """Initialize in-memory storage"""
        if self._initialized:
            return
            
        logger.info("Initializing InMemoryStorage...")
        
        # Create some default shards for development
        default_shards = [
            Shard(
                shard_id=f"aipress-shard-{i:03d}",
                project_id=f"aipress-shard-{i:03d}",
                region="us-central1",
                control_plane_url=f"https://aipress-shard-{i:03d}-control-plane.run.app",
                created_at=datetime.utcnow()
            )
            for i in range(1, 6)  # Create first 5 shards for development
        ]
        
        for shard in default_shards:
            await self.save_shard(shard)
        
        self._initialized = True
        logger.info(f"Initialized InMemoryStorage with {len(default_shards)} default shards")
    
    async def close(self):
        """Close storage (no-op for in-memory)"""
        logger.info("Closing InMemoryStorage...")
    
    # Tenant operations
    async def save_tenant(self, tenant: Tenant):
        """Save tenant metadata"""
        self._tenants[tenant.tenant_id] = tenant
        
        # Update shard index
        shard_id = tenant.shard_id
        if shard_id not in self._tenants_by_shard:
            self._tenants_by_shard[shard_id] = []
        
        if tenant.tenant_id not in self._tenants_by_shard[shard_id]:
            self._tenants_by_shard[shard_id].append(tenant.tenant_id)
    
    async def get_tenant(self, tenant_id: str) -> Optional[Tenant]:
        """Get tenant by ID"""
        return self._tenants.get(tenant_id)
    
    async def get_all_tenants(self) -> List[Tenant]:
        """Get all tenants"""
        return list(self._tenants.values())
    
    async def delete_tenant(self, tenant_id: str):
        """Delete tenant metadata"""
        if tenant_id in self._tenants:
            tenant = self._tenants[tenant_id]
            shard_id = tenant.shard_id
            
            # Remove from main storage
            del self._tenants[tenant_id]
            
            # Update shard index
            if shard_id in self._tenants_by_shard:
                if tenant_id in self._tenants_by_shard[shard_id]:
                    self._tenants_by_shard[shard_id].remove(tenant_id)
    
    async def get_tenants_by_shard(self, shard_id: str) -> List[Tenant]:
        """Get all tenants in a specific shard"""
        tenant_ids = self._tenants_by_shard.get(shard_id, [])
        return [self._tenants[tid] for tid in tenant_ids if tid in self._tenants]
    
    # Shard operations
    async def save_shard(self, shard: Shard):
        """Save shard metadata"""
        self._shards[shard.shard_id] = shard
    
    async def get_shard(self, shard_id: str) -> Optional[Shard]:
        """Get shard by ID"""
        return self._shards.get(shard_id)
    
    async def get_all_shards(self) -> List[Shard]:
        """Get all shards"""
        return list(self._shards.values())
    
    async def delete_shard(self, shard_id: str):
        """Delete shard metadata"""
        if shard_id in self._shards:
            del self._shards[shard_id]
        
        # Clean up tenant index
        if shard_id in self._tenants_by_shard:
            del self._tenants_by_shard[shard_id]
    
    # Project operations
    async def save_project(self, project: ProjectInfo):
        """Save project metadata"""
        self._projects[project.project_id] = project
    
    async def get_project(self, project_id: str) -> Optional[ProjectInfo]:
        """Get project by ID"""
        return self._projects.get(project_id)
    
    async def get_all_projects(self) -> List[ProjectInfo]:
        """Get all projects"""
        return list(self._projects.values())
    
    async def delete_project(self, project_id: str):
        """Delete project metadata"""
        if project_id in self._projects:
            del self._projects[project_id]
    
    # Audit operations
    async def save_audit_event(self, event: AuditEvent):
        """Save audit event"""
        self._audit_events.append(event)
        
        # Keep only last 10000 events in memory
        if len(self._audit_events) > 10000:
            self._audit_events = self._audit_events[-10000:]
    
    async def get_audit_events(self, limit: int = 100, offset: int = 0) -> List[AuditEvent]:
        """Get audit events with pagination"""
        # Sort by timestamp descending (most recent first)
        sorted_events = sorted(self._audit_events, key=lambda x: x.timestamp, reverse=True)
        return sorted_events[offset:offset + limit]
    
    # Statistics and debugging
    async def get_storage_stats(self) -> Dict[str, Any]:
        """Get storage statistics for debugging"""
        return {
            "tenants": len(self._tenants),
            "shards": len(self._shards),
            "projects": len(self._projects),
            "audit_events": len(self._audit_events),
            "tenants_by_shard": {
                shard_id: len(tenant_ids) 
                for shard_id, tenant_ids in self._tenants_by_shard.items()
            }
        }


class CloudSpannerStorage(MetadataStorage):
    """
    Cloud Spanner implementation for production use.
    
    Provides global consistency and automatic multi-region replication
    as specified in the SCALING_TO_50K_SITES.md architecture.
    
    NOTE: This is a placeholder implementation. In a real production system,
    this would use the google-cloud-spanner library and implement
    proper schema management, connection pooling, and error handling.
    """
    
    def __init__(self, instance_id: str, database_id: str):
        self.instance_id = instance_id
        self.database_id = database_id
        self._client = None
        self._database = None
    
    async def initialize(self):
        """Initialize Cloud Spanner connection"""
        logger.info(f"Initializing CloudSpannerStorage: {self.instance_id}/{self.database_id}")
        
        # In a real implementation:
        # from google.cloud import spanner
        # self._client = spanner.Client()
        # self._instance = self._client.instance(self.instance_id)
        # self._database = self._instance.database(self.database_id)
        
        # For now, fall back to in-memory for development
        logger.warning("CloudSpannerStorage not fully implemented, using InMemoryStorage")
        self._fallback = InMemoryStorage()
        await self._fallback.initialize()
    
    async def close(self):
        """Close Spanner connections"""
        if hasattr(self, '_fallback'):
            await self._fallback.close()
    
    # All methods would delegate to fallback for now
    async def save_tenant(self, tenant: Tenant):
        return await self._fallback.save_tenant(tenant)
    
    async def get_tenant(self, tenant_id: str) -> Optional[Tenant]:
        return await self._fallback.get_tenant(tenant_id)
    
    async def get_all_tenants(self) -> List[Tenant]:
        return await self._fallback.get_all_tenants()
    
    async def delete_tenant(self, tenant_id: str):
        return await self._fallback.delete_tenant(tenant_id)
    
    async def get_tenants_by_shard(self, shard_id: str) -> List[Tenant]:
        return await self._fallback.get_tenants_by_shard(shard_id)
    
    async def save_shard(self, shard: Shard):
        return await self._fallback.save_shard(shard)
    
    async def get_shard(self, shard_id: str) -> Optional[Shard]:
        return await self._fallback.get_shard(shard_id)
    
    async def get_all_shards(self) -> List[Shard]:
        return await self._fallback.get_all_shards()
    
    async def delete_shard(self, shard_id: str):
        return await self._fallback.delete_shard(shard_id)
    
    async def save_project(self, project: ProjectInfo):
        return await self._fallback.save_project(project)
    
    async def get_project(self, project_id: str) -> Optional[ProjectInfo]:
        return await self._fallback.get_project(project_id)
    
    async def get_all_projects(self) -> List[ProjectInfo]:
        return await self._fallback.get_all_projects()
    
    async def delete_project(self, project_id: str):
        return await self._fallback.delete_project(project_id)
    
    async def save_audit_event(self, event: AuditEvent):
        return await self._fallback.save_audit_event(event)
    
    async def get_audit_events(self, limit: int = 100, offset: int = 0) -> List[AuditEvent]:
        return await self._fallback.get_audit_events(limit, offset)


def create_storage(storage_type: str = "memory", **kwargs) -> MetadataStorage:
    """
    Factory function to create appropriate storage implementation.
    
    Args:
        storage_type: "memory" for development, "spanner" for production
        **kwargs: Additional arguments for storage implementation
    
    Returns:
        MetadataStorage implementation
    """
    if storage_type == "memory":
        return InMemoryStorage()
    elif storage_type == "spanner":
        return CloudSpannerStorage(
            instance_id=kwargs.get("instance_id", "aipress-metadata"),
            database_id=kwargs.get("database_id", "aipress-db")
        )
    else:
        raise ValueError(f"Unknown storage type: {storage_type}")


# Default storage instance for convenience
# In production, this would be configured via environment variables
MetadataStorage = InMemoryStorage
