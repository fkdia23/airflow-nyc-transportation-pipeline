FROM python:3.11-slim

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install DuckDB Python package
RUN pip install --no-cache-dir duckdb

# Create directories for DuckDB database
RUN mkdir -p /var/lib/duckdb /data

# Copy initialization script and entrypoint
COPY postgres-init.sh /docker-entrypoint-initdb.d/postgres-init.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /docker-entrypoint-initdb.d/postgres-init.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["sleep", "infinity"]