-- models/staging/stg_sessions.sql

{{ config(materialized='view') }}

WITH events AS (
  SELECT * FROM {{ ref('stg_events') }}
)

SELECT
  user_pseudo_id,
  ga_session_id,
  MIN(event_date) AS session_date,
  MIN(event_timestamp) AS session_start_timestamp,
  session_source,
  session_medium,
  device_category,
  country,
  COUNTIF(event_name = 'page_view') AS page_views,
  SUM(COALESCE(engagement_time_msec, 0)) AS total_engagement_msec,
  MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
FROM events
GROUP BY
  user_pseudo_id,
  ga_session_id,
  session_source,
  session_medium,
  device_category,
  country
