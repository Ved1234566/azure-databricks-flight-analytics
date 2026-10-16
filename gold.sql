-- 1. Setup
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE DATABRICK_PROJECT_DB;
CREATE SCHEMA IF NOT EXISTS VIEWS_SCHEMA;
USE SCHEMA DATABRICK_PROJECT_DB.VIEWS_SCHEMA;

CREATE OR REPLACE VIEW vw_airline_performance AS
WITH summary AS (
    SELECT airline_sk, flight_year,
           SUM(total_flights)       AS total_flights,
           SUM(cancelled_flights)   AS total_cancelled,
           AVG(on_time_percentage)  AS avg_on_time_pct
    FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_flight_summary
    GROUP BY airline_sk, flight_year
),
delays AS (
    SELECT airline_sk, flight_year,
           SUM(total_delay_minutes) AS total_delay_minutes
    FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airline_delay_cause
    GROUP BY airline_sk, flight_year
)
SELECT
    s.flight_year,
    da.airline_code,
    s.total_flights,
    s.total_cancelled,
    s.avg_on_time_pct,
    d.total_delay_minutes
FROM summary s
JOIN DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_Airline da ON da.airline_sk = s.airline_sk
LEFT JOIN delays d ON d.airline_sk = s.airline_sk AND d.flight_year = s.flight_year;

-- 3. Delay trend (per airline, per month)
CREATE OR REPLACE VIEW vw_delay_trend_monthly AS
WITH summary AS (
    SELECT airline_sk, flight_year, flight_month,
           AVG(on_time_percentage) AS avg_on_time_pct
    FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_flight_summary
    GROUP BY airline_sk, flight_year, flight_month
),
delays AS (
    SELECT airline_sk, flight_year, flight_month,
           AVG(total_delay_minutes) AS avg_delay_min
    FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airline_delay_cause
    GROUP BY airline_sk, flight_year, flight_month
)
SELECT
    s.flight_year || '-' || LPAD(s.flight_month::VARCHAR, 2, '0') AS year_month,
    da.airline_code,
    s.avg_on_time_pct,
    d.avg_delay_min
FROM summary s
JOIN DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_Airline da ON da.airline_sk = s.airline_sk
LEFT JOIN delays d
  ON d.airline_sk = s.airline_sk
 AND d.flight_year = s.flight_year
 AND d.flight_month = s.flight_month;

-- 4. Airport map
CREATE OR REPLACE VIEW vw_airport_performance_map AS
SELECT
    o.origin_code,
    o.origin_airport_name,
    o.origin_city,
    o.origin_state,
    f.*  EXCLUDE (origin_sk)
FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airport_year_monthly f
JOIN DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_origin o ON o.origin_sk = f.origin_sk;

-- 5. Checks (run last)
SELECT * FROM vw_airline_performance;
SELECT * FROM vw_delay_trend_monthly;
SELECT * FROM vw_airport_performance_map;