-- models/mart/mart_traffic.sql

{{ config(materialized='table') }}

WITH sessions AS (
  SELECT * FROM {{ ref('stg_sessions') }}
)

SELECT
  session_date AS event_date,
  IFNULL(session_medium, '(none)') AS medium,
  device_category,
  COUNT(*) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  SUM(page_views) AS page_views,
  ROUND(AVG(total_engagement_msec) / 1000, 1) AS avg_engagement_sec,
  SUM(has_purchase) AS purchases,
  ROUND(SAFE_DIVIDE(SUM(has_purchase), COUNT(*)) * 100, 2) AS cvr_pct
FROM sessions
GROUP BY event_date, medium, device_category
