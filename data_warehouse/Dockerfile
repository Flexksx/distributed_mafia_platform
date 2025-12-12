FROM python:3.11-slim

WORKDIR /app

# Create log directory with proper permissions
RUN mkdir -p /var/log/etl && chmod 777 /var/log/etl

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY schema.sql .
COPY etl_pipeline.py .
COPY scheduler.py .

# Healthcheck - verify Python process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f "python scheduler.py" || exit 1

# Default command runs the scheduler
CMD ["python", "-u", "scheduler.py"]
