-- 出典: BigQueryでGA4データをdbtで管理する入門
-- 記事: articles/bigquery-ga4-dbt-management-intro.md（stg_events.sql）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- models/staging/stg_events.sql

{{ config(materialized='view') }}

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  event_timestamp,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title') AS page_title,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
  collected_traffic_source.manual_source AS session_source,
  collected_traffic_source.manual_medium AS session_medium,
  device.category AS device_category,
  geo.country AS country
FROM {{ source('ga4_raw', 'events') }}
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
