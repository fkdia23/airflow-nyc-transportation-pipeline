#!/bin/bash

set -eux

# Create database and read-only user expected by taxi_fileserver
psql -v ON_ERROR_STOP=1 <<-EOSQL
  CREATE DATABASE tlctriprecords;
  CREATE USER taxi WITH PASSWORD 'ridetlc';
EOSQL

# Create table
psql -v ON_ERROR_STOP=1 tlctriprecords <<-EOSQL
  CREATE TABLE IF NOT EXISTS triprecords (
    pickup_datetime    TIMESTAMP,
    dropoff_datetime   TIMESTAMP,
    pickup_locationid  INTEGER,
    dropoff_locationid INTEGER,
    trip_distance      FLOAT8
  );
EOSQL

# Load data
urls="
https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-01.parquet
https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-02.parquet
https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-03.parquet
https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-11.parquet
"

parquet=/tmp/tripdata.parquet
csv=/tmp/tripdata.csv

for url in ${urls}; do
  wget -q "${url}" -O "${parquet}"

  # Keep about 1 ride out of 8 to limit disk usage, as citibike_db does
  /opt/duckdb/bin/python -c "
import duckdb
duckdb.sql('''
  COPY (
    SELECT
      tpep_pickup_datetime  AS pickup_datetime,
      tpep_dropoff_datetime AS dropoff_datetime,
      PULocationID          AS pickup_locationid,
      DOLocationID          AS dropoff_locationid,
      trip_distance
    FROM read_parquet('${parquet}') TABLESAMPLE 12.5 PERCENT (bernoulli, 42)
    WHERE trip_distance > 0
  ) TO '${csv}' (HEADER)
''')
"

  psql -v ON_ERROR_STOP=1 tlctriprecords <<-EOSQL
    COPY triprecords FROM '${csv}' DELIMITER ',' CSV HEADER;
EOSQL

  rm -f "${parquet}" "${csv}"
done

# Create indices and grant read access
psql -v ON_ERROR_STOP=1 tlctriprecords <<-EOSQL
  CREATE INDEX ON triprecords(pickup_datetime);
  CREATE INDEX ON triprecords(dropoff_datetime);
  CREATE INDEX ON triprecords(pickup_locationid);
  CREATE INDEX ON triprecords(dropoff_locationid);
  GRANT SELECT ON triprecords TO taxi;
EOSQL
