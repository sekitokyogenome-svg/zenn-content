-- 出典: GA4×BigQueryでメルマガのROIを正確に測定する
-- 記事: articles/ga4-bigquery-email-marketing-roi.md（メルマガ流入セッションを特定するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH email_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_campaign AS campaign,
    event_name,
    event_timestamp,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'email'
)

SELECT
  campaign,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(session_id AS STRING))) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  ROUND(SUM(IF(event_name = 'purchase', revenue, 0)), 0) AS total_revenue,
  ROUND(
    COUNTIF(event_name = 'purchase')
    / COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(session_id AS STRING))) * 100,
    2
  ) AS cvr
FROM email_sessions
GROUP BY campaign
ORDER BY total_revenue DESC
