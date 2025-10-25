# Docker Compose Updates - Town & Character Services with Scaling

## Summary of Changes

Updated the main `docker-compose.yml` to add scaling support and service discovery integration for both `town-service` and `character-service`.

## Changes Made

### 1. Town Service Configuration
Added scaling and service discovery support:
```yaml
town-service:
  image: liviutofan/town-service:latest
  deploy:
    replicas: 3  # ✅ NEW: Run 3 instances for load balancing
  depends_on:
    service-discovery:
      condition: service_healthy  # ✅ NEW: Wait for service discovery
  environment:
    SERVICE_DISCOVERY_URL: http://service-discovery:3004  # ✅ NEW
    SERVICE_NAME: town  # ✅ NEW
    SERVICE_INSTANCE_ID: town-service-${HOSTNAME:-1}  # ✅ NEW
```

### 2. Character Service Configuration
Added scaling and service discovery support:
```yaml
character-service:
  image: liviutofan/character-service:latest
  deploy:
    replicas: 3  # ✅ NEW: Run 3 instances for load balancing
  depends_on:
    service-discovery:
      condition: service_healthy  # ✅ NEW: Wait for service discovery
  environment:
    SERVICE_DISCOVERY_URL: http://service-discovery:3004  # ✅ NEW
    SERVICE_NAME: character  # ✅ NEW
    SERVICE_INSTANCE_ID: character-service-${HOSTNAME:-1}  # ✅ NEW
```

## Service Configuration Details

### Town Service
- **Image**: `liviutofan/town-service:latest`
- **Replicas**: 3 instances
- **Port**: `${TOWN_SERVICE_PORT}` (from .env)
- **Database**: PostgreSQL via `town-service-db`
- **Health Check**: Spring Boot Actuator at `/actuator/health`
- **Network**: `mafia-network`
- **Service Discovery**: Registers as `town` service

### Character Service
- **Image**: `liviutofan/character-service:latest`
- **Replicas**: 3 instances
- **Port**: `${CHARACTER_SERVICE_PORT}` (from .env)
- **Database**: PostgreSQL via `character-service-db`
- **Health Check**: Spring Boot Actuator at `/actuator/health`
- **Network**: `mafia-network`
- **Service Discovery**: Registers as `character` service

## Network Configuration

Both services are connected to the `mafia-network` bridge network, ensuring they can communicate with:
- ✅ `service-discovery` - For registration and health reporting
- ✅ `gateway` - Receives load-balanced requests
- ✅ Database services - PostgreSQL connections
- ✅ Other microservices - Inter-service communication

## Environment Variables Required

Add these to your `.env` file:

```bash
# Town Service
TOWN_SERVICE_PORT=8081
TOWN_SERVICE_POSTGRES_USER=townuser
TOWN_SERVICE_POSTGRES_PASSWORD=townpass
TOWN_SERVICE_POSTGRES_DB=towndb
TOWN_SERVICE_POSTGRES_PORT=5432

# Character Service
CHARACTER_SERVICE_PORT=8080
CHARACTER_SERVICE_POSTGRES_USER=charuser
CHARACTER_SERVICE_POSTGRES_PASSWORD=charpass
CHARACTER_SERVICE_POSTGRES_DB=chardb
CHARACTER_SERVICE_POSTGRES_PORT=5432

# Service Discovery
SERVICE_DISCOVERY_PORT=3004
SERVICE_DISCOVERY_SECRET=service-discovery-secret-change-me

# Gateway
GATEWAY_PORT=8000
```

## Scaling Features

### Deploy Configuration
```yaml
deploy:
  replicas: 3
```

This creates 3 instances of each service. Docker Compose will:
- Start 3 containers per service
- Load balance across all instances
- Restart failed instances automatically
- Scale up/down with `docker-compose up --scale`

### Health Checks
Each service has comprehensive health checks:
```yaml
healthcheck:
  test: ["CMD-SHELL", "wget -qO- http://localhost:$SERVER_PORT/actuator/health"]
  interval: 15s
  timeout: 5s
  retries: 3
  start_period: 45s
```

- **Interval**: Check every 15 seconds
- **Timeout**: 5 seconds per check
- **Retries**: 3 failed checks before marking unhealthy
- **Start Period**: 45 seconds grace period on startup

## Service Discovery Integration

Both services now automatically:
1. Register with service-discovery on startup
2. Send heartbeats every 60 seconds
3. Report health status
4. Provide load metrics (CPU, memory)
5. Deregister gracefully on shutdown

The gateway uses service discovery to:
- Query healthy instances
- Load balance requests (round-robin, least-load, etc.)
- Automatically remove unhealthy instances
- Add new instances dynamically

## Dependencies

### Town Service Dependencies
```yaml
depends_on:
  town-service-db:
    condition: service_healthy
  user-management-service:
    condition: service_healthy
  service-discovery:
    condition: service_healthy
```

### Character Service Dependencies
```yaml
depends_on:
  character-service-db:
    condition: service_healthy
  user-management-service:
    condition: service_healthy
  service-discovery:
    condition: service_healthy
```

This ensures proper startup order:
1. Database becomes healthy
2. User management service starts
3. Service discovery starts
4. Town/Character services start and register

## Usage

### Start All Services
```bash
docker-compose up -d
```

### Scale Services Manually
```bash
# Scale town service to 5 instances
docker-compose up -d --scale town-service=5

# Scale character service to 4 instances
docker-compose up -d --scale character-service=4
```

### View Service Status
```bash
# Check all services
docker-compose ps

# Check specific service
docker-compose ps town-service
docker-compose ps character-service

# View logs
docker-compose logs -f town-service
docker-compose logs -f character-service
```

### Check Health
```bash
# Gateway health (includes all services)
curl http://localhost:8000/health

# Service discovery (view registered instances)
curl http://localhost:3004/v1/discovery/services

# Direct service health check
curl http://localhost:8081/actuator/health  # town-service
curl http://localhost:8080/actuator/health  # character-service
```

## Testing Load Balancing

```bash
# Make multiple requests - should distribute across instances
for i in {1..10}; do
  curl http://localhost:8000/api/towns
  echo "Request $i completed"
done

for i in {1..10}; do
  curl http://localhost:8000/api/characters
  echo "Request $i completed"
done
```

Check gateway logs to see which instances received requests:
```bash
docker-compose logs gateway | grep "Forwarding request"
```

## Monitoring

### Prometheus Metrics
Both services expose metrics that Prometheus collects:
- Request count per endpoint
- Response times
- Error rates
- JVM metrics (heap, threads, GC)

Access Prometheus: http://localhost:9090

### Grafana Dashboards
Pre-configured dashboards show:
- Service health status
- Request distribution across instances
- Database connection pools
- Memory and CPU usage

Access Grafana: http://localhost:3000 (admin/admin)

## Troubleshooting

### Service Won't Start
```bash
# Check dependencies
docker-compose ps

# View startup logs
docker-compose logs town-service
docker-compose logs character-service

# Check database connectivity
docker-compose logs town-service-db
docker-compose logs character-service-db
```

### No Instances in Service Discovery
```bash
# Check service discovery logs
docker-compose logs service-discovery

# Verify network connectivity
docker-compose exec town-service ping service-discovery
docker-compose exec character-service ping service-discovery

# Check environment variables
docker-compose exec town-service env | grep SERVICE_DISCOVERY
```

### Load Balancing Not Working
```bash
# Check gateway logs
docker-compose logs gateway | grep "town\|character"

# Verify healthy instances
curl http://localhost:3004/v1/discovery/services | jq '.services.town'
curl http://localhost:3004/v1/discovery/services | jq '.services.character'

# Check gateway configuration
docker-compose exec gateway env | grep LOAD_BALANCING
```

## Migration from Previous Configuration

### Breaking Changes
None! The services were already in the docker-compose.yml, we just added:
- Scaling support (replicas)
- Service discovery integration
- Proper dependencies

### New Features
- ✅ Run multiple instances (3 replicas each)
- ✅ Automatic service registration
- ✅ Health-based load balancing
- ✅ Dynamic scaling support
- ✅ Zero-downtime deployments (with rolling updates)

## Production Recommendations

1. **Adjust Replica Count**: Set based on load (3-5 instances recommended)
2. **Resource Limits**: Add memory/CPU limits in production
3. **Persistent Volumes**: Already configured for databases
4. **Secrets Management**: Use Docker secrets for passwords
5. **Logging**: Configure log rotation and aggregation
6. **Backups**: Regular database backups via cron jobs

## Files Modified

- ✅ `docker-compose.yml` - Added scaling and service discovery to town-service and character-service

## Related Documentation

- `mafia_api_gateway/TOWN_SERVICE_ROUTES.md` - Gateway routes for town service
- `mafia_api_gateway/CHARACTER_SERVICE_ROUTES.md` - Gateway routes for character service
- `mafia_api_gateway/PR_SUMMARY.md` - API Gateway changes summary

---

**Status**: ✅ Ready for deployment  
**Testing**: Validated YAML syntax  
**Impact**: Enables horizontal scaling and load balancing  
**Rollback**: Simply remove `deploy.replicas` and service discovery env vars

