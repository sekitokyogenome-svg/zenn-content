-- 346. GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順（stg_sessions（セッション単位の集約））
-- 用途: stg_sessions（セッション単位の集約）
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `project.staging.stg_sessions` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS session_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  device.category AS device_category,
  MAX(IF(event_name = 'session_start', 1, 0)) AS is_session_start,
  MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
  MAX(IF(event_name = 'add_to_cart', 1, 0)) AS has_add_to_cart,
  MAX(IF(event_name = 'view_item', 1, 0)) AS has_view_item,
  SUM(ecommerce.purchase_revenue) AS session_revenue
FROM `${PROJECT}.${DATASET}.events_*`
GROUP BY
  event_date, user_pseudo_id, ga_session_id,
  source, medium, device_category
