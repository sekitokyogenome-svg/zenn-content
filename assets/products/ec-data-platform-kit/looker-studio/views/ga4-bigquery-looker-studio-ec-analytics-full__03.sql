-- GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順
-- 出典: articles/ga4-bigquery-looker-studio-ec-analytics-full.md

CREATE OR REPLACE VIEW `project.staging.stg_purchases` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  ecommerce.transaction_id,
  ecommerce.purchase_revenue,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  device.category AS device_category
FROM `${PROJECT}.${DATASET}.events_*`
WHERE event_name = 'purchase'
  AND ecommerce.transaction_id IS NOT NULL
