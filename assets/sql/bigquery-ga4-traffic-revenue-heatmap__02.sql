-- 出典: BigQueryでGA4の流入経路×購入金額のヒートマップを作成した
-- 記事: articles/bigquery-ga4-traffic-revenue-heatmap.md（チャネル×地域のクロス集計SQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    CASE
      WHEN collected_traffic_source.manual_medium = 'organic' THEN 'Organic Search'
      WHEN collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN collected_traffic_source.manual_medium = 'social' THEN 'Social'
      WHEN collected_traffic_source.manual_medium = 'email' THEN 'Email'
      WHEN collected_traffic_source.manual_medium = 'referral' THEN 'Referral'
      WHEN collected_traffic_source.manual_medium = '(none)'
        OR collected_traffic_source.manual_medium IS NULL THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    geo.region AS region,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND geo.country = 'Japan'
),

session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    channel,
    region,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase', revenue, 0)) AS session_revenue
  FROM session_data
  GROUP BY user_pseudo_id, session_id, channel, region
)

SELECT
  channel,
  region,
  COUNT(*) AS sessions,
  ROUND(SUM(session_revenue), 0) AS total_revenue,
  ROUND(SUM(session_revenue) / NULLIF(COUNT(*), 0), 0) AS revenue_per_session
FROM session_summary
GROUP BY channel, region
HAVING sessions >= 10
ORDER BY total_revenue DESC
