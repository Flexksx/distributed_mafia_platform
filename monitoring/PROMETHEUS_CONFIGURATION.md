# Prometheus Monitoring Configuration - Town & Character Services

## Summary of Changes

Updated `monitoring/prometheus.yml` to add scrape configurations for both `town-service` and `character-service` with automatic discovery of all 3 replicas per service.

## Changes Made

### 1. Town Service Scrape Configuration
```yaml
- job_name: 'town-service'
  dns_sd_configs:
    - names: ['town-service']
      type: 'A'
      port: 8081
  relabel_configs:
    - source_labels: [__meta_dns_name]
      target_label: instance
      regex: 'town-service'
      replacement: 'town-service'
    - source_labels: [__address__]
      target_label: service_name
      replacement: 'town-service'
  metrics_path: '/actuator/prometheus'
  scrape_interval: 15s
```

### 2. Character Service Scrape Configuration
```yaml
- job_name: 'character-service'
  dns_sd_configs:
    - names: ['character-service']
      type: 'A'
      port: 8080
  relabel_configs:
    - source_labels: [__meta_dns_name]
      target_label: instance
      regex: 'character-service'
      replacement: 'character-service'
    - source_labels: [__address__]
      target_label: service_name
      replacement: 'character-service'
  metrics_path: '/actuator/prometheus'
  scrape_interval: 15s
```

## Configuration Details

### DNS Service Discovery
Both services use **DNS-based service discovery** instead of static targets. This means:

✅ **Automatic Instance Discovery**: Prometheus automatically discovers all 3 replicas of each service  
✅ **Dynamic Scaling**: When you scale up/down, Prometheus updates targets automatically  
✅ **No Manual Configuration**: No need to list each instance IP address  
✅ **Docker Network Integration**: Uses Docker's built-in DNS resolution  

### How DNS Service Discovery Works

1. **Docker Compose** creates multiple containers for each service (3 replicas)
2. **Docker DNS** resolves `town-service` and `character-service` to all container IPs
3. **Prometheus** queries DNS every scrape interval
4. **All instances** are automatically discovered and scraped

Example DNS resolution:
```bash
# town-service resolves to 3 IPs
town-service -> 172.18.0.10, 172.18.0.11, 172.18.0.12

# character-service resolves to 3 IPs  
character-service -> 172.18.0.13, 172.18.0.14, 172.18.0.15
```

### Metrics Configuration

#### Town Service
- **Port**: 8081 (matches `TOWN_SERVICE_PORT`)
- **Metrics Path**: `/actuator/prometheus` (Spring Boot Actuator)
- **Scrape Interval**: 15 seconds (more frequent than default)
- **Discovered Instances**: All 3 replicas automatically

#### Character Service
- **Port**: 8080 (matches `CHARACTER_SERVICE_PORT`)
- **Metrics Path**: `/actuator/prometheus` (Spring Boot Actuator)
- **Scrape Interval**: 15 seconds (more frequent than default)
- **Discovered Instances**: All 3 replicas automatically

### Relabel Configuration

The `relabel_configs` section standardizes labels:

```yaml
relabel_configs:
  - source_labels: [__meta_dns_name]
    target_label: instance
    replacement: 'town-service'
```

This ensures consistent labels across all instances:
- `instance="town-service"` (instead of IP addresses)
- `service_name="town-service"`
- Individual instance IPs are preserved in `__address__`

## Spring Boot Actuator Metrics

Both services expose Spring Boot Actuator metrics at `/actuator/prometheus`:

### Available Metrics

#### JVM Metrics
- `jvm_memory_used_bytes` - Memory usage
- `jvm_memory_max_bytes` - Maximum memory
- `jvm_gc_pause_seconds` - Garbage collection pauses
- `jvm_threads_live` - Active thread count
- `jvm_classes_loaded` - Loaded classes

#### HTTP Metrics
- `http_server_requests_seconds` - Request latency
- `http_server_requests_seconds_count` - Request count
- `http_server_requests_seconds_sum` - Total request time

#### Database Metrics
- `hikaricp_connections_active` - Active DB connections
- `hikaricp_connections_idle` - Idle DB connections
- `hikaricp_connections_pending` - Waiting connections

#### Application Metrics
- `process_cpu_usage` - CPU usage
- `system_cpu_usage` - System CPU usage
- `process_uptime_seconds` - Service uptime

## Verifying the Configuration

### 1. Check Prometheus Targets
After starting the services, visit:
```
http://localhost:9090/targets
```

You should see:
- ✅ `town-service` with 3 targets (UP)
- ✅ `character-service` with 3 targets (UP)

### 2. Query Metrics in Prometheus
Example queries:

```promql
# Request rate for town service
rate(http_server_requests_seconds_count{service_name="town-service"}[5m])

# Memory usage for character service
jvm_memory_used_bytes{service_name="character-service", area="heap"}

# CPU usage across all instances
process_cpu_usage{service_name=~"town-service|character-service"}

# 95th percentile response time
histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))
```

### 3. Test DNS Resolution
From inside the Prometheus container:

```bash
# Verify DNS resolves to multiple IPs
docker-compose exec prometheus nslookup town-service
docker-compose exec prometheus nslookup character-service

# Each should return 3 IP addresses
```

## Grafana Dashboard Integration

Create dashboards to visualize the metrics:

### Town Service Dashboard
```json
{
  "title": "Town Service Metrics",
  "panels": [
    {
      "title": "Request Rate",
      "target": "rate(http_server_requests_seconds_count{service_name=\"town-service\"}[5m])"
    },
    {
      "title": "Response Time (p95)",
      "target": "histogram_quantile(0.95, rate(http_server_requests_seconds_bucket{service_name=\"town-service\"}[5m]))"
    },
    {
      "title": "Memory Usage",
      "target": "jvm_memory_used_bytes{service_name=\"town-service\", area=\"heap\"}"
    }
  ]
}
```

### Character Service Dashboard
```json
{
  "title": "Character Service Metrics",
  "panels": [
    {
      "title": "Request Rate",
      "target": "rate(http_server_requests_seconds_count{service_name=\"character-service\"}[5m])"
    },
    {
      "title": "Response Time (p95)",
      "target": "histogram_quantile(0.95, rate(http_server_requests_seconds_bucket{service_name=\"character-service\"}[5m]))"
    },
    {
      "title": "Memory Usage",
      "target": "jvm_memory_used_bytes{service_name=\"character-service\", area=\"heap\"}"
    }
  ]
}
```

## Testing the Configuration

### 1. Start the Stack
```bash
cd /home/lifan/Univer/PAD/distributed_mafia_platform
docker-compose up -d
```

### 2. Wait for Services to Start
```bash
# Monitor startup
docker-compose logs -f town-service character-service prometheus

# Check health
docker-compose ps
```

### 3. Verify Prometheus Scraping
```bash
# Check Prometheus logs
docker-compose logs prometheus | grep "town-service\|character-service"

# You should see successful scrape messages
```

### 4. Query Metrics
```bash
# Check if metrics are being collected
curl "http://localhost:9090/api/v1/query?query=up{job='town-service'}"
curl "http://localhost:9090/api/v1/query?query=up{job='character-service'}"

# Should return: "value": [timestamp, "1"] for each instance
```

### 5. Generate Load and Verify
```bash
# Generate some traffic
for i in {1..100}; do
  curl http://localhost:8000/api/towns
  curl http://localhost:8000/api/characters
done

# Query request metrics
curl "http://localhost:9090/api/v1/query?query=rate(http_server_requests_seconds_count{service_name='town-service'}[1m])"
```

## Troubleshooting

### No Targets Discovered
```bash
# Check DNS resolution
docker-compose exec prometheus nslookup town-service
docker-compose exec prometheus nslookup character-service

# Verify service is running
docker-compose ps town-service character-service

# Check Prometheus logs
docker-compose logs prometheus | tail -50
```

### Metrics Endpoint Not Found (404)
```bash
# Verify actuator is exposed
docker-compose exec town-service curl http://localhost:8081/actuator/prometheus
docker-compose exec character-service curl http://localhost:8080/actuator/prometheus

# Check Spring Boot configuration
docker-compose exec town-service env | grep MANAGEMENT
```

### Wrong Port
Verify ports match in:
1. `docker-compose.yml` - `ports` section
2. `prometheus.yml` - `port` in `dns_sd_configs`
3. Service environment variables - `SERVER_PORT`

### Only 1 Target Instead of 3
```bash
# Check replica count
docker-compose ps | grep "town-service\|character-service"

# Should see 3 containers per service
# If not, check deploy.replicas in docker-compose.yml
```

## Alternative: Static Configuration (Not Recommended)

If DNS service discovery doesn't work, you can use static configs (but lose automatic scaling):

```yaml
# NOT RECOMMENDED - manual maintenance required
- job_name: 'town-service'
  static_configs:
    - targets: 
        - 'town-service-1:8081'
        - 'town-service-2:8081'
        - 'town-service-3:8081'
  metrics_path: '/actuator/prometheus'
  scrape_interval: 15s
```

## Monitoring Best Practices

1. **Set Alerts**: Configure alerting rules for:
   - High error rates
   - Slow response times (p95 > threshold)
   - Memory leaks (increasing heap usage)
   - High CPU usage

2. **Retention Policy**: Prometheus retains 15 days by default
   - Adjust via `--storage.tsdb.retention.time` flag

3. **Scrape Intervals**:
   - 15s for application services (real-time monitoring)
   - 30s for infrastructure services
   - 60s for less critical metrics

4. **Cardinality**: Avoid high-cardinality labels (user IDs, request IDs)

## Files Modified

- ✅ `monitoring/prometheus.yml` - Added town-service and character-service scrape configs

## Related Configuration

### Spring Boot Services Must Enable Actuator
Both services should have in `application.yml` or `application.properties`:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus,metrics
  metrics:
    export:
      prometheus:
        enabled: true
```

### Docker Compose Network
Services must be on the same network:
```yaml
networks:
  - mafia-network
```

## Next Steps

1. ✅ **Configuration Updated** - prometheus.yml ready
2. 🔄 **Restart Prometheus** - `docker-compose restart prometheus`
3. ✅ **Verify Targets** - Check http://localhost:9090/targets
4. 📊 **Create Dashboards** - Import/create Grafana dashboards
5. 🔔 **Configure Alerts** - Set up alerting rules
6. 📈 **Monitor Metrics** - Use queries to track performance

## Useful Prometheus Queries

```promql
# All instances health status
up{job=~"town-service|character-service"}

# Request rate per service
sum(rate(http_server_requests_seconds_count[5m])) by (service_name)

# Error rate
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) by (service_name)

# Memory usage per instance
jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}

# Database connection pool usage
hikaricp_connections_active / hikaricp_connections_max

# Top slowest endpoints
topk(10, histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m])))
```

---

**Status**: ✅ Configuration Complete  
**Discovery Method**: DNS Service Discovery (automatic)  
**Instances Monitored**: 3 per service (6 total)  
**Scrape Interval**: 15 seconds  
**Metrics Endpoint**: `/actuator/prometheus` (Spring Boot Actuator)

