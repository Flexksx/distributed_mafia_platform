"""
Scheduled ETL Runner for Data Warehouse

This script runs the ETL pipeline on a schedule using APScheduler.
It performs incremental loads every 5 minutes and full loads daily.

Usage:
    python scheduler.py

Environment Variables:
    ETL_INTERVAL_MINUTES: Interval between incremental ETL runs (default: 5)
    ETL_FULL_LOAD_HOUR: Hour to run full load (default: 2 = 2 AM)
"""

import os
import signal
import sys
import logging
from datetime import datetime
from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from etl_pipeline import ETLPipeline

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("ETL-Scheduler")

# Configuration
ETL_INTERVAL_MINUTES = int(os.getenv("ETL_INTERVAL_MINUTES", "5"))
ETL_FULL_LOAD_HOUR = int(os.getenv("ETL_FULL_LOAD_HOUR", "2"))


def run_incremental_etl():
    """Run incremental ETL for all sources."""
    logger.info(f"⏰ Scheduled incremental ETL starting at {datetime.utcnow()}")

    try:
        pipeline = ETLPipeline()
        pipeline.run_all(full_load=False)
    except Exception as e:
        logger.error(f"❌ Scheduled ETL failed: {e}")


def run_full_etl():
    """Run full ETL for all sources (daily)."""
    logger.info(f"⏰ Scheduled FULL ETL starting at {datetime.utcnow()}")

    try:
        pipeline = ETLPipeline()
        pipeline.run_all(full_load=True)
    except Exception as e:
        logger.error(f"❌ Scheduled full ETL failed: {e}")


def graceful_shutdown(signum, frame):
    """Handle shutdown signals."""
    logger.info("Received shutdown signal, stopping scheduler...")
    sys.exit(0)


def main():
    logger.info("=" * 60)
    logger.info("🚀 Starting ETL Scheduler")
    logger.info(f"   Incremental ETL every {ETL_INTERVAL_MINUTES} minutes")
    logger.info(f"   Full ETL daily at {ETL_FULL_LOAD_HOUR}:00 UTC")
    logger.info("=" * 60)

    # Handle shutdown gracefully
    signal.signal(signal.SIGTERM, graceful_shutdown)
    signal.signal(signal.SIGINT, graceful_shutdown)

    scheduler = BlockingScheduler()

    # Incremental ETL every N minutes
    scheduler.add_job(
        run_incremental_etl,
        IntervalTrigger(minutes=ETL_INTERVAL_MINUTES),
        id="incremental_etl",
        name="Incremental ETL",
        replace_existing=True,
    )

    # Full ETL daily at specified hour
    scheduler.add_job(
        run_full_etl,
        CronTrigger(hour=ETL_FULL_LOAD_HOUR, minute=0),
        id="full_etl",
        name="Daily Full ETL",
        replace_existing=True,
    )

    # Run initial ETL on startup
    logger.info("Running initial incremental ETL on startup...")
    run_incremental_etl()

    logger.info("Scheduler started. Press Ctrl+C to exit.")

    try:
        scheduler.start()
    except (KeyboardInterrupt, SystemExit):
        logger.info("Scheduler stopped.")


if __name__ == "__main__":
    main()
