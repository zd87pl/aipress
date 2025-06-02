"""
Tenant Routing Module for AIPress Meta Control Plane

Implements consistent hashing for tenant-to-shard routing, load balancing,
and tenant management across 1,000+ project shards.

Based on the routing algorithm specified in SCALING_TO_50K_SITES.md
"""

import hashlib
import logging
import asyncio
from typing import Dict, List, Optional, Set
from datetime import datetime
from collections import defaultdict

from .models import Tenant, LoadBalancingConfig
from .storage import MetadataStorage


logger = logging.getLogger(__name__)


class TenantRouter:
    """
    Manages tenant-to-shard routing using consistent hashing.
    
    Key responsibilities:
    - Route tenants to shards using consistent hashing
    - Load balancing across available shards
    - Tenant migration and rebalancing
    - Capacity management
    """
    
    def __init__(self, num_shards: int = 1000, storage: Optional[MetadataStorage] = None):
        self.num_shards = num_shards
        self.storage = storage or MetadataStorage()
        
        # In-memory caches for performance
        self._tenant_to_shard_cache: Dict[str, str] = {}
        self._shard_tenant_counts: Dict[str, int] = defaultdict(int)
        self._available_shards: Set[str] = set()
        
        # Configuration
        self.config = LoadBalancingConfig()
        
        # Statistics
        self._routing_stats = {
            "total_routes": 0,
            "cache_hits": 0,
            "cache_misses": 0,
            "rebalance_operations": 0
        }
    
    async def initialize(self):
        """Initialize the router with existing tenant data"""
        logger.info("Initializing TenantRouter...")
        
        # Load existing tenant mappings
        tenants = await self.storage.get_all_tenants()
        for tenant in tenants:
            self._tenant_to_shard_cache[tenant.tenant_id] = tenant.shard_id
            self._shard_tenant_counts[tenant.shard_id] += 1
        
        # Load available shards
        shards = await self.storage.get_all_shards()
        self._available_shards = {shard.shard_id for shard in shards}
        
        logger.info(f"Initialized router with {len(tenants)} tenants across {len(shards)} shards")
    
    def get_shard_for_tenant(self, tenant_id: str) -> str:
        """
        Get the shard ID for a tenant using consistent hashing.
        
        Implementation of the algorithm from ARCHITECTURE.md:
        ```python
        def get_shard_for_tenant(tenant_id: str) -> str:
            tenant_hash = hashlib.sha256(tenant_id.encode()).hexdigest()
            shard_number = int(tenant_hash[:8], 16) % NUM_SHARDS + 1
            return f"aipress-shard-{shard_number:03d}"
        ```
        """
        self._routing_stats["total_routes"] += 1
        
        # Check cache first
        if tenant_id in self._tenant_to_shard_cache:
            self._routing_stats["cache_hits"] += 1
            return self._tenant_to_shard_cache[tenant_id]
        
        self._routing_stats["cache_misses"] += 1
        
        # Calculate shard using consistent hashing
        shard_id = self._calculate_shard_id(tenant_id)
        
        # Cache the result
        self._tenant_to_shard_cache[tenant_id] = shard_id
        
        return shard_id
    
    def _calculate_shard_id(self, tenant_id: str) -> str:
        """Calculate shard ID using consistent hashing algorithm"""
        tenant_hash = hashlib.sha256(tenant_id.encode()).hexdigest()
        shard_number = int(tenant_hash[:8], 16) % self.num_shards + 1
        return f"aipress-shard-{shard_number:03d}"
    
    def _get_tenant_hash(self, tenant_id: str) -> str:
        """Get the hash value for a tenant (for debugging)"""
        return hashlib.sha256(tenant_id.encode()).hexdigest()
    
    async def register_tenant(self, tenant_id: str, shard_id: str):
        """Register a tenant in the specified shard"""
        # Update cache
        self._tenant_to_shard_cache[tenant_id] = shard_id
        self._shard_tenant_counts[shard_id] += 1
        
        # Persist to storage
        tenant = Tenant(
            tenant_id=tenant_id,
            shard_id=shard_id,
            project_id=await self._get_project_id_for_shard(shard_id),
            created_at=datetime.utcnow()
        )
        await self.storage.save_tenant(tenant)
        
        logger.info(f"Registered tenant {tenant_id} in shard {shard_id}")
    
    async def unregister_tenant(self, tenant_id: str):
        """Remove a tenant from routing"""
        if tenant_id in self._tenant_to_shard_cache:
            shard_id = self._tenant_to_shard_cache[tenant_id]
            
            # Update cache
            del self._tenant_to_shard_cache[tenant_id]
            self._shard_tenant_counts[shard_id] = max(0, self._shard_tenant_counts[shard_id] - 1)
            
            # Remove from storage
            await self.storage.delete_tenant(tenant_id)
            
            logger.info(f"Unregistered tenant {tenant_id} from shard {shard_id}")
    
    async def get_optimal_shard(self) -> str:
        """
        Find the optimal shard for a new tenant based on load balancing.
        
        Strategy:
        1. Use consistent hashing as the primary placement
        2. Check if the target shard has capacity
        3. If not, find the least loaded shard in the same region
        4. Fall back to global least loaded shard
        """
        # Get all available shards sorted by utilization
        shard_utilizations = []
        
        for shard_id in self._available_shards:
            tenant_count = self._shard_tenant_counts.get(shard_id, 0)
            utilization = tenant_count / self.config.max_tenants_per_shard
            shard_utilizations.append((shard_id, utilization, tenant_count))
        
        # Sort by utilization (ascending)
        shard_utilizations.sort(key=lambda x: x[1])
        
        # Find first shard with available capacity
        for shard_id, utilization, tenant_count in shard_utilizations:
            if tenant_count < self.config.max_tenants_per_shard:
                logger.info(f"Selected optimal shard {shard_id} (utilization: {utilization:.1%})")
                return shard_id
        
        # If no shard has capacity, we need to create a new one
        raise Exception("No available capacity in existing shards - new shard creation required")
    
    async def find_available_shard(self) -> str:
        """Find any shard with available capacity"""
        for shard_id in self._available_shards:
            tenant_count = self._shard_tenant_counts.get(shard_id, 0)
            if tenant_count < self.config.max_tenants_per_shard:
                return shard_id
        
        # No capacity available - need to create new shard
        new_shard_id = f"aipress-shard-{len(self._available_shards) + 1:03d}"
        logger.info(f"No available capacity found - suggesting new shard: {new_shard_id}")
        return new_shard_id
    
    async def get_shard_tenant_count(self, shard_id: str) -> int:
        """Get the current tenant count for a shard"""
        return self._shard_tenant_counts.get(shard_id, 0)
    
    async def get_total_tenant_count(self) -> int:
        """Get the total number of registered tenants"""
        return len(self._tenant_to_shard_cache)
    
    async def get_shard_utilization(self, shard_id: str) -> float:
        """Get utilization percentage for a shard"""
        tenant_count = await self.get_shard_tenant_count(shard_id)
        return tenant_count / self.config.max_tenants_per_shard
    
    async def add_available_shard(self, shard_id: str):
        """Add a new shard to the available pool"""
        self._available_shards.add(shard_id)
        if shard_id not in self._shard_tenant_counts:
            self._shard_tenant_counts[shard_id] = 0
        logger.info(f"Added shard {shard_id} to available pool")
    
    async def remove_shard(self, shard_id: str):
        """Remove a shard from the available pool (for maintenance/deletion)"""
        if shard_id in self._available_shards:
            self._available_shards.remove(shard_id)
            logger.info(f"Removed shard {shard_id} from available pool")
    
    async def migrate_tenant(self, tenant_id: str, target_shard_id: str) -> bool:
        """
        Migrate a tenant from one shard to another.
        This is primarily for load balancing and maintenance operations.
        """
        if tenant_id not in self._tenant_to_shard_cache:
            logger.error(f"Cannot migrate unknown tenant {tenant_id}")
            return False
        
        source_shard_id = self._tenant_to_shard_cache[tenant_id]
        
        if source_shard_id == target_shard_id:
            logger.info(f"Tenant {tenant_id} already in target shard {target_shard_id}")
            return True
        
        # Check target shard capacity
        target_count = self._shard_tenant_counts.get(target_shard_id, 0)
        if target_count >= self.config.max_tenants_per_shard:
            logger.error(f"Target shard {target_shard_id} at capacity")
            return False
        
        # Update routing
        self._tenant_to_shard_cache[tenant_id] = target_shard_id
        self._shard_tenant_counts[source_shard_id] -= 1
        self._shard_tenant_counts[target_shard_id] += 1
        
        # Update persistent storage
        tenant = await self.storage.get_tenant(tenant_id)
        if tenant:
            tenant.shard_id = target_shard_id
            tenant.project_id = await self._get_project_id_for_shard(target_shard_id)
            await self.storage.save_tenant(tenant)
        
        logger.info(f"Migrated tenant {tenant_id} from {source_shard_id} to {target_shard_id}")
        return True
    
    async def rebalance_tenants(self) -> Dict[str, any]:
        """
        Perform tenant rebalancing across shards to optimize load distribution.
        
        Returns summary of rebalancing operations performed.
        """
        logger.info("Starting tenant rebalancing...")
        self._routing_stats["rebalance_operations"] += 1
        
        # Calculate current utilization across shards
        shard_stats = []
        total_tenants = 0
        
        for shard_id in self._available_shards:
            tenant_count = self._shard_tenant_counts.get(shard_id, 0)
            utilization = tenant_count / self.config.max_tenants_per_shard
            shard_stats.append({
                "shard_id": shard_id,
                "tenant_count": tenant_count,
                "utilization": utilization,
                "over_threshold": utilization > (self.config.rebalance_threshold_percent / 100)
            })
            total_tenants += tenant_count
        
        # Sort by utilization
        shard_stats.sort(key=lambda x: x["utilization"], reverse=True)
        
        # Identify shards that need rebalancing
        overloaded_shards = [s for s in shard_stats if s["over_threshold"]]
        underloaded_shards = [s for s in shard_stats if not s["over_threshold"]]
        
        migrations_performed = []
        
        # Perform migrations from overloaded to underloaded shards
        for overloaded in overloaded_shards:
            if not underloaded_shards:
                break
                
            source_shard = overloaded["shard_id"]
            
            # Find tenants in this shard that could be moved
            tenants_in_shard = [
                tenant_id for tenant_id, shard_id in self._tenant_to_shard_cache.items()
                if shard_id == source_shard
            ]
            
            # Try to move some tenants to underloaded shards
            for tenant_id in tenants_in_shard[:5]:  # Limit to 5 migrations per round
                if not underloaded_shards:
                    break
                    
                target_shard = underloaded_shards[0]["shard_id"]
                
                if await self.migrate_tenant(tenant_id, target_shard):
                    migrations_performed.append({
                        "tenant_id": tenant_id,
                        "from": source_shard,
                        "to": target_shard
                    })
                    
                    # Update underloaded shard stats
                    underloaded_shards[0]["tenant_count"] += 1
                    underloaded_shards[0]["utilization"] = (
                        underloaded_shards[0]["tenant_count"] / self.config.max_tenants_per_shard
                    )
                    
                    # Remove from underloaded if it's now at threshold
                    if underloaded_shards[0]["utilization"] > (self.config.rebalance_threshold_percent / 100):
                        underloaded_shards.pop(0)
        
        result = {
            "timestamp": datetime.utcnow(),
            "migrations_performed": len(migrations_performed),
            "migrations": migrations_performed,
            "total_tenants": total_tenants,
            "total_shards": len(self._available_shards),
            "average_utilization": total_tenants / (len(self._available_shards) * self.config.max_tenants_per_shard),
            "overloaded_shards": len(overloaded_shards),
            "underloaded_shards": len(underloaded_shards)
        }
        
        logger.info(f"Rebalancing completed: {len(migrations_performed)} migrations performed")
        return result
    
    async def get_routing_statistics(self) -> Dict[str, any]:
        """Get routing performance statistics"""
        cache_hit_rate = (
            self._routing_stats["cache_hits"] / max(1, self._routing_stats["total_routes"])
        ) * 100
        
        return {
            **self._routing_stats,
            "cache_hit_rate_percent": cache_hit_rate,
            "total_tenants": len(self._tenant_to_shard_cache),
            "total_shards": len(self._available_shards),
            "average_tenants_per_shard": len(self._tenant_to_shard_cache) / max(1, len(self._available_shards))
        }
    
    async def _get_project_id_for_shard(self, shard_id: str) -> str:
        """Get the GCP project ID for a shard"""
        # This would normally query the project manager
        # For now, derive from shard ID
        shard_number = shard_id.split('-')[-1]
        return f"aipress-shard-{shard_number}"
    
    async def validate_routing_consistency(self) -> Dict[str, any]:
        """
        Validate that routing is consistent and identify any issues.
        Used for debugging and operational monitoring.
        """
        issues = []
        
        # Check for tenants in non-existent shards
        for tenant_id, shard_id in self._tenant_to_shard_cache.items():
            if shard_id not in self._available_shards:
                issues.append(f"Tenant {tenant_id} routed to non-existent shard {shard_id}")
        
        # Check for routing inconsistencies (tenant in wrong shard per hash)
        routing_mismatches = 0
        for tenant_id, actual_shard in self._tenant_to_shard_cache.items():
            expected_shard = self._calculate_shard_id(tenant_id)
            if actual_shard != expected_shard:
                routing_mismatches += 1
                # Note: This might be intentional due to migrations
        
        # Check shard capacity violations
        overloaded_shards = []
        for shard_id, tenant_count in self._shard_tenant_counts.items():
            if tenant_count > self.config.max_tenants_per_shard:
                overloaded_shards.append({
                    "shard_id": shard_id,
                    "tenant_count": tenant_count,
                    "max_capacity": self.config.max_tenants_per_shard
                })
        
        return {
            "timestamp": datetime.utcnow(),
            "total_issues": len(issues),
            "issues": issues,
            "routing_mismatches": routing_mismatches,
            "overloaded_shards": overloaded_shards,
            "total_tenants": len(self._tenant_to_shard_cache),
            "total_shards": len(self._available_shards)
        }
