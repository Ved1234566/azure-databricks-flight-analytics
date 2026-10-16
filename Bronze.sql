-- 1. Setup
USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WITH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
CREATE DATABASE IF NOT EXISTS DATABRICK_PROJECT_DB;
CREATE SCHEMA IF NOT EXISTS DATABRICK_PROJECT_DB.GOLD_SCHEMA;

USE WAREHOUSE COMPUTE_WH;
USE DATABASE DATABRICK_PROJECT_DB;
USE SCHEMA GOLD_SCHEMA;

-- 2. Tables
CREATE TABLE IF NOT EXISTS delay_cause_analysis (
    flight_year INT,
    flight_month INT,
    airline_code VARCHAR(3),
    delayed_flights BIGINT,
    total_delay_minutes FLOAT,
    carrier_delay_min FLOAT,
    weather_delay_min FLOAT,
    nas_delay_min FLOAT,
    security_delay_min FLOAT,
    late_aircraft_delay_min FLOAT,
    carrier_pct FLOAT,
    weather_pct FLOAT,
    nas_pct FLOAT,
    security_pct FLOAT,
    late_aircraft_pct FLOAT,
    gold_processed_ts TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS airport_monthly_performance (
    flight_year INT,
    flight_month INT,
    year_month VARCHAR(7),
    airport_code VARCHAR(5),
    origin_code VARCHAR(3),
    origin_airport_name VARCHAR(200),
    origin_city VARCHAR(100),
    origin_state VARCHAR(100),
    origin_lat FLOAT,
    origin_lon FLOAT,
    departures BIGINT,
    cancelled_departures BIGINT,
    avg_dep_delay FLOAT,
    dep_on_time_pct FLOAT,
    avg_airtime FLOAT,
    avg_route_distance FLOAT,
    airlines_operating INT,
    unique_destinations INT,
    gold_processed_ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS flight_summary_table (
    flight_year INT,
    flight_month INT,
    airline_code VARCHAR,
    total_flights NUMBER,
    total_diverted NUMBER,
    total_cancelled NUMBER,
    average_delay FLOAT,
    on_time_percentage FLOAT,
    carrierdelay_percentage FLOAT,
    weatherdelay_percentage FLOAT,
    nasdelay_percentage FLOAT,
    securitydelay_percentage FLOAT,
    lateaircraftdelay_percentage FLOAT
);

CREATE TABLE IF NOT EXISTS route_based_insights (
    flight_year INT,
    route VARCHAR,
    total_flights NUMBER,
    avg_dep_delay FLOAT,
    avg_arr_delay FLOAT,
    total_cancelled NUMBER,
    avg_distance FLOAT
);

-- 3. Check
SHOW TABLES;

-- 4. Run these AFTER the Databricks load
SELECT * FROM delay_cause_analysis;
SELECT * FROM airport_monthly_performance;
SELECT * FROM flight_summary_table;
SELECT * FROM route_based_insights;