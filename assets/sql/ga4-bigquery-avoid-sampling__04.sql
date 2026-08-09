-- 出典: BigQueryでGA4のサンプリングを回避して正確な数値を出す
-- 記事: articles/ga4-bigquery-avoid-sampling.md（必要なカラムだけSELECTする）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 良い例：必要なカラムだけ取得
SELECT event_date, event_name, user_pseudo_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260330'

-- 悪い例：全カラム取得（コスト大）
SELECT *
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260330'
