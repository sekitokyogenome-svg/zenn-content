-- 出典: BigQueryでGA4のサンプリングを回避して正確な数値を出す
-- 記事: articles/ga4-bigquery-avoid-sampling.md（_TABLE_SUFFIXで期間を絞る）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 良い例：必要な期間だけスキャン
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'

-- 悪い例：全期間スキャン（コスト大）
FROM `${PROJECT}.${DATASET}.events_*`
