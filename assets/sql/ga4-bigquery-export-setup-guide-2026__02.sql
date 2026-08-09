-- 出典: GA4のBigQueryエクスポート完全設定ガイド【2026年版】
-- 記事: articles/ga4-bigquery-export-setup-guide-2026.md（流入元（メディア）を取得するクエリ例）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_20260328`
WHERE
  event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  event_count DESC
