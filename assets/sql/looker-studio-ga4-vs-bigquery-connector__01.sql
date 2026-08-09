-- 出典: Looker StudioのGA4コネクタとBigQueryコネクタの違いと使い分け
-- 記事: articles/looker-studio-ga4-vs-bigquery-connector.md（Looker Studioでの接続手順）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  device.category AS device,
  traffic_source.source AS source,
  traffic_source.medium AS medium,
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
GROUP BY
  date, device, source, medium
