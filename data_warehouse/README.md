# Data Warehouse for Mafia Platform

This module provides a centralized data warehouse for analytics and reporting across all Mafia Platform services.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│  User Service   │    │  Game Service   │
│   PostgreSQL    │    │   PostgreSQL    │
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
         └───────────────────────┘
```

## Features

- **Star Schema**: Optimized for analytical queries with dimension and fact tables
- **Incremental ETL**: Extracts only changed data since last run
- **Scheduled Sync**: Runs every 5 minutes by default
- **Full Load**: Daily full sync at 2 AM UTC
- **ETL Logging**: Tracks all ETL runs for monitoring

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

### Start the Data Warehouse

```bash
cd data_warehouse
docker-compose up -d
```

### Run Manual ETL

```bash
# Full load
docker-compose exec etl-service python etl_pipeline.py --all --full-load

# Incremental load
docker-compose exec etl-service python etl_pipeline.py --all

# Specific source
docker-compose exec etl-service python etl_pipeline.py --source user_service
```

### Query the Warehouse

```bash
docker-compose exec data-warehouse-db psql -U warehouse -d mafia_warehouse
```

Example queries:

```sql
-- Total games by lobby
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
