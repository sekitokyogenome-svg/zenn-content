-- 出典: GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け
-- 記事: articles/ga4-bigquery-streaming-vs-daily-export.md（流入元の取得方法）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(*) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC;
