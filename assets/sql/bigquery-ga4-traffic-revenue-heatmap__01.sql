-- 出典: BigQueryでGA4の流入経路×購入金額のヒートマップを作成した
-- 記事: articles/bigquery-ga4-traffic-revenue-heatmap.md（チャネル×デバイスのクロス集計SQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    device.category AS device_category,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
),

session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    -- チャネルグルーピング
    CASE
      WHEN medium = 'organic' THEN 'Organic Search'
      WHEN medium = 'cpc' THEN 'Paid Search'
      WHEN medium = 'social' THEN 'Social'
      WHEN medium = 'email' THEN 'Email'
      WHEN medium = 'referral' THEN 'Referral'
      WHEN medium = '(none)' OR medium IS NULL THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    device_category,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase', revenue, 0)) AS session_revenue
  FROM session_data
  GROUP BY user_pseudo_id, session_id, channel, device_category
)

SELECT
  channel,
  device_category,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(session_revenue), 0) AS total_revenue,
  ROUND(SUM(session_revenue) / COUNT(*), 0) AS revenue_per_session,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cvr
FROM session_summary
GROUP BY channel, device_category
ORDER BY total_revenue DESC
