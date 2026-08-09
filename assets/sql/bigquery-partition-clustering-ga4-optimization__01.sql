-- 出典: BigQueryのパーティション・クラスタリングでGA4クエリを高速化する
-- 記事: articles/bigquery-partition-clustering-ga4-optimization.md（GA4エクスポートテーブルの構造を理解する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
