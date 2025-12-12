FROM python:3.11-slim

WORKDIR /app

# Create log directory
RUN mkdir -p /var/log/etl

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY schema.sql .
COPY etl_pipeline.py .
COPY scheduler.py .

# Default command runs the scheduler
CMD ["python", "scheduler.py"]
