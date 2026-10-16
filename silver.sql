-- 1. Setup
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE DATABRICK_PROJECT_DB;
CREATE SCHEMA IF NOT EXISTS DIMENSION_MODELS;
USE SCHEMA DATABRICK_PROJECT_DB.DIMENSION_MODELS;

-- 2. Dim_origin
CREATE OR REPLACE TABLE DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_origin (
    origin_sk INT AUTOINCREMENT,
    origin_code VARCHAR(5),
    origin_airport_name VARCHAR(200),
    origin_city VARCHAR(200),
    origin_state VARCHAR(200)
);

INSERT INTO DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_origin
    (origin_code, origin_airport_name, origin_city, origin_state)
SELECT origin_code, MAX(origin_airport_name), MAX(origin_city), MAX(origin_state)
FROM DATABRICK_PROJECT_DB.GOLD_SCHEMA.airport_monthly_performance
GROUP BY origin_code;

-- 3. Dim_Airline
CREATE OR REPLACE TABLE DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_Airline (
    airline_sk INT AUTOINCREMENT,
    airline_code VARCHAR(5)
);

INSERT INTO DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_Airline (airline_code)
SELECT airline_code FROM DATABRICK_PROJECT_DB.GOLD_SCHEMA.delay_cause_analysis
UNION
SELECT reporting_airline FROM DATABRICK_PROJECT_DB.GOLD_SCHEMA.flight_summary_table;

-- 4. Dim_date
CREATE OR REPLACE TABLE DATABRICK_PROJECT_DB.DIMENSION_MODELS.dim_date (
    date_key DATE PRIMARY KEY,
    day_of_week INTEGER,
    day_name VARCHAR(10),
    day_of_month INTEGER,
    day_of_year INTEGER,
    week_of_year INTEGER,
    month_number INTEGER,
    month_name VARCHAR(10),
    quarter INTEGER,
    quarter_name VARCHAR(10),
    year INTEGER,
    is_weekend BOOLEAN,
    month_year VARCHAR(10),
    quarter_year VARCHAR(10),
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO DATABRICK_PROJECT_DB.DIMENSION_MODELS.dim_date
    (date_key, day_of_week, day_name, day_of_month, day_of_year,
     week_of_year, month_number, month_name, quarter, quarter_name,
     year, is_weekend, month_year, quarter_year)
WITH date_generated AS (
    SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY NULL) - 1, '2019-01-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 3000))   -- 2019-01-01 to about 2027-03
)
SELECT
    d,
    EXTRACT(dayofweek FROM d),
    DAYNAME(d),
    DAY(d),
    EXTRACT(dayofyear FROM d),
    EXTRACT(weekofyear FROM d),
    EXTRACT(month FROM d),
    MONTHNAME(d),
    EXTRACT(quarter FROM d),
    'Q' || EXTRACT(quarter FROM d),
    YEAR(d),
    DAYNAME(d) IN ('Sat', 'Sun'),
    MONTHNAME(d) || '-' || YEAR(d),
    'Q' || EXTRACT(quarter FROM d) || '-' || YEAR(d)
FROM date_generated;

-- 5. Fact: airport monthly
CREATE OR REPLACE DYNAMIC TABLE DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airport_year_monthly
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
AS
SELECT
    o.origin_sk,
    DATE_FROM_PARTS(amp.flight_year, amp.flight_month, 1) AS date_key,
    amp.flight_year,
    amp.flight_month,
    amp.origin_lat,
    amp.origin_lon,
    amp.departures,
    amp.cancelled_departures,
    amp.avg_dep_delay,
    amp.dep_on_time_pct,
    amp.avg_airtime,
    amp.avg_route_distance,
    amp.airlines_operating,
    amp.unique_destinations
FROM DATABRICK_PROJECT_DB.GOLD_SCHEMA.airport_monthly_performance amp
JOIN DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_origin o
  ON o.origin_code = amp.origin_code;

CREATE OR REPLACE DYNAMIC TABLE DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airport_year_monthly
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
AS
SELECT
    o.origin_sk,
    amp.* EXCLUDE (origin_code, origin_airport_name, origin_city, origin_state)
FROM DATABRICK_PROJECT_DB.GOLD_SCHEMA.airport_monthly_performance amp
JOIN DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_origin o
  ON o.origin_code = amp.origin_code;


-- 6. Fact: delay cause
CREATE OR REPLACE DYNAMIC TABLE DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airline_delay_cause
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
AS
SELECT
    a.airline_sk,
    DATE_FROM_PARTS(dca.flight_year, dca.flight_month, 1) AS date_key,
    dca.flight_year,
    dca.flight_month,
    dca.delayed_flights,
    dca.total_delay_minutes,
    dca.carrier_delay_min,
    dca.weather_delay_min,
    dca.nas_delay_min,
    dca.security_delay_min,
    dca.late_aircraft_delay_min,
    dca.carrier_pct,
    dca.weather_pct,
    dca.nas_pct,
    dca.security_pct,
    dca.late_aircraft_pct
FROM DATABRICK_PROJECT_DB.GOLD_SCHEMA.delay_cause_analysis dca
JOIN DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_Airline a
  ON a.airline_code = dca.airline_code;

CREATE OR REPLACE DYNAMIC TABLE DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airline_delay_cause
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
AS
SELECT
    a.airline_sk,
    dca.* EXCLUDE (airline_code)
FROM DATABRICK_PROJECT_DB.GOLD_SCHEMA.delay_cause_analysis dca
JOIN DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_Airline a
  ON a.airline_code = dca.airline_code;

CREATE OR REPLACE DYNAMIC TABLE DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airline_delay_cause
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
AS
SELECT
    a.airline_sk,
    dca.* EXCLUDE (airline_code)
FROM DATABRICK_PROJECT_DB.GOLD_SCHEMA.delay_cause_analysis dca
JOIN DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_Airline a
  ON a.airline_code = dca.airline_code;

SELECT * FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airline_delay_cause LIMIT 5;

-- 7. Fact: flight summary
CREATE OR REPLACE DYNAMIC TABLE DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_flight_summary
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
AS
SELECT
    a.airline_sk,
    DATE_FROM_PARTS(fst.year::INT, fst.month::INT, 1) AS date_key,
    fst.year::INT  AS flight_year,
    fst.month::INT AS flight_month,
    fst.* EXCLUDE (year, month, reporting_airline)
FROM DATABRICK_PROJECT_DB.GOLD_SCHEMA.flight_summary_table fst
JOIN DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_Airline a
  ON a.airline_code = fst.reporting_airline;

-- 8. Checks (run last)
SHOW TABLES IN SCHEMA DATABRICK_PROJECT_DB.DIMENSION_MODELS;
SHOW DYNAMIC TABLES IN SCHEMA DATABRICK_PROJECT_DB.DIMENSION_MODELS;

SELECT COUNT(*) FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_origin;
SELECT COUNT(*) FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.Dim_Airline;
SELECT COUNT(*) FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.dim_date;
SELECT COUNT(*) FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airport_year_monthly;
SELECT COUNT(*) FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_airline_delay_cause;
SELECT COUNT(*) FROM DATABRICK_PROJECT_DB.DIMENSION_MODELS.fact_flight_summary;