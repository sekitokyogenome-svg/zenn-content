-- 出典: チャネル別ROASをBigQueryで集計してLooker Studioに可視化する
-- 記事: articles/bigquery-channel-roas-looker-studio.md（Step 1：チャネル別売上をBigQueryで集計する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- チャネル別の売上集計
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(
    IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)
  ) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  AND collected_traffic_source.manual_medium IS NOT NULL
GROUP BY
  month, medium, source
ORDER BY
  month, revenue DESC
