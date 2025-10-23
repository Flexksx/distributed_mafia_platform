# Monitoring Stack

This directory contains the monitoring configuration for the Mafia Platform using Prometheus and Grafana.

## Services

### Prometheus
- **URL**: http://localhost:9090
- **Purpose**: Metrics collection and storage
- **Configuration**: `prometheus.yml`

### Grafana
- **URL**: http://localhost:3000
- **Default Credentials**: admin/admin
- **Purpose**: Visualization and dashboards
- **Configuration**: `grafana/provisioning/`

## Configuration Files

- `prometheus.yml` - Prometheus scrape configuration
- `grafana/provisioning/datasources/prometheus.yml` - Grafana datasource configuration
- `grafana/provisioning/dashboards/dashboards.yml` - Dashboard provisioning
- `grafana/dashboards/mafia-platform.json` - Mafia Platform monitoring dashboard

## Monitoring Targets

Prometheus is configured to scrape the following services:

- **service-discovery** (port 3004) - Service discovery metrics
- **gateway** (port 8080) - API Gateway metrics
- **user-management** (port 3000) - User management service metrics
- **game-service** (port 3001) - Game service metrics
- **task-service** (port 3002) - Task service metrics
- **voting-service** (port 3003) - Voting service metrics

## Environment Variables

You can customize the monitoring stack using these environment variables:

```bash
# Prometheus
PROMETHEUS_PORT=9090

# Grafana
GRAFANA_PORT=3000
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin
```

## Usage

1. Start the monitoring stack:
   ```bash
   docker-compose up prometheus grafana -d
   ```

2. Access Prometheus: http://localhost:9090
3. Access Grafana: http://localhost:3000 (admin/admin)

## Dashboard

The Mafia Platform dashboard includes:
- Service status monitoring
- Total services count
- Service health indicators

## Adding Metrics to Services

To add metrics to your services, expose a `/metrics` endpoint that returns Prometheus-formatted metrics. The service discovery service already includes basic health metrics.

Example metrics endpoint:
```
# HELP service_requests_total Total number of requests
# TYPE service_requests_total counter
service_requests_total{service="my-service"} 42
```
