-- 出典: BigQueryのパーティション・クラスタリングでGA4クエリを高速化する
-- 記事: articles/bigquery-partition-clustering-ga4-optimization.md（確認方法2：INFORMATION_SCHEMAで確認）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  table_name,
  ROUND(total_logical_bytes / POW(1024, 3), 3) AS size_gb,
  ROUND(total_physical_bytes / POW(1024, 3), 3) AS physical_size_gb
FROM `your-project.mart.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE table_name LIKE 'mart_daily%'
