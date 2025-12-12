# Data Warehouse for Mafia Platform

This module provides a centralized data warehouse for analytics and reporting across all Mafia Platform services.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│  User Service   │    │  Game Service   │
│   PostgreSQL    │    │   PostgreSQL    │
│(user-management │    │ (game-service   │
│      -db)       │    │      -db)       │
└────────┬────────┘    └────────┬────────┘
         │                      │
         │     ┌────────────┐   │
         └────►│ ETL Service│◄──┘
               │ (Python)   │
               └─────┬──────┘
                     │
                     ▼
         ┌───────────────────────┐
         │   Data Warehouse      │
         │     PostgreSQL        │
         │  (Star Schema)        │
         │  Port: 5440           │
         └───────────────────────┘
```

## Features

- **Star Schema**: Optimized for analytical queries with dimension and fact tables
- **Incremental ETL**: Extracts only changed data since last run
- **Scheduled Sync**: Runs every 5 minutes by default
- **Full Load**: Daily full sync at 2 AM UTC
- **ETL Logging**: Tracks all ETL runs for monitoring

## Integration with Root Docker Compose

The data warehouse is integrated into the main `docker-compose.yml` in the project root. It will automatically:
1. Start a PostgreSQL database for the warehouse (port 5440)
2. Start the ETL service that syncs data from User and Game services
3. Wait for source databases to be healthy before starting ETL

### Start with the Platform

```bash
# From the project root
docker compose up -d data-warehouse-db etl-service
```

### View ETL Logs

```bash
docker compose logs -f etl-service
```

## Schema Overview

### Dimension Tables
- `dim_users`: User information (SCD Type 2)
- `dim_lobbies`: Game lobby information
- `dim_roles`: Game roles (Mafia, Citizen, etc.)
- `dim_time`: Pre-populated time dimension for date analytics

### Fact Tables
- `fact_games`: Completed game metrics
- `fact_player_sessions`: Player participation per game
- `fact_transactions`: Currency transactions
- `fact_access_events`: Login/logout events
- `fact_game_actions`: In-game actions (votes, kills)

## Usage

### Run Manual ETL

```bash
# Full load (all sources)
docker compose exec etl-service python etl_pipeline.py --all --full-load

# Incremental load
docker compose exec etl-service python etl_pipeline.py --all

# Specific source only
docker compose exec etl-service python etl_pipeline.py --source user_service
docker compose exec etl-service python etl_pipeline.py --source game_service
```

### Query the Warehouse

```bash
# Connect to the warehouse database
docker compose exec data-warehouse-db psql -U warehouse -d mafia_warehouse
```

Example queries:

```sql
-- Check ETL run history
SELECT * FROM etl_run_log ORDER BY run_start_time DESC LIMIT 10;

-- Count users synced
SELECT COUNT(*) FROM dim_users;

-- Count lobbies synced
SELECT COUNT(*) FROM dim_lobbies;
SELECT l.lobby_name, COUNT(g.game_id) as total_games
FROM fact_games g
JOIN dim_lobbies l ON g.lobby_id = l.lobby_id
GROUP BY l.lobby_name
ORDER BY total_games DESC;

-- User activity summary
SELECT u.username, 
       COUNT(DISTINCT s.lobby_id) as lobbies_joined,
       SUM(t.amount) as total_transactions
FROM dim_users u
LEFT JOIN fact_player_sessions s ON u.user_id = s.user_id
LEFT JOIN fact_transactions t ON u.user_id = t.user_id
GROUP BY u.user_id, u.username;
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ETL_INTERVAL_MINUTES` | 5 | Interval between incremental ETL runs |
| `ETL_FULL_LOAD_HOUR` | 2 | Hour (UTC) for daily full load |
| `WAREHOUSE_DB_HOST` | data-warehouse-db | Warehouse database host |
| `USER_SERVICE_DB_HOST` | user-db-primary | User service database host |
| `GAME_SERVICE_DB_HOST` | game-db-primary | Game service database host |

## Monitoring

Check ETL run history:

```sql
SELECT source_system, table_name, status, 
       records_extracted, records_loaded,
       run_start_time, run_end_time
FROM etl_run_log
ORDER BY run_start_time DESC
LIMIT 10;
```
