-- 出典: GA4×BigQueryのエクスポートが止まったときのトラブルシューティング
-- 記事: articles/ga4-bigquery-export-stopped-troubleshoot.md（直近のテーブル作成状況をチェック）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  table_name,
  creation_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), creation_time, HOUR) AS hours_ago
FROM `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.TABLES`
WHERE table_name LIKE 'events_%'
ORDER BY creation_time DESC
LIMIT 5
