-- 出典: BigQueryでGA4データのコスト管理・クエリ最適化入門
-- 記事: articles/bigquery-ga4-cost-query-optimization.md（パターン1：_TABLE_SUFFIXを使わない）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 良い例：必要な期間だけスキャン
SELECT event_date, COUNT(*) AS events
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
GROUP BY event_date
ORDER BY event_date
