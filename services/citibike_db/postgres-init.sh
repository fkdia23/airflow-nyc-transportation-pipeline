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
urls="
https://s3.amazonaws.com/tripdata/JC-201901-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201902-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201903-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201904-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201905-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201906-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201907-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201908-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201909-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201910-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201911-citibike-tripdata.csv.zip
https://s3.amazonaws.com/tripdata/JC-201912-citibike-tripdata.csv.zip
"

for url in ${urls}; do
  wget "${url}" -O /tmp/citibike-tripdata.csv.zip
  unzip -o /tmp/citibike-tripdata.csv.zip -d /tmp

  # Filename of unzipped CSV matches the zip name without .zip
  filename=$(echo "${url}" | sed 's:.*/::' | sed 's/\.zip$//')

  # Keep header + every 8th line, extract first 11 columns, exclude NULLs
  # (reduces image size: full data ~4.18GB → ~890MB)
  time awk -F',' 'NR == 1 || NR % 8 == 0 {print $1","$2","$3","$4","$5","$6","$7","$8","$9","$10","$11}' \
    "/tmp/${filename}" | grep -v "NULL" > /tmp/citibike-tripdata.csv

  time psql -v ON_ERROR_STOP=1 citibike <<-EOSQL
    COPY tripdata
    FROM '/tmp/citibike-tripdata.csv' DELIMITER ',' CSV HEADER;
EOSQL

  # Cleanup temp files to keep image size small
  rm -f /tmp/citibike-tripdata.csv.zip "/tmp/${filename}" /tmp/citibike-tripdata.csv
done

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