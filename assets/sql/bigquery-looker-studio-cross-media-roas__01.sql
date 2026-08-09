-- 出典: BigQuery × Looker Studioで広告媒体横断ROASダッシュボードを構築する全手順
-- 記事: articles/bigquery-looker-studio-cross-media-roas.md（2. GA4 BigQueryエクスポートからROAS計算に必要なデータを取得する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
GROUP BY
  1, 2, 3
ORDER BY
  date DESC
