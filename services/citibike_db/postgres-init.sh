#!/bin/bash

set -eux

# Create database
psql -v ON_ERROR_STOP=1 <<-EOSQL
  CREATE DATABASE citibike;
EOSQL

# Create table
psql -v ON_ERROR_STOP=1 citibike <<-EOSQL
  CREATE TABLE IF NOT EXISTS tripdata (
    tripduration            INTEGER,
    starttime               TIMESTAMP,
    stoptime                TIMESTAMP,
    start_station_id        INTEGER,
    start_station_name      VARCHAR(100),
    start_station_latitude  FLOAT8,
    start_station_longitude FLOAT8,
    end_station_id          INTEGER,
    end_station_name        VARCHAR(100),
    end_station_latitude    FLOAT8,
    end_station_longitude   FLOAT8
  );
EOSQL

# Load data
# New York rides are now only published as one yearly archive of monthly CSV files.
# The JC-* files cover Jersey City, which lies outside the NYC taxi zones.
archive=/tmp/citibike-tripdata.zip
wget -q https://s3.amazonaws.com/tripdata/2019-citibike-tripdata.zip -O "${archive}"

for filename in $(unzip -Z1 "${archive}" | grep -E '^2019-citibike-tripdata/.*\.csv$'); do
  # Keep header + every 8th line, extract first 11 columns, exclude NULLs
  # NF == 15 drops the rare lines with a comma inside a quoted value
  # Some months write station ids as floats (3507.0), which COPY rejects for INTEGER
  unzip -p "${archive}" "${filename}" \
    | awk -F',' 'NF == 15 && (NR == 1 || NR % 8 == 0) {sub(/\.0$/, "", $4); sub(/\.0$/, "", $8); print $1","$2","$3","$4","$5","$6","$7","$8","$9","$10","$11}' \
    | grep -v "NULL" > /tmp/citibike-tripdata.csv

  psql -v ON_ERROR_STOP=1 citibike <<-EOSQL
    COPY tripdata
    FROM '/tmp/citibike-tripdata.csv' DELIMITER ',' CSV HEADER;
EOSQL

  rm -f /tmp/citibike-tripdata.csv
done

rm -f "${archive}"

# Create user and grant privileges
# FIX: split into two psql calls — \c does not work inside a heredoc
psql -v ON_ERROR_STOP=1 <<-EOSQL
  CREATE USER citi WITH PASSWORD 'cycling';
  GRANT ALL PRIVILEGES ON DATABASE citibike TO citi;
EOSQL

psql -v ON_ERROR_STOP=1 citibike <<-EOSQL
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO citi;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO citi;
EOSQL