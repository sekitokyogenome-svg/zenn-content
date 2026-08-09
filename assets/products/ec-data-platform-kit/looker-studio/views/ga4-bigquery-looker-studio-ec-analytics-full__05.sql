-- GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順
-- 出典: articles/ga4-bigquery-looker-studio-ec-analytics-full.md

CREATE OR REPLACE TABLE `project.mart.mart_funnel` AS
SELECT
  FORMAT_DATE('%Y-%m', session_date) AS month,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS total_sessions,
  COUNT(DISTINCT IF(has_view_item = 1, CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)), NULL)) AS view_item_sessions,
  COUNT(DISTINCT IF(has_add_to_cart = 1, CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)), NULL)) AS add_to_cart_sessions,
  COUNT(DISTINCT IF(has_purchase = 1, CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)), NULL)) AS purchase_sessions
FROM `project.staging.stg_sessions`
GROUP BY month
