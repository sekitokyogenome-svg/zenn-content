-- GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順
-- 出典: articles/ga4-bigquery-looker-studio-ec-analytics-full.md

CREATE OR REPLACE VIEW `project.staging.stg_events` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  event_timestamp,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title') AS page_title,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  device.category AS device_category,
  geo.country AS country,
  ecommerce.purchase_revenue AS purchase_revenue,
  ecommerce.transaction_id AS transaction_id
FROM `${PROJECT}.${DATASET}.events_*`
