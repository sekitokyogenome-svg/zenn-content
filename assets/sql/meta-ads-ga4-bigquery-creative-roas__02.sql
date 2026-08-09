-- 出典: Meta広告×GA4×BigQueryでクリエイティブ別ROASを深掘りする
-- 記事: articles/meta-ads-ga4-bigquery-creative-roas.md（クリエイティブ別ROASを算出するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH meta_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'content') AS creative_name,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND collected_traffic_source.manual_source = 'facebook'
    AND collected_traffic_source.manual_medium = 'paid_social'
),
session_summary AS (
  SELECT
    creative_name,
    campaign,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(CASE WHEN event_name = 'purchase' THEN revenue ELSE 0 END) AS total_revenue
  FROM meta_sessions
  WHERE creative_name IS NOT NULL
  GROUP BY creative_name, campaign
)
SELECT
  creative_name,
  campaign,
  sessions,
  purchases,
  total_revenue,
  ROUND(SAFE_DIVIDE(purchases, sessions) * 100, 2) AS cvr,
  ROUND(SAFE_DIVIDE(total_revenue, sessions), 0) AS revenue_per_session
FROM session_summary
ORDER BY total_revenue DESC;
