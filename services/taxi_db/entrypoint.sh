#!/bin/bash
set -e

# Initialize database if it doesn't exist
if [ ! -f /var/lib/duckdb/tripdata.duckdb ]; then
  echo "Initializing DuckDB database..."
  /docker-entrypoint-initdb.d/postgres-init.sh
fi

# Execute the command passed to the container
exec "$@"
