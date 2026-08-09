-- 136. GA4×BigQueryのエクスポートが止まったときのトラブルシューティング（テーブルの作成日時と行数）
-- 用途: テーブルの作成日時と行数
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  table_name,
  creation_time,
  ROUND(total_rows / 1000, 1) AS rows_k,
  ROUND(total_logical_bytes / POW(1024, 2), 1) AS size_mb
FROM `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE table_name LIKE 'events_%'
ORDER BY table_name DESC
LIMIT 10
