# Monitoring Configuration for Scaled Services

## Overview

This document explains how the monitoring stack handles multiple replicas of services in the distributed mafia platform.

## Problem Solved

When services are scaled to multiple replicas (e.g., `user-management-service` and `game-service` with 2 replicas each), Prometheus needs to discover and monitor all instances, not just one.

## Solution Implemented

### 1. Updated Prometheus Configuration

The `monitoring/prometheus.yml` file now includes specific configurations for scaled services:

```yaml
# User Management Service - Multiple replicas with static targets
- job_name: 'user-management'
  static_configs:
    - targets: 
        - 'user-management-service-1:3000'
        - 'user-management-service-2:3000'
  relabel_configs:
    - source_labels: [__address__]
      target_label: instance
      regex: 'user-management-service-([0-9]+):3000'
      replacement: 'user-management-service-${1}'
    - target_label: service_name
      replacement: 'user-management-service'
  metrics_path: '/metrics'
  scrape_interval: 30s

# Game Service - Multiple replicas with static targets
- job_name: 'game-service'
  static_configs:
    - targets: 
        - 'game-service-1:3001'
        - 'game-service-2:3001'
  relabel_configs:
    - source_labels: [__address__]
      target_label: instance
      regex: 'game-service-([0-9]+):3001'
      replacement: 'game-service-${1}'
    - target_label: service_name
      replacement: 'game-service'
  metrics_path: '/metrics'
  scrape_interval: 30s
```

### 2. Service Discovery Enhancement

Added a Prometheus-compatible endpoint to the service discovery service:

```python
@router.get("/services/{service_name}/instances")
async def get_service_instances_for_prometheus(service_name: str):
    """Get service instances in Prometheus HTTP service discovery format"""
    # Returns instances in Prometheus HTTP SD format
```

### 3. Docker Socket Access

Added Docker socket mount to Prometheus for potential future Docker-based service discovery:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

## Current Status

✅ **Working Configuration**: Prometheus successfully discovers all replicas
- `user-management-service-1` and `user-management-service-2`
- `game-service-1` and `game-service-2`

✅ **Proper Labeling**: Each instance has unique labels for identification
- `instance`: Specific replica identifier
- `service_name`: Service type identifier
- `job`: Prometheus job name

## Monitoring Endpoints

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3007 (admin/admin)
- **Service Discovery**: http://localhost:3004

## Scaling Guidelines

When adding more replicas to services:

1. **Update Prometheus Config**: Add new targets to the `static_configs` section
2. **Update Docker Compose**: Increase the `replicas` count
3. **Restart Services**: `docker-compose restart prometheus`

### Example: Adding a 3rd replica

```yaml
# In prometheus.yml
- job_name: 'user-management'
  static_configs:
    - targets: 
        - 'user-management-service-1:3000'
        - 'user-management-service-2:3000'
        - 'user-management-service-3:3000'  # Add this line
```

## Future Improvements

1. **Dynamic Service Discovery**: Implement automatic discovery using the service discovery service
2. **Health-based Filtering**: Only monitor healthy instances
3. **Auto-scaling Integration**: Automatically update Prometheus config when replicas change

## Verification

To verify the setup is working:

```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | grep -A3 -B3 "user-management\|game-service"

# Check service discovery endpoint
curl -s http://localhost:3004/v1/services/user-management-service/instances
```

The configuration ensures that all service replicas are properly monitored and metrics are collected from each instance independently.
