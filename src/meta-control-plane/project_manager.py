"""
Project Manager Module for AIPress Meta Control Plane

Manages GCP project lifecycle, creation, and configuration for the
multi-project federation architecture.

Based on project management requirements from SCALING_TO_50K_SITES.md
"""

import logging
import asyncio
from typing import Dict, List, Optional, Any
from datetime import datetime

from .models import ProjectInfo, Shard, ProjectStatus, ShardHealth
from .storage import MetadataStorage


logger = logging.getLogger(__name__)


class ProjectManager:
    """
    Manages GCP project lifecycle for the multi-project federation.
    
    Key responsibilities:
    - Create and configure GCP projects for shards
    - Manage project quotas and billing
    - Monitor project health and status
    - Coordinate cross-project networking
    """
    
    def __init__(self, organization_id: str, billing_account: str, storage: Optional[MetadataStorage] = None):
        self.organization_id = organization_id
        self.billing_account = billing_account
        self.storage = storage or MetadataStorage()
        
        # GCP clients (would be initialized with actual GCP libraries)
        self._resource_manager_client = None
        self._billing_client = None
        self._compute_client = None
        
        # Project management state
        self._projects: Dict[str, ProjectInfo] = {}
        self._shards: Dict[str, Shard] = {}
        self._project_creation_queue = asyncio.Queue()
        
        # Configuration
        self.default_region = "us-central1"
        self.project_prefix = "aipress-shard"
        
        # Statistics
        self._stats = {
            "projects_created": 0,
            "projects_deleted": 0,
            "creation_failures": 0,
            "active_projects": 0
        }
    
    async def initialize(self):
        """Initialize the project manager"""
        logger.info("Initializing ProjectManager...")
        
        # Initialize storage
        await self.storage.initialize()
        
        # Load existing projects and shards
        projects = await self.storage.get_all_projects()
        shards = await self.storage.get_all_shards()
        
        for project in projects:
            self._projects[project.project_id] = project
        
        for shard in shards:
            self._shards[shard.shard_id] = shard
        
        # In a real implementation, initialize GCP clients:
        # from google.cloud import resourcemanager
        # from google.cloud import billing
        # from google.cloud import compute
        # 
        # self._resource_manager_client = resourcemanager.ProjectsClient()
        # self._billing_client = billing.CloudBillingClient()
        # self._compute_client = compute.InstancesClient()
        
        self._stats["active_projects"] = len(self._projects)
        
        logger.info(f"Initialized ProjectManager with {len(projects)} projects and {len(shards)} shards")
    
    async def ensure_shard_exists(self, shard_id: str) -> Shard:
        """
        Ensure that a shard exists, creating it if necessary.
        
        Returns the shard information after ensuring it exists.
        """
        # Check if shard already exists
        if shard_id in self._shards:
            return self._shards[shard_id]
        
        # Check storage for existing shard
        existing_shard = await self.storage.get_shard(shard_id)
        if existing_shard:
            self._shards[shard_id] = existing_shard
            return existing_shard
        
        # Create new shard
        logger.info(f"Creating new shard: {shard_id}")
        return await self.create_shard_project(shard_id)
    
    async def create_shard_project(self, shard_id: str, region: Optional[str] = None) -> Shard:
        """
        Create a new GCP project for a shard.
        
        This involves:
        1. Creating the GCP project
        2. Enabling required APIs
        3. Setting up billing
        4. Configuring networking
        5. Deploying the shard control plane
        """
        if not region:
            region = self.default_region
        
        project_id = self._generate_project_id(shard_id)
        
        try:
            # Step 1: Create GCP project
            logger.info(f"Creating GCP project: {project_id}")
            project_info = await self._create_gcp_project(project_id, shard_id)
            
            # Step 2: Configure project
            await self._configure_project(project_info, region)
            
            # Step 3: Create shard metadata
            shard = Shard(
                shard_id=shard_id,
                project_id=project_id,
                region=region,
                control_plane_url=f"https://{project_id}-control-plane.run.app",
                created_at=datetime.utcnow(),
                health=ShardHealth.UNKNOWN  # Will be updated by health monitor
            )
            
            # Step 4: Store metadata
            await self.storage.save_project(project_info)
            await self.storage.save_shard(shard)
            
            # Step 5: Update local cache
            self._projects[project_id] = project_info
            self._shards[shard_id] = shard
            
            self._stats["projects_created"] += 1
            self._stats["active_projects"] += 1
            
            logger.info(f"Successfully created shard {shard_id} with project {project_id}")
            return shard
            
        except Exception as e:
            logger.error(f"Failed to create shard {shard_id}: {e}")
            self._stats["creation_failures"] += 1
            raise
    
    async def _create_gcp_project(self, project_id: str, shard_id: str) -> ProjectInfo:
        """Create the actual GCP project"""
        
        # In a real implementation, this would use the GCP API:
        # project = {
        #     "project_id": project_id,
        #     "name": f"AIPress Shard {shard_id}",
        #     "parent": {"type": "organization", "id": self.organization_id}
        # }
        # 
        # operation = self._resource_manager_client.create_project(project=project)
        # result = operation.result()  # Wait for completion
        
        # For development, create a mock project info
        project_info = ProjectInfo(
            project_id=project_id,
            project_name=f"AIPress Shard {shard_id}",
            shard_id=shard_id,
            status=ProjectStatus.CREATING,
            region=self.default_region,
            billing_account=self.billing_account,
            organization_id=self.organization_id,
            created_at=datetime.utcnow(),
            resource_usage={},
            cost_data={}
        )
        
        # Simulate project creation time
        await asyncio.sleep(0.1)
        project_info.status = ProjectStatus.ACTIVE
        
        logger.info(f"Created GCP project {project_id}")
        return project_info
    
    async def _configure_project(self, project_info: ProjectInfo, region: str):
        """Configure the newly created project"""
        project_id = project_info.project_id
        
        logger.info(f"Configuring project {project_id}")
        
        # In a real implementation, this would:
        # 1. Enable required APIs
        # 2. Set up billing
        # 3. Configure IAM roles
        # 4. Set up networking (VPC, subnets, firewall rules)
        # 5. Deploy the shard control plane
        
        # For development, simulate configuration
        configuration_steps = [
            "enable_apis",
            "setup_billing", 
            "configure_iam",
            "setup_networking",
            "deploy_control_plane"
        ]
        
        for step in configuration_steps:
            logger.debug(f"Configuring {project_id}: {step}")
            await asyncio.sleep(0.05)  # Simulate API calls
        
        logger.info(f"Successfully configured project {project_id}")
    
    def _generate_project_id(self, shard_id: str) -> str:
        """Generate a unique project ID for a shard"""
        # Extract shard number from shard_id (e.g., "aipress-shard-001" -> "001")
        shard_number = shard_id.split('-')[-1]
        return f"{self.project_prefix}-{shard_number}"
    
    async def get_shard_info(self, shard_id: str) -> Optional[Shard]:
        """Get shard information"""
        if shard_id in self._shards:
            return self._shards[shard_id]
        
        # Check storage
        shard = await self.storage.get_shard(shard_id)
        if shard:
            self._shards[shard_id] = shard
        
        return shard
    
    async def get_project_info(self, project_id: str) -> Optional[ProjectInfo]:
        """Get project information"""
        if project_id in self._projects:
            return self._projects[project_id]
        
        # Check storage
        project = await self.storage.get_project(project_id)
        if project:
            self._projects[project_id] = project
        
        return project
    
    async def list_projects(self) -> List[ProjectInfo]:
        """List all managed projects"""
        return list(self._projects.values())
    
    async def list_shards(self) -> List[Shard]:
        """List all shards"""
        return list(self._shards.values())
    
    async def delete_project(self, project_id: str) -> bool:
        """
        Delete a GCP project and associated shard.
        
        This is a destructive operation that should be used carefully.
        """
        try:
            logger.info(f"Deleting project {project_id}")
            
            # Find associated shard
            shard_id = None
            for sid, shard in self._shards.items():
                if shard.project_id == project_id:
                    shard_id = sid
                    break
            
            # In a real implementation:
            # operation = self._resource_manager_client.delete_project(name=f"projects/{project_id}")
            # operation.result()  # Wait for completion
            
            # Remove from storage
            await self.storage.delete_project(project_id)
            if shard_id:
                await self.storage.delete_shard(shard_id)
            
            # Remove from cache
            if project_id in self._projects:
                del self._projects[project_id]
            if shard_id and shard_id in self._shards:
                del self._shards[shard_id]
            
            self._stats["projects_deleted"] += 1
            self._stats["active_projects"] -= 1
            
            logger.info(f"Successfully deleted project {project_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to delete project {project_id}: {e}")
            return False
    
    async def update_project_status(self, project_id: str, status: ProjectStatus):
        """Update the status of a project"""
        if project_id in self._projects:
            self._projects[project_id].status = status
            await self.storage.save_project(self._projects[project_id])
    
    async def get_project_resource_usage(self, project_id: str) -> Dict[str, Any]:
        """
        Get resource usage information for a project.
        
        In a real implementation, this would query GCP APIs for:
        - Compute usage (CPU, memory, disk)
        - Network usage (bandwidth, requests)
        - Database usage (connections, storage)
        - Storage usage (buckets, objects)
        """
        # For development, return mock data
        return {
            "timestamp": datetime.utcnow().isoformat(),
            "compute": {
                "cpu_hours": 100.5,
                "memory_gb_hours": 250.0,
                "instances": 5
            },
            "storage": {
                "bucket_storage_gb": 50.2,
                "objects": 1500
            },
            "database": {
                "cpu_hours": 24.0,
                "storage_gb": 25.0,
                "connections": 150
            },
            "network": {
                "ingress_gb": 10.5,
                "egress_gb": 25.8
            }
        }
    
    async def get_project_costs(self, project_id: str) -> Dict[str, Any]:
        """
        Get cost information for a project.
        
        In a real implementation, this would query the Cloud Billing API.
        """
        # For development, return mock cost data
        base_cost = 150.0  # Base monthly cost per shard
        return {
            "timestamp": datetime.utcnow().isoformat(),
            "current_month_cost": base_cost,
            "projected_month_cost": base_cost * 1.1,
            "cost_breakdown": {
                "compute": base_cost * 0.4,
                "database": base_cost * 0.3,
                "storage": base_cost * 0.2,
                "network": base_cost * 0.1
            },
            "currency": "USD"
        }
    
    async def scale_shard_resources(self, shard_id: str, target_capacity: int):
        """
        Scale resources for a shard based on demand.
        
        This would adjust:
        - Cloud Run instance limits
        - Database connection pools
        - Storage allocations
        """
        shard = await self.get_shard_info(shard_id)
        if not shard:
            raise ValueError(f"Shard {shard_id} not found")
        
        logger.info(f"Scaling shard {shard_id} to capacity {target_capacity}")
        
        # Update shard metadata
        shard.max_tenants = target_capacity
        await self.storage.save_shard(shard)
        self._shards[shard_id] = shard
        
        # In a real implementation, this would:
        # 1. Update Cloud Run service configuration
        # 2. Adjust database connection limits
        # 3. Update storage quotas
        # 4. Modify monitoring thresholds
    
    async def get_federation_status(self) -> Dict[str, Any]:
        """Get overall federation status and statistics"""
        total_shards = len(self._shards)
        healthy_shards = sum(1 for shard in self._shards.values() if shard.health == ShardHealth.HEALTHY)
        
        total_capacity = sum(shard.max_tenants for shard in self._shards.values())
        used_capacity = sum(shard.tenant_count for shard in self._shards.values())
        
        # Regional distribution
        regional_distribution = {}
        for shard in self._shards.values():
            region = shard.region
            if region not in regional_distribution:
                regional_distribution[region] = 0
            regional_distribution[region] += 1
        
        return {
            "timestamp": datetime.utcnow(),
            "total_projects": len(self._projects),
            "total_shards": total_shards,
            "healthy_shards": healthy_shards,
            "unhealthy_shards": total_shards - healthy_shards,
            "total_capacity": total_capacity,
            "used_capacity": used_capacity,
            "utilization_percent": (used_capacity / max(1, total_capacity)) * 100,
            "regional_distribution": regional_distribution,
            "statistics": self._stats.copy()
        }
    
    async def cleanup_failed_projects(self):
        """Clean up projects that failed to create properly"""
        failed_projects = [
            project_id for project_id, project in self._projects.items()
            if project.status in [ProjectStatus.ERROR, ProjectStatus.SUSPENDED]
        ]
        
        logger.info(f"Cleaning up {len(failed_projects)} failed projects")
        
        for project_id in failed_projects:
            try:
                await self.delete_project(project_id)
            except Exception as e:
                logger.error(f"Failed to cleanup project {project_id}: {e}")
    
    async def close(self):
        """Close connections and cleanup"""
        logger.info("Closing ProjectManager...")
        await self.storage.close()
