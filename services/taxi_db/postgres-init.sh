#!/usr/bin/env python3

import duckdb
import os
import subprocess

DB_FILE = "/var/lib/duckdb/tripdata.duckdb"
TEMP_DIR = "/tmp"

# Ensure directory exists
os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)

# Connect to database
print("Connecting to DuckDB...")
conn = duckdb.connect(DB_FILE)

# Create table
print("Creating table...")
conn.execute("""
  CREATE TABLE IF NOT EXISTS triprecords (
    pickup_datetime    TIMESTAMP,
    dropoff_datetime   TIMESTAMP,
    pickup_locationid  INTEGER,
    dropoff_locationid INTEGER,
    trip_distance      FLOAT8
  );
""")

# List of parquet files to load
urls = [
  "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-01.parquet",
  "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-02.parquet",
  "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-03.parquet",
  "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-11.parquet"
]

# Process each parquet file
for url in urls:
    file = os.path.join(TEMP_DIR, os.path.basename(url))
    print(f"\nDownloading {url}")
    subprocess.run(["wget", "-q", url, "-O", file], check=True)
    
    print(f"Loading into DuckDB...")
    try:
        conn.execute(f"""
            INSERT INTO triprecords
            SELECT
              tpep_pickup_datetime AS pickup_datetime,
              tpep_dropoff_datetime AS dropoff_datetime,
              PULocationID AS pickup_locationid,
              DOLocationID AS dropoff_locationid,
              trip_distance
            FROM read_parquet('{file}')
            WHERE trip_distance > 0;
        """)
        print(f"Successfully loaded {file}")
    except Exception as e:
        print(f"Error loading {file}: {e}")
    finally:
        if os.path.exists(file):
            os.remove(file)

# Create indices
print("\nCreating indices...")
conn.execute("""
  CREATE INDEX IF NOT EXISTS idx_pickup_datetime 
    ON triprecords(pickup_datetime);
  CREATE INDEX IF NOT EXISTS idx_dropoff_datetime 
    ON triprecords(dropoff_datetime);
  CREATE INDEX IF NOT EXISTS idx_pickup_locationid 
    ON triprecords(pickup_locationid);
  CREATE INDEX IF NOT EXISTS idx_dropoff_locationid 
    ON triprecords(dropoff_locationid);
""")

# Display summary statistics
print("\nFetching database statistics...")
result = conn.execute("""
  SELECT 
    COUNT(*) as row_count,
    COUNT(DISTINCT pickup_locationid) as unique_pickup_locations,
    COUNT(DISTINCT dropoff_locationid) as unique_dropoff_locations,
    MIN(trip_distance) as min_distance,
    MAX(trip_distance) as max_distance,
    AVG(trip_distance) as avg_distance
  FROM triprecords;
""").fetchall()

print("\n=== Database Statistics ===")
for row in result:
    print(f"Total Rows: {row[0]:,}")
    print(f"Unique Pickup Locations: {row[1]}")
    print(f"Unique Dropoff Locations: {row[2]}")
    print(f"Min Distance: {row[3]}")
    print(f"Max Distance: {row[4]}")
    print(f"Avg Distance: {row[5]:.2f}")

# Create user
print("\nCreating user...")
conn.execute("CREATE USER IF NOT EXISTS taxi WITH PASSWORD 'ridetlc';")
conn.execute("GRANT SELECT ON triprecords TO taxi;")

conn.close()
print("\n✓ Database initialization complete!")
print(f"Database location: {DB_FILE}")