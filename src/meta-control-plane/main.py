"""
AIPress Meta Control Plane

Central orchestrator for managing 1,000+ project shards in the AIPress platform.
Handles tenant-to-shard routing, project lifecycle management, and global coordination.

Based on ARCHITECTURE.md and SCALING_TO_50K_SITES.md specifications.
"""

import hashlib
import logging
import os
from typing import Dict, List, Optional
from datetime import datetime

from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

from .models import (
    Tenant, Shard, ProjectInfo, HealthStatus, 
    TenantCreateRequest, TenantRouteResponse,
    ShardStatus, GlobalMetrics
)
from .routing import TenantRouter
from .project_manager import ProjectManager
from .health_monitor import HealthMonitor

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
NUM_SHARDS = int(os.getenv("NUM_SHARDS", "1000"))  # Target: 1,000 shards
SITES_PER_SHARD = int(os.getenv("SITES_PER_SHARD", "50"))  # 50 sites per shard
GCP_ORGANIZATION_ID = os.getenv("GCP_ORGANIZATION_ID")
GCP_BILLING_ACCOUNT = os.getenv("GCP_BILLING_ACCOUNT")

app = FastAPI(
    title="AIPress Meta Control Plane",
    description="Central orchestrator for managing 50,000+ WordPress sites across 1,000+ GCP projects",
    version="1.0.0"
)

# CORS middleware for frontend access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize core components
tenant_router = TenantRouter(num_shards=NUM_SHARDS)
project_manager = ProjectManager(
    organization_id=GCP_ORGANIZATION_ID,
    billing_account=GCP_BILLING_ACCOUNT
)
health_monitor = HealthMonitor()

@app.on_startup
async def startup_event():
    """Initialize services on startup"""
    logger.info("Starting AIPress Meta Control Plane...")
    await project_manager.initialize()
    await health_monitor.start_monitoring()
    logger.info(f"Meta Control Plane initialized for {NUM_SHARDS} shards")

@app.on_shutdown
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("Shutting down Meta Control Plane...")
    await health_monitor.stop_monitoring()

# Health and status endpoints
@app.get("/health", response_model=HealthStatus)
async def health_check():
    """Health check endpoint"""
    return HealthStatus(
        status="healthy",
        timestamp=datetime.utcnow(),
        meta_control_plane=True,
        active_shards=await health_monitor.get_active_shard_count(),
        total_tenants=await tenant_router.get_total_tenant_count()
    )

@app.get("/metrics", response_model=GlobalMetrics)
async def get_global_metrics():
    """Get global platform metrics"""
    return await health_monitor.get_global_metrics()

# Tenant routing endpoints
@app.get("/tenants/{tenant_id}/route", response_model=TenantRouteResponse)
async def get_tenant_route(tenant_id: str):
    """Get routing information for a tenant"""
    shard_id = tenant_router.get_shard_for_tenant(tenant_id)
    shard_info = await project_manager.get_shard_info(shard_id)
    
    if not shard_info:
        raise HTTPException(
            status_code=404,
            detail=f"Shard not found for tenant {tenant_id}"
        )
    
    return TenantRouteResponse(
        tenant_id=tenant_id,
        shard_id=shard_id,
        project_id=shard_info.project_id,
        control_plane_url=shard_info.control_plane_url,
        region=shard_info.region
    )

@app.post("/tenants", response_model=TenantRouteResponse)
async def create_tenant(request: TenantCreateRequest):
    """Create a new tenant and assign to optimal shard"""
    
    # Get optimal shard (load balancing)
    optimal_shard = await tenant_router.get_optimal_shard()
    
    # Ensure shard project exists
    shard_info = await project_manager.ensure_shard_exists(optimal_shard)
    
    # Check if shard has capacity
    current_tenants = await tenant_router.get_shard_tenant_count(optimal_shard)
    if current_tenants >= SITES_PER_SHARD:
        # Find alternative shard or create new one
        optimal_shard = await tenant_router.find_available_shard()
        shard_info = await project_manager.ensure_shard_exists(optimal_shard)
    
    # Register tenant in routing table
    await tenant_router.register_tenant(request.tenant_id, optimal_shard)
    
    logger.info(f"Created tenant {request.tenant_id} in shard {optimal_shard}")
    
    return TenantRouteResponse(
        tenant_id=request.tenant_id,
        shard_id=optimal_shard,
        project_id=shard_info.project_id,
        control_plane_url=shard_info.control_plane_url,
        region=shard_info.region
    )

# Project management endpoints
@app.get("/projects", response_model=List[ProjectInfo])
async def list_projects():
    """List all managed GCP projects"""
    return await project_manager.list_projects()

@app.get("/projects/{project_id}")
async def get_project_info(project_id: str):
    """Get detailed information about a specific project"""
    project_info = await project_manager.get_project_info(project_id)
    if not project_info:
        raise HTTPException(status_code=404, detail="Project not found")
    return project_info

@app.post("/projects/{shard_id}")
async def create_shard_project(shard_id: str):
    """Create a new shard project"""
    try:
        project_info = await project_manager.create_shard_project(shard_id)
        return project_info
    except Exception as e:
        logger.error(f"Failed to create shard project {shard_id}: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to create shard project: {str(e)}"
        )

# Shard management endpoints
@app.get("/shards", response_model=List[ShardStatus])
async def list_shards():
    """List all shards with their status"""
    return await health_monitor.get_all_shard_status()

@app.get("/shards/{shard_id}", response_model=ShardStatus)
async def get_shard_status(shard_id: str):
    """Get detailed status of a specific shard"""
    shard_status = await health_monitor.get_shard_status(shard_id)
    if not shard_status:
        raise HTTPException(status_code=404, detail="Shard not found")
    return shard_status

@app.post("/shards/{shard_id}/health-check")
async def trigger_shard_health_check(shard_id: str):
    """Trigger manual health check for a shard"""
    result = await health_monitor.check_shard_health(shard_id)
    return {"shard_id": shard_id, "health_check_result": result}

# Administrative endpoints
@app.post("/admin/rebalance")
async def rebalance_tenants():
    """Trigger tenant rebalancing across shards"""
    # This would be used for load balancing optimization
    result = await tenant_router.rebalance_tenants()
    return {"rebalance_result": result}

@app.get("/admin/capacity")
async def get_capacity_report():
    """Get detailed capacity report across all shards"""
    return await health_monitor.get_capacity_report()

# Development and debugging endpoints
@app.get("/debug/routing/{tenant_id}")
async def debug_tenant_routing(tenant_id: str):
    """Debug routing logic for a specific tenant"""
    return {
        "tenant_id": tenant_id,
        "hash": tenant_router._get_tenant_hash(tenant_id),
        "shard_id": tenant_router.get_shard_for_tenant(tenant_id),
        "routing_algorithm": "consistent_hashing",
        "num_shards": NUM_SHARDS
    }

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8080,
        reload=True,
        log_level="info"
    )
