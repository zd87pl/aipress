"""
Health Monitor Module for AIPress Meta Control Plane

Monitors the health of all shards across the multi-project federation,
providing real-time health status, metrics collection, and alerting.

Based on health monitoring requirements from SCALING_TO_50K_SITES.md
"""

import logging
import asyncio
import aiohttp
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
from collections import defaultdict

from .models import (
    ShardHealth, ShardStatus, GlobalMetrics, CapacityReport,
    ShardResourceUsage, AlertConfig
)
from .storage import MetadataStorage


logger = logging.getLogger(__name__)


class HealthMonitor:
    """
    Monitors health across all shards in the federation.
    
    Key responsibilities:
    - Periodic health checks of all shards
    - Collect and aggregate performance metrics
    - Generate capacity planning reports
    - Trigger alerts for issues
    - Provide global platform visibility
    """
    
    def __init__(self, storage: Optional[MetadataStorage] = None):
        self.storage = storage or MetadataStorage()
        
        # Health monitoring state
        self._shard_health: Dict[str, ShardHealth] = {}
        self._last_health_check: Dict[str, datetime] = {}
        self._health_check_errors: Dict[str, int] = defaultdict(int)
        
        # Performance metrics storage
        self._metrics_history: Dict[str, List[ShardResourceUsage]] = defaultdict(list)
        self._global_metrics_history: List[GlobalMetrics] = []
        
        # Monitoring configuration
        self.config = AlertConfig()
        self._monitoring_active = False
        self._health_check_task = None
        
        # HTTP session for health checks
        self._http_session: Optional[aiohttp.ClientSession] = None
        
        # Statistics
        self._stats = {
            "total_health_checks": 0,
            "failed_health_checks": 0,
            "alerts_triggered": 0,
            "shards_monitored": 0
        }
    
    async def start_monitoring(self):
        """Start the health monitoring background task"""
        if self._monitoring_active:
            return
        
        logger.info("Starting health monitoring...")
        
        # Initialize HTTP session
        timeout = aiohttp.ClientTimeout(total=30)
        self._http_session = aiohttp.ClientSession(timeout=timeout)
        
        # Start background monitoring task
        self._monitoring_active = True
        self._health_check_task = asyncio.create_task(self._monitoring_loop())
        
        logger.info("Health monitoring started")
    
    async def stop_monitoring(self):
        """Stop the health monitoring background task"""
        if not self._monitoring_active:
            return
        
        logger.info("Stopping health monitoring...")
        
        self._monitoring_active = False
        
        if self._health_check_task:
            self._health_check_task.cancel()
            try:
                await self._health_check_task
            except asyncio.CancelledError:
                pass
        
        # Close HTTP session
        if self._http_session:
            await self._http_session.close()
            self._http_session = None
        
        logger.info("Health monitoring stopped")
    
    async def _monitoring_loop(self):
        """Main monitoring loop that runs periodically"""
        while self._monitoring_active:
            try:
                await self._perform_health_checks()
                await self._collect_metrics()
                await self._check_alerts()
                
                # Wait for next interval
                await asyncio.sleep(self.config.health_check_interval_seconds)
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in monitoring loop: {e}")
                await asyncio.sleep(30)  # Wait before retrying
    
    async def _perform_health_checks(self):
        """Perform health checks on all shards"""
        shards = await self.storage.get_all_shards()
        
        # Perform health checks concurrently
        health_check_tasks = [
            self.check_shard_health(shard.shard_id) 
            for shard in shards
        ]
        
        if health_check_tasks:
            await asyncio.gather(*health_check_tasks, return_exceptions=True)
        
        self._stats["shards_monitored"] = len(shards)
    
    async def check_shard_health(self, shard_id: str) -> Dict[str, Any]:
        """
        Perform comprehensive health check on a specific shard.
        
        Checks:
        - Control plane responsiveness
        - Database connectivity
        - Storage accessibility
        - Resource utilization
        """
        logger.debug(f"Checking health of shard {shard_id}")
        
        self._stats["total_health_checks"] += 1
        start_time = datetime.utcnow()
        
        try:
            shard = await self.storage.get_shard(shard_id)
            if not shard:
                logger.warning(f"Shard {shard_id} not found in storage")
                return {"error": "Shard not found"}
            
            # Check control plane health
            control_plane_healthy, response_time = await self._check_control_plane_health(shard.control_plane_url)
            
            # Check database health (would query actual database in production)
            database_healthy = await self._check_database_health(shard.project_id)
            
            # Check storage health (would query actual storage in production)
            storage_healthy = await self._check_storage_health(shard.project_id)
            
            # Determine overall health
            if control_plane_healthy and database_healthy and storage_healthy:
                health = ShardHealth.HEALTHY
            elif control_plane_healthy:
                health = ShardHealth.DEGRADED
            else:
                health = ShardHealth.UNHEALTHY
            
            # Update shard health
            self._shard_health[shard_id] = health
            self._last_health_check[shard_id] = datetime.utcnow()
            self._health_check_errors[shard_id] = 0  # Reset error count on success
            
            # Update shard in storage
            shard.health = health
            shard.last_health_check = self._last_health_check[shard_id]
            await self.storage.save_shard(shard)
            
            result = {
                "shard_id": shard_id,
                "health": health.value,
                "control_plane_healthy": control_plane_healthy,
                "database_healthy": database_healthy,
                "storage_healthy": storage_healthy,
                "response_time_ms": response_time,
                "timestamp": start_time
            }
            
            logger.debug(f"Health check completed for {shard_id}: {health.value}")
            return result
            
        except Exception as e:
            logger.error(f"Health check failed for shard {shard_id}: {e}")
            
            self._stats["failed_health_checks"] += 1
            self._health_check_errors[shard_id] += 1
            self._shard_health[shard_id] = ShardHealth.UNHEALTHY
            
            return {
                "shard_id": shard_id,
                "error": str(e),
                "timestamp": start_time
            }
    
    async def _check_control_plane_health(self, control_plane_url: str) -> tuple[bool, float]:
        """Check if the shard control plane is responsive"""
        if not self._http_session:
            return False, 0.0
        
        try:
            start_time = datetime.utcnow()
            
            # Make health check request to shard control plane
            health_url = f"{control_plane_url}/health"
            async with self._http_session.get(health_url) as response:
                end_time = datetime.utcnow()
                response_time = (end_time - start_time).total_seconds() * 1000
                
                if response.status == 200:
                    return True, response_time
                else:
                    logger.warning(f"Control plane health check failed with status {response.status}")
                    return False, response_time
                    
        except Exception as e:
            logger.warning(f"Control plane health check failed: {e}")
            return False, 0.0
    
    async def _check_database_health(self, project_id: str) -> bool:
        """Check database health for a project"""
        # In a real implementation, this would:
        # 1. Connect to the shared Cloud SQL instance
        # 2. Perform a simple query (SELECT 1)
        # 3. Check connection pool status
        # 4. Verify read replica connectivity
        
        # For development, simulate database check
        await asyncio.sleep(0.01)  # Simulate database query
        return True  # Assume healthy for development
    
    async def _check_storage_health(self, project_id: str) -> bool:
        """Check storage health for a project"""
        # In a real implementation, this would:
        # 1. List objects in the shared GCS bucket
        # 2. Check bucket accessibility
        # 3. Verify permissions
        
        # For development, simulate storage check
        await asyncio.sleep(0.01)  # Simulate storage check
        return True  # Assume healthy for development
    
    async def _collect_metrics(self):
        """Collect performance and resource metrics from all shards"""
        shards = await self.storage.get_all_shards()
        
        for shard in shards:
            try:
                # In a real implementation, this would query monitoring APIs
                # For development, generate mock metrics
                metrics = await self._generate_mock_metrics(shard.shard_id)
                
                # Store metrics (keep last 24 hours)
                self._metrics_history[shard.shard_id].append(metrics)
                cutoff_time = datetime.utcnow() - timedelta(hours=24)
                self._metrics_history[shard.shard_id] = [
                    m for m in self._metrics_history[shard.shard_id]
                    if m.timestamp > cutoff_time
                ]
                
            except Exception as e:
                logger.error(f"Failed to collect metrics for shard {shard.shard_id}: {e}")
    
    async def _generate_mock_metrics(self, shard_id: str) -> ShardResourceUsage:
        """Generate mock metrics for development"""
        import random
        
        return ShardResourceUsage(
            shard_id=shard_id,
            cpu_utilization_percent=random.uniform(20, 80),
            memory_utilization_percent=random.uniform(30, 90),
            storage_used_gb=random.uniform(100, 800),
            storage_available_gb=random.uniform(200, 1000),
            network_ingress_gb=random.uniform(5, 50),
            network_egress_gb=random.uniform(10, 100),
            database_connections=random.randint(50, 300),
            database_max_connections=500,
            timestamp=datetime.utcnow()
        )
    
    async def _check_alerts(self):
        """Check if any alert conditions are met"""
        for shard_id, health in self._shard_health.items():
            # Check for unhealthy shards
            if health == ShardHealth.UNHEALTHY:
                await self._trigger_alert("shard_unhealthy", {
                    "shard_id": shard_id,
                    "health": health.value
                })
            
            # Check error rate (simplified for development)
            error_count = self._health_check_errors.get(shard_id, 0)
            if error_count >= 3:
                await self._trigger_alert("high_error_rate", {
                    "shard_id": shard_id,
                    "error_count": error_count
                })
    
    async def _trigger_alert(self, alert_type: str, details: Dict[str, Any]):
        """Trigger an alert (simplified implementation)"""
        logger.warning(f"ALERT: {alert_type} - {details}")
        self._stats["alerts_triggered"] += 1
        
        # In a real implementation, this would:
        # 1. Send notifications (email, Slack, PagerDuty)
        # 2. Create incident tickets
        # 3. Trigger automated remediation
    
    async def get_active_shard_count(self) -> int:
        """Get the number of active (healthy) shards"""
        healthy_count = sum(
            1 for health in self._shard_health.values()
            if health == ShardHealth.HEALTHY
        )
        return healthy_count
    
    async def get_shard_status(self, shard_id: str) -> Optional[ShardStatus]:
        """Get detailed status for a specific shard"""
        shard = await self.storage.get_shard(shard_id)
        if not shard:
            return None
        
        health = self._shard_health.get(shard_id, ShardHealth.UNKNOWN)
        last_check = self._last_health_check.get(shard_id)
        
        # Get latest metrics
        latest_metrics = None
        if shard_id in self._metrics_history and self._metrics_history[shard_id]:
            latest_metrics = self._metrics_history[shard_id][-1]
        
        # Calculate utilization
        utilization_percent = (shard.tenant_count / max(1, shard.max_tenants)) * 100
        
        return ShardStatus(
            shard_id=shard_id,
            project_id=shard.project_id,
            region=shard.region,
            health=health,
            tenant_count=shard.tenant_count,
            max_tenants=shard.max_tenants,
            utilization_percent=utilization_percent,
            control_plane_url=shard.control_plane_url,
            control_plane_healthy=health in [ShardHealth.HEALTHY, ShardHealth.DEGRADED],
            database_healthy=health in [ShardHealth.HEALTHY, ShardHealth.DEGRADED],
            storage_healthy=health in [ShardHealth.HEALTHY, ShardHealth.DEGRADED],
            last_health_check=last_check or datetime.utcnow(),
            response_time_ms=latest_metrics.cpu_utilization_percent if latest_metrics else None,
            error_rate_percent=self._health_check_errors.get(shard_id, 0) * 10.0,
            resource_usage=latest_metrics.dict() if latest_metrics else {}
        )
    
    async def get_all_shard_status(self) -> List[ShardStatus]:
        """Get status for all shards"""
        shards = await self.storage.get_all_shards()
        
        status_list = []
        for shard in shards:
            status = await self.get_shard_status(shard.shard_id)
            if status:
                status_list.append(status)
        
        return status_list
    
    async def get_global_metrics(self) -> GlobalMetrics:
        """Get aggregated global platform metrics"""
        shards = await self.storage.get_all_shards()
        tenants = await self.storage.get_all_tenants()
        
        # Calculate health distribution
        healthy_shards = sum(1 for s in shards if self._shard_health.get(s.shard_id) == ShardHealth.HEALTHY)
        degraded_shards = sum(1 for s in shards if self._shard_health.get(s.shard_id) == ShardHealth.DEGRADED)
        unhealthy_shards = sum(1 for s in shards if self._shard_health.get(s.shard_id) == ShardHealth.UNHEALTHY)
        
        # Calculate capacity metrics
        total_capacity = sum(shard.max_tenants for shard in shards)
        used_capacity = len(tenants)
        utilization_percent = (used_capacity / max(1, total_capacity)) * 100
        
        # Calculate performance metrics (mock for development)
        avg_response_time = 85.0
        p99_response_time = 150.0
        global_error_rate = 0.5
        
        # Calculate cost metrics (mock for development)
        estimated_monthly_cost = len(shards) * 150.0  # $150 per shard
        cost_per_tenant = estimated_monthly_cost / max(1, used_capacity)
        
        # Regional distribution
        regional_distribution = {}
        for shard in shards:
            region = shard.region
            if region not in regional_distribution:
                regional_distribution[region] = 0
            regional_distribution[region] += 1
        
        return GlobalMetrics(
            timestamp=datetime.utcnow(),
            total_projects=len(shards),  # One project per shard
            total_shards=len(shards),
            total_tenants=len(tenants),
            active_tenants=used_capacity,
            avg_response_time_ms=avg_response_time,
            p99_response_time_ms=p99_response_time,
            global_error_rate_percent=global_error_rate,
            total_capacity=total_capacity,
            used_capacity=used_capacity,
            utilization_percent=utilization_percent,
            healthy_shards=healthy_shards,
            degraded_shards=degraded_shards,
            unhealthy_shards=unhealthy_shards,
            estimated_monthly_cost=estimated_monthly_cost,
            cost_per_tenant=cost_per_tenant,
            regional_distribution=regional_distribution
        )
    
    async def get_capacity_report(self) -> CapacityReport:
        """Generate capacity planning report"""
        shards = await self.storage.get_all_shards()
        tenants = await self.storage.get_all_tenants()
        
        current_shards = len(shards)
        total_capacity = sum(shard.max_tenants for shard in shards)
        used_capacity = len(tenants)
        current_utilization = (used_capacity / max(1, total_capacity)) * 100
        
        # Simple growth projection (would be more sophisticated in production)
        projected_growth_rate = 10.0  # 10% monthly growth
        projected_shards_needed = int(current_shards * 1.2)  # 20% more shards needed
        
        # Capacity planning recommendations
        should_create_new_shards = current_utilization > 80.0
        recommended_new_shards = max(0, projected_shards_needed - current_shards)
        
        # Time to capacity calculation
        if projected_growth_rate > 0:
            remaining_capacity = total_capacity - used_capacity
            months_to_capacity = remaining_capacity / (used_capacity * projected_growth_rate / 100)
        else:
            months_to_capacity = None
        
        # Regional capacity breakdown
        regional_capacity = {}
        for shard in shards:
            region = shard.region
            if region not in regional_capacity:
                regional_capacity[region] = {
                    "shards": 0,
                    "total_capacity": 0,
                    "used_capacity": 0,
                    "utilization_percent": 0
                }
            
            regional_capacity[region]["shards"] += 1
            regional_capacity[region]["total_capacity"] += shard.max_tenants
            
            # Count tenants in this region (simplified)
            region_tenants = len([t for t in tenants if t.shard_id == shard.shard_id])
            regional_capacity[region]["used_capacity"] += region_tenants
            regional_capacity[region]["utilization_percent"] = (
                regional_capacity[region]["used_capacity"] / 
                max(1, regional_capacity[region]["total_capacity"])
            ) * 100
        
        return CapacityReport(
            timestamp=datetime.utcnow(),
            current_shards=current_shards,
            projected_shards_needed=projected_shards_needed,
            current_utilization_percent=current_utilization,
            projected_growth_rate=projected_growth_rate,
            should_create_new_shards=should_create_new_shards,
            recommended_new_shards=recommended_new_shards,
            estimated_months_to_capacity=months_to_capacity,
            regional_capacity=regional_capacity,
            current_monthly_cost=current_shards * 150.0,
            projected_monthly_cost=projected_shards_needed * 150.0
        )
    
    async def get_monitoring_statistics(self) -> Dict[str, Any]:
        """Get health monitoring statistics"""
        total_checks = self._stats["total_health_checks"]
        failed_checks = self._stats["failed_health_checks"]
        success_rate = ((total_checks - failed_checks) / max(1, total_checks)) * 100
        
        return {
            **self._stats.copy(),
            "success_rate_percent": success_rate,
            "monitoring_active": self._monitoring_active,
            "health_check_interval_seconds": self.config.health_check_interval_seconds,
            "shards_with_errors": len([k for k, v in self._health_check_errors.items() if v > 0])
        }
