"""
ETL Pipeline for Mafia Platform Data Warehouse

This module provides Extract-Transform-Load functionality to sync data
from operational databases (User Management, Game Service) to the data warehouse.

Features:
1. Incremental extraction based on timestamps
2. Transformation for dimensional modeling
3. Idempotent loading with conflict handling
4. Detailed logging for monitoring
5. Scheduled execution support

Usage:
    python etl_pipeline.py --source user_service --full-load
    python etl_pipeline.py --source game_service --incremental
    python etl_pipeline.py --all
"""

import os
import sys
import argparse
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import psycopg2
from psycopg2.extras import RealDictCursor, execute_batch

# Configure logging - create log directory if it doesn't exist
LOG_DIR = "/var/log/etl"
os.makedirs(LOG_DIR, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(os.path.join(LOG_DIR, "etl_pipeline.log"), mode="a"),
    ],
)
logger = logging.getLogger("ETL")

# Database connection configurations
DB_CONFIGS = {
    "user_service": {
        "host": os.getenv("USER_SERVICE_DB_HOST", "user-management-db"),
        "port": int(os.getenv("USER_SERVICE_DB_PORT", 5432)),
        "database": os.getenv("USER_SERVICE_DB_NAME", "mafia_users"),
        "user": os.getenv("USER_SERVICE_DB_USER", "mafia_user"),
        "password": os.getenv("USER_SERVICE_DB_PASSWORD", "mafia_secure_password"),
    },
    "game_service": {
        "host": os.getenv("GAME_SERVICE_DB_HOST", "game-service-db"),
        "port": int(os.getenv("GAME_SERVICE_DB_PORT", 5432)),
        "database": os.getenv("GAME_SERVICE_DB_NAME", "mafia_game"),
        "user": os.getenv("GAME_SERVICE_DB_USER", "mafia_game_user"),
        "password": os.getenv("GAME_SERVICE_DB_PASSWORD", "mafia_game_secure_password"),
    },
    "warehouse": {
        "host": os.getenv("WAREHOUSE_DB_HOST", "data-warehouse-db"),
        "port": int(os.getenv("WAREHOUSE_DB_PORT", 5432)),
        "database": os.getenv("WAREHOUSE_DB_NAME", "mafia_warehouse"),
        "user": os.getenv("WAREHOUSE_DB_USER", "warehouse"),
        "password": os.getenv("WAREHOUSE_DB_PASSWORD", "warehouse"),
    },
}


class ETLPipeline:
    """Main ETL Pipeline class for data warehouse sync."""

    def __init__(self):
        self.warehouse_conn = None
        self.source_conns: Dict[str, Any] = {}

    def connect_warehouse(self):
        """Establish connection to data warehouse."""
        try:
            self.warehouse_conn = psycopg2.connect(**DB_CONFIGS["warehouse"])
            logger.info("✅ Connected to data warehouse")
        except Exception as e:
            logger.error(f"❌ Failed to connect to warehouse: {e}")
            raise

    def connect_source(self, source_name: str):
        """Establish connection to a source database."""
        if source_name not in DB_CONFIGS:
            raise ValueError(f"Unknown source: {source_name}")

        try:
            conn = psycopg2.connect(**DB_CONFIGS[source_name])
            self.source_conns[source_name] = conn
            logger.info(f"✅ Connected to {source_name} database")
        except Exception as e:
            logger.error(f"❌ Failed to connect to {source_name}: {e}")
            raise

    def close_connections(self):
        """Close all database connections."""
        if self.warehouse_conn:
            self.warehouse_conn.close()
        for conn in self.source_conns.values():
            conn.close()
        logger.info("All connections closed")

    def get_last_etl_timestamp(self, source: str, table: str) -> Optional[datetime]:
        """Get the last successful ETL timestamp for incremental loads."""
        with self.warehouse_conn.cursor() as cur:
            cur.execute(
                """
                SELECT last_extracted_timestamp 
                FROM etl_run_log 
                WHERE source_system = %s AND table_name = %s AND status = 'success'
                ORDER BY run_end_time DESC 
                LIMIT 1
            """,
                (source, table),
            )
            result = cur.fetchone()
            return result[0] if result else None

    def log_etl_start(self, source: str, table: str) -> int:
        """Log the start of an ETL run."""
        with self.warehouse_conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO etl_run_log (source_system, table_name, run_start_time, status)
                VALUES (%s, %s, %s, 'running')
                RETURNING run_id
            """,
                (source, table, datetime.utcnow()),
            )
            run_id = cur.fetchone()[0]
            self.warehouse_conn.commit()
            return run_id

    def log_etl_end(
        self,
        run_id: int,
        records_extracted: int,
        records_loaded: int,
        status: str,
        last_timestamp: Optional[datetime] = None,
        error: str = None,
    ):
        """Log the end of an ETL run."""
        with self.warehouse_conn.cursor() as cur:
            cur.execute(
                """
                UPDATE etl_run_log 
                SET run_end_time = %s, records_extracted = %s, records_loaded = %s,
                    status = %s, last_extracted_timestamp = %s, error_message = %s
                WHERE run_id = %s
            """,
                (
                    datetime.utcnow(),
                    records_extracted,
                    records_loaded,
                    status,
                    last_timestamp,
                    error,
                    run_id,
                ),
            )
            self.warehouse_conn.commit()

    # =========================================
    # USER SERVICE ETL
    # =========================================

    def extract_users(self, since: Optional[datetime] = None) -> List[Dict]:
        """Extract users from user management service."""
        conn = self.source_conns.get("user_service")
        if not conn:
            raise ValueError("User service not connected")

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            if since:
                cur.execute(
                    """
                    SELECT id, username, email, "createdAt", "updatedAt"
                    FROM "User"
                    WHERE "updatedAt" > %s
                    ORDER BY "updatedAt"
                """,
                    (since,),
                )
            else:
                cur.execute("""
                    SELECT id, username, email, "createdAt", "updatedAt"
                    FROM "User"
                    ORDER BY "createdAt"
                """)

            users = cur.fetchall()
            logger.info(f"📤 Extracted {len(users)} users from user_service")
            return [dict(u) for u in users]

    def load_users(self, users: List[Dict]) -> int:
        """Load users into dimension table."""
        if not users:
            return 0

        with self.warehouse_conn.cursor() as cur:
            insert_sql = """
                INSERT INTO dim_users (user_id, username, email, created_at, last_updated)
                VALUES (%(id)s, %(username)s, %(email)s, %(createdAt)s, %(updatedAt)s)
                ON CONFLICT (user_id) DO UPDATE SET
                    username = EXCLUDED.username,
                    email = EXCLUDED.email,
                    last_updated = EXCLUDED.last_updated
            """
            execute_batch(cur, insert_sql, users, page_size=100)
            self.warehouse_conn.commit()

        logger.info(f"📥 Loaded {len(users)} users to warehouse")
        return len(users)

    def extract_transactions(self, since: Optional[datetime] = None) -> List[Dict]:
        """Extract currency transactions from user management service."""
        conn = self.source_conns.get("user_service")
        if not conn:
            raise ValueError("User service not connected")

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            if since:
                cur.execute(
                    """
                    SELECT id, "userId", type, amount, description, "createdAt"
                    FROM "CurrencyTransaction"
                    WHERE "createdAt" > %s
                    ORDER BY "createdAt"
                """,
                    (since,),
                )
            else:
                cur.execute("""
                    SELECT id, "userId", type, amount, description, "createdAt"
                    FROM "CurrencyTransaction"
                    ORDER BY "createdAt"
                """)

            transactions = cur.fetchall()
            logger.info(
                f"📤 Extracted {len(transactions)} transactions from user_service"
            )
            return [dict(t) for t in transactions]

    def load_transactions(self, transactions: List[Dict]) -> int:
        """Load transactions into fact table."""
        if not transactions:
            return 0

        # Transform to warehouse schema
        transformed = []
        for t in transactions:
            transformed.append(
                {
                    "user_id": t["userId"],
                    "transaction_type": t["type"],
                    "amount": t["amount"],
                    "description": t.get("description"),
                    "occurred_at": t["createdAt"],
                }
            )

        with self.warehouse_conn.cursor() as cur:
            insert_sql = """
                INSERT INTO fact_transactions 
                    (user_id, transaction_type, amount, description, occurred_at, source_system)
                VALUES (%(user_id)s, %(transaction_type)s, %(amount)s, %(description)s, 
                        %(occurred_at)s, 'user_service')
            """
            execute_batch(cur, insert_sql, transformed, page_size=100)
            self.warehouse_conn.commit()

        logger.info(f"📥 Loaded {len(transformed)} transactions to warehouse")
        return len(transformed)

    # =========================================
    # GAME SERVICE ETL
    # =========================================

    def extract_lobbies(self, since: Optional[datetime] = None) -> List[Dict]:
        """Extract lobbies from game service."""
        conn = self.source_conns.get("game_service")
        if not conn:
            raise ValueError("Game service not connected")

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            if since:
                cur.execute(
                    """
                    SELECT id, name, "maxPlayers", status, "createdAt", "updatedAt"
                    FROM "Lobby"
                    WHERE "updatedAt" > %s
                    ORDER BY "updatedAt"
                """,
                    (since,),
                )
            else:
                cur.execute("""
                    SELECT id, name, "maxPlayers", status, "createdAt", "updatedAt"
                    FROM "Lobby"
                    ORDER BY "createdAt"
                """)

            lobbies = cur.fetchall()
            logger.info(f"📤 Extracted {len(lobbies)} lobbies from game_service")
            return [dict(l) for l in lobbies]

    def load_lobbies(self, lobbies: List[Dict]) -> int:
        """Load lobbies into dimension table."""
        if not lobbies:
            return 0

        with self.warehouse_conn.cursor() as cur:
            insert_sql = """
                INSERT INTO dim_lobbies (lobby_id, lobby_name, max_players, created_at, last_updated)
                VALUES (%(id)s, %(name)s, %(maxPlayers)s, %(createdAt)s, %(updatedAt)s)
                ON CONFLICT (lobby_id) DO UPDATE SET
                    lobby_name = EXCLUDED.lobby_name,
                    max_players = EXCLUDED.max_players,
                    last_updated = EXCLUDED.last_updated
            """
            execute_batch(cur, insert_sql, lobbies, page_size=100)
            self.warehouse_conn.commit()

        logger.info(f"📥 Loaded {len(lobbies)} lobbies to warehouse")
        return len(lobbies)

    def extract_player_sessions(self, since: Optional[datetime] = None) -> List[Dict]:
        """Extract player sessions (lobby players) from game service."""
        conn = self.source_conns.get("game_service")
        if not conn:
            raise ValueError("Game service not connected")

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            if since:
                cur.execute(
                    """
                    SELECT id, "lobbyId", "userId", role, "joinedAt", "isAlive", "isActive", "updatedAt"
                    FROM "LobbyPlayer"
                    WHERE "updatedAt" > %s
                    ORDER BY "updatedAt"
                """,
                    (since,),
                )
            else:
                cur.execute("""
                    SELECT id, "lobbyId", "userId", role, "joinedAt", "isAlive", "isActive", "updatedAt"
                    FROM "LobbyPlayer"
                    ORDER BY "joinedAt"
                """)

            sessions = cur.fetchall()
            logger.info(
                f"📤 Extracted {len(sessions)} player sessions from game_service"
            )
            return [dict(s) for s in sessions]

    def load_player_sessions(self, sessions: List[Dict]) -> int:
        """Load player sessions into fact table."""
        if not sessions:
            return 0

        # Transform to warehouse schema
        transformed = []
        for s in sessions:
            transformed.append(
                {
                    "user_id": s["userId"],
                    "lobby_id": s["lobbyId"],
                    "role_assigned": s.get("role"),
                    "joined_at": s["joinedAt"],
                    "survived_until_end": s.get("isAlive", False),
                }
            )

        with self.warehouse_conn.cursor() as cur:
            insert_sql = """
                INSERT INTO fact_player_sessions 
                    (user_id, lobby_id, role_assigned, joined_at, survived_until_end)
                VALUES (%(user_id)s, %(lobby_id)s, %(role_assigned)s, %(joined_at)s, %(survived_until_end)s)
            """
            execute_batch(cur, insert_sql, transformed, page_size=100)
            self.warehouse_conn.commit()

        logger.info(f"📥 Loaded {len(transformed)} player sessions to warehouse")
        return len(transformed)

    # =========================================
    # ORCHESTRATION
    # =========================================

    def run_user_service_etl(self, full_load: bool = False):
        """Run ETL for user management service."""
        logger.info("🚀 Starting User Service ETL...")

        # Connect to source
        self.connect_source("user_service")

        # Users ETL
        run_id = self.log_etl_start("user_service", "dim_users")
        try:
            since = (
                None
                if full_load
                else self.get_last_etl_timestamp("user_service", "dim_users")
            )
            users = self.extract_users(since)
            loaded = self.load_users(users)
            last_ts = users[-1]["updatedAt"] if users else datetime.utcnow()
            self.log_etl_end(run_id, len(users), loaded, "success", last_ts)
        except Exception as e:
            logger.error(f"❌ User ETL failed: {e}")
            self.log_etl_end(run_id, 0, 0, "failed", error=str(e))

        # Transactions ETL
        run_id = self.log_etl_start("user_service", "fact_transactions")
        try:
            since = (
                None
                if full_load
                else self.get_last_etl_timestamp("user_service", "fact_transactions")
            )
            transactions = self.extract_transactions(since)
            loaded = self.load_transactions(transactions)
            last_ts = (
                transactions[-1]["createdAt"] if transactions else datetime.utcnow()
            )
            self.log_etl_end(run_id, len(transactions), loaded, "success", last_ts)
        except Exception as e:
            logger.error(f"❌ Transactions ETL failed: {e}")
            self.log_etl_end(run_id, 0, 0, "failed", error=str(e))

        logger.info("✅ User Service ETL completed")

    def run_game_service_etl(self, full_load: bool = False):
        """Run ETL for game service."""
        logger.info("🚀 Starting Game Service ETL...")

        # Connect to source
        self.connect_source("game_service")

        # Lobbies ETL
        run_id = self.log_etl_start("game_service", "dim_lobbies")
        try:
            since = (
                None
                if full_load
                else self.get_last_etl_timestamp("game_service", "dim_lobbies")
            )
            lobbies = self.extract_lobbies(since)
            loaded = self.load_lobbies(lobbies)
            last_ts = lobbies[-1]["updatedAt"] if lobbies else datetime.utcnow()
            self.log_etl_end(run_id, len(lobbies), loaded, "success", last_ts)
        except Exception as e:
            logger.error(f"❌ Lobbies ETL failed: {e}")
            self.log_etl_end(run_id, 0, 0, "failed", error=str(e))

        # Player Sessions ETL
        run_id = self.log_etl_start("game_service", "fact_player_sessions")
        try:
            since = (
                None
                if full_load
                else self.get_last_etl_timestamp("game_service", "fact_player_sessions")
            )
            sessions = self.extract_player_sessions(since)
            loaded = self.load_player_sessions(sessions)
            last_ts = sessions[-1]["updatedAt"] if sessions else datetime.utcnow()
            self.log_etl_end(run_id, len(sessions), loaded, "success", last_ts)
        except Exception as e:
            logger.error(f"❌ Player Sessions ETL failed: {e}")
            self.log_etl_end(run_id, 0, 0, "failed", error=str(e))

        logger.info("✅ Game Service ETL completed")

    def run_all(self, full_load: bool = False):
        """Run ETL for all sources."""
        logger.info("=" * 60)
        logger.info(f"🏁 Starting full ETL pipeline (full_load={full_load})")
        logger.info("=" * 60)

        self.connect_warehouse()

        try:
            self.run_user_service_etl(full_load)
            self.run_game_service_etl(full_load)
        finally:
            self.close_connections()

        logger.info("=" * 60)
        logger.info("🎉 ETL pipeline completed successfully")
        logger.info("=" * 60)


def main():
    parser = argparse.ArgumentParser(description="Mafia Platform Data Warehouse ETL")
    parser.add_argument(
        "--source",
        choices=["user_service", "game_service", "all"],
        default="all",
        help="Source to extract from",
    )
    parser.add_argument(
        "--full-load",
        action="store_true",
        help="Perform full load instead of incremental",
    )

    args = parser.parse_args()

    pipeline = ETLPipeline()

    if args.source == "all":
        pipeline.run_all(args.full_load)
    elif args.source == "user_service":
        pipeline.connect_warehouse()
        try:
            pipeline.run_user_service_etl(args.full_load)
        finally:
            pipeline.close_connections()
    elif args.source == "game_service":
        pipeline.connect_warehouse()
        try:
            pipeline.run_game_service_etl(args.full_load)
        finally:
            pipeline.close_connections()


if __name__ == "__main__":
    main()
