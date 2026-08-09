-- GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順
-- 出典: articles/ga4-bigquery-looker-studio-ec-analytics-full.md

CREATE OR REPLACE TABLE `project.mart.mart_traffic` AS
SELECT
  session_date,
  source,
  medium,
  device_category,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT IF(has_purchase = 1, CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)), NULL)) AS converting_sessions,
  SUM(session_revenue) AS total_revenue
FROM `project.staging.stg_sessions`
GROUP BY session_date, source, medium, device_category
