-- 出典: GA4×BigQueryのエクスポートが止まったときのトラブルシューティング
-- 記事: articles/ga4-bigquery-export-stopped-troubleshoot.md（STEP 1：最新テーブルの日付を確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  table_id,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified
FROM `${PROJECT}.${DATASET}.__TABLES__`
WHERE table_id LIKE 'events_%'
ORDER BY table_id DESC
LIMIT 10
