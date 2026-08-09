-- 出典: BigQueryでGA4のサンプリングを回避して正確な数値を出す
-- 記事: articles/ga4-bigquery-avoid-sampling.md（_TABLE_SUFFIXで期間を絞る）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT COUNT(*) AS events
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
