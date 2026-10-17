# Flight Analytics Data Engineering Pipeline

An end-to-end data engineering project that ingests US flight performance data, processes it through a **Bronze → Silver → Gold** Medallion architecture on Azure Databricks, loads the results into Snowflake, models them as a star schema, and serves Power BI dashboards.

![Azure](https://img.shields.io/badge/Azure-ADLS%20Gen2-0078D4)
![Databricks](https://img.shields.io/badge/Databricks-PySpark%20%7C%20Delta%20Lake-FF3621)
![Snowflake](https://img.shields.io/badge/Snowflake-Data%20Warehouse-29B5E8)
![Power BI](https://img.shields.io/badge/Power%20BI-Dashboards-F2C811)
![Uploading image.png…]()

---

## Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Data Sources](#data-sources)
- [Azure Setup and Security](#azure-setup-and-security)
- [Medallion Layers](#medallion-layers)
- [Gold Datasets](#gold-datasets)
- [Snowflake Data Model](#snowflake-data-model)
- [Power BI Views](#power-bi-views)
- [Repository Structure](#repository-structure)
- [How to Run](#how-to-run)
- [Challenges and Fixes](#challenges-and-fixes)
- [Key Learnings](#key-learnings)
- [Future Improvements](#future-improvements)

---

## Project Overview

**Goal:** analyse flight delays, cancellations, on-time performance and route efficiency.

**What the pipeline does**
- Ingests raw flight CSV and airport JSON files from Azure Data Lake Storage Gen2
- Cleans, validates and enriches the data with PySpark
- Stores each layer as Delta tables
- Aggregates the data into 4 analytical Gold datasets
- Loads the Gold datasets into Snowflake
- Builds dimension tables, fact tables and reporting views
- Feeds Power BI dashboards

---

## Architecture

```
 Landing (CSV + JSON)
        │
        ▼
 ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
 │    BRONZE     │ → │    SILVER     │ → │     GOLD      │
 │ ingest + DQ   │   │ clean + enrich│   │ aggregations  │
 │ flags         │   │               │   │ (4 datasets)  │
 └───────────────┘   └───────────────┘   └───────┬───────┘
        Azure Data Lake Storage Gen2 (Delta)      │
                                                  ▼
                                    ┌──────────────────────────┐
                                    │        SNOWFLAKE         │
                                    │ GOLD_SCHEMA              │
                                    │ DIMENSION_MODELS         │
                                    │ VIEWS_SCHEMA             │
                                    └────────────┬─────────────┘
                                                 ▼
                                             Power BI
```

> Add your own diagram image here: `![Architecture](images/architecture.png)`

---

## Tech Stack

| Area | Tools |
|---|---|
| Storage | Azure Data Lake Storage Gen2 |
| Processing | Azure Databricks, PySpark, Delta Lake |
| Governance and access | Unity Catalog, Access Connector (managed identity), Azure RBAC |
| Warehouse | Snowflake (tables, dynamic tables, views) |
| Reporting | Power BI |
| Languages | Python, SQL |

---

## Data Sources

- **Flight data:** US On-Time Reporting Carrier On-Time Performance (CSV). The notebooks read the April 2022 file.
- **Airport data:** `airports.json` with IATA code, city, country, latitude, longitude, altitude and timezone.

---

## Azure Setup and Security

- Azure **Resource Group** holding the storage account and Databricks workspace
- ADLS Gen2 storage account with a container for the Landing, Silver and Gold data
- **Databricks Access Connector** using a managed identity
- **Azure RBAC:** *Storage Blob Data Contributor* assigned to the managed identity
- **Unity Catalog:** storage credential and external location, so Databricks reads and writes storage without account keys in code
- Snowflake password is entered through a Databricks widget (or a secret scope), never stored in the notebook

---

## Medallion Layers

### Bronze: ingestion and data quality flags

- Read all CSV files from the Landing folder with header and schema inference
- Detect the latest file with `dbutils.fs.ls` and modification time
- Add audit columns: `Ingest_Timestamp` and `ingested_filename` (from `_metadata.file_name`)
- Add data quality flags (1 = problem, 0 = ok):
  - Null checks on year, airline, origin and origin state
  - `DepDelay` outside the range -120 to 1440 minutes
  - `Distance` outside the range 1 to 10,000
- Combine flags into `total_flag` and `dg_is_clean`, then report the clean-data percentage
- Read airport JSON, keep valid coordinates (latitude -90 to 90, longitude -180 to 180), round them and add `_load_ts_`
- Join flights with airports on `Origin` and `Dest` (left joins) and convert HHMM times to minutes after midnight
- Write Delta output to `Silver/flight_airport_delta` and `Silver/airport_delta`

### Silver: cleaning and enrichment

- Drop duplicates and rows with null `FlightDate`, `Origin` or `Dest`
- Standardise `Origin` and `Dest` (trim and uppercase)
- Boolean flags: `is_cancelled`, `is_diverted`, `is_dep_delayed`, `is_arr_delayed`, `is_weekend`
- `arr_delay_category` buckets (early, on time, minor delay, major delay)
- `sum_delay_cause`: total of carrier, weather, NAS, security and late-aircraft delay
- `absolute_delay`: difference between arrival delay and the sum of delay causes
- `cancelation_category`: maps cancellation code A/B/C/D to carrier, weather, NAS, security
- Origin and destination coordinates through broadcast joins with the airport lookup
- `haversine_distance` between origin and destination in km
- Write Delta output to `Silver/flight_cleaned` and `Silver/flight_final_delta`

### Gold: business aggregations

- Read `Silver/flight_final_delta`
- Aggregate into 4 analytical DataFrames (see below)
- Rank airlines per month with a window function (`row_number`)
- Push the 4 DataFrames to Snowflake with `write_pandas`

---

## Gold Datasets

| Snowflake table | Grain | Main metrics |
|---|---|---|
| `FLIGHT_SUMMARY_TABLE` | Year, month, airline | total, flown, cancelled, diverted and delayed flights; average delay; on-time %; cancellation rate; average delay by cause; distance; monthly rank by flights |
| `ROUTE_BASED_INSIGHTS` | Year, origin, destination | total, served, cancelled, diverted and delayed flights; average delay; on-time %; cancellation rate; average distance |
| `AIRPORT_MONTHLY_PERFORMANCE` | Year, month, origin airport | departures, cancelled departures, average departure delay, departure on-time %, average airtime, route distance, airlines operating, unique destinations |
| `DELAY_CAUSE_ANALYSIS` | Year, month, airline | delayed flights, total delay minutes, minutes and % of flights affected by carrier, weather, NAS, security and late-aircraft causes |

---

## Snowflake Data Model

**Database:** `DATABRICK_PROJECT_DB`

| Schema | Contents |
|---|---|
| `GOLD_SCHEMA` | The 4 Gold tables loaded from Databricks |
| `DIMENSION_MODELS` | 3 dimensions and 3 dynamic fact tables |
| `VIEWS_SCHEMA` | Reporting views for Power BI |

### Dimensions

| Table | Description |
|---|---|
| `Dim_origin` | One row per airport code, with surrogate key `origin_sk` |
| `Dim_Airline` | One row per airline code, with surrogate key `airline_sk` |
| `dim_date` | Calendar table from 2019-01-01 (day, week, month, quarter, year, weekend flag) |

### Fact tables (dynamic tables, 1 hour target lag)

| Table | Source | Joins to |
|---|---|---|
| `fact_airport_year_monthly` | `AIRPORT_MONTHLY_PERFORMANCE` | `Dim_origin` |
| `fact_airline_delay_cause` | `DELAY_CAUSE_ANALYSIS` | `Dim_Airline` |
| `fact_flight_summary` | `FLIGHT_SUMMARY_TABLE` | `Dim_Airline` |

```
          Dim_origin                    Dim_Airline
              │                         │        │
              ▼                         ▼        ▼
 fact_airport_year_monthly   fact_flight_summary   fact_airline_delay_cause
```

---

## Power BI Views

| View | Purpose |
|---|---|
| `vw_airline_performance` | Flights, cancellations, on-time % and delay minutes per airline per year |
| `vw_delay_trend_monthly` | On-time % and average delay per airline per month |
| `vw_airport_performance_map` | Airport metrics with latitude and longitude for map visuals |

**Dashboard coverage**
- Flight delays
- Cancellations
- On-time performance
- Route efficiency

> Add dashboard screenshots here: `![Dashboard](images/dashboard.png)`

---

## Repository Structure

```
.
├── notebooks/
│   ├── bronze.ipynb
│   ├── silver.ipynb
│   └── gold.ipynb
├── sql/
│   ├── 01_snowflake_setup.sql      # warehouse, database, schema, Gold tables
│   ├── 02_dimensional_model.sql    # dimensions and dynamic fact tables
│   └── 03_views.sql                # Power BI views
├── images/
│   ├── architecture.png
│   └── dashboard.png
└── README.md
```

---

## How to Run

**Prerequisites**
- Azure subscription with ADLS Gen2 and an Azure Databricks workspace (Unity Catalog enabled)
- Snowflake account
- Power BI Desktop

**Steps**

1. **Azure:** create the resource group, storage account and Databricks workspace. Create the Access Connector, assign *Storage Blob Data Contributor*, then add the storage credential and external location in Unity Catalog.
2. **Upload data:** place the flight CSV and `airports.json` in the `Landing` folder.
3. **Databricks:** run `bronze.ipynb`, then `silver.ipynb`, then `gold.ipynb` (up to the 4 Gold DataFrames).
4. **Snowflake setup:** run `sql/01_snowflake_setup.sql`.
5. **Load to Snowflake:** in Databricks, create the password widget and run the load cell.
   ```python
   dbutils.widgets.text("sf_password", "")
   ```
6. **Model:** run `sql/02_dimensional_model.sql`, one section at a time.
7. **Views:** run `sql/03_views.sql`.
8. **Power BI:** connect to Snowflake and import the views from `VIEWS_SCHEMA`.

**Before you publish this repo**
- Replace the Snowflake account, user and storage account names in the notebooks with placeholders
- Delete any cell that contains a real password
- Never run `CREATE OR REPLACE DATABASE` or `SCHEMA` after loading, it deletes the data

---

## Challenges and Fixes

| Problem | Cause | Fix |
|---|---|---|
| Secret scope not found in Databricks | Scope and key were never created | Create the scope and secret, or use a widget |
| `Invalid identifier` errors in Snowflake | `write_pandas` with `overwrite=True` rebuilds each table from the DataFrame columns (for example `YEAR`, `MONTH`, `REPORTING_AIRLINE`) | Use the real column names, or `SELECT * EXCLUDE (...)` in the fact tables |
| Tables empty after `CREATE OR REPLACE` | Replacing the database or schema wiped loaded data | Use `IF NOT EXISTS` and run setup before the load |
| Inflated totals in views | Joining facts to each other and to `dim_date` on year repeated rows | Aggregate each fact first, then join |
| Duplicate dimension rows | One airport or airline appeared with several names | Group by code and take one name |

---

## Key Learnings

- Medallion architecture separates raw ingestion, cleaning and business aggregation
- Unity Catalog and managed identities remove the need for storage keys in code
- Delta Lake gives reliable, overwrite-safe storage for each layer
- Data quality flags make the quality of each load measurable
- Snowflake dynamic tables keep fact tables fresh without manual refresh jobs
- Grain matters: joining at the wrong level multiplies rows and breaks totals

---

## Future Improvements

- Load multiple months of data and process only new files incrementally
- Join airport names so `origin_airport_name` is filled (it is currently null in the Gold airport table)
- Replace `write_pandas` with the Snowflake Spark connector for large volumes
- Orchestrate Bronze → Silver → Gold with Databricks Workflows
- Add automated data quality tests
- Use a dedicated Snowflake role instead of `ACCOUNTADMIN`
