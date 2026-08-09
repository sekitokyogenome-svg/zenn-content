-- 出典: BigQueryでGA4データのコスト管理・クエリ最適化入門
-- 記事: articles/bigquery-ga4-cost-query-optimization.md（パターン2：SELECT * を使う）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 良い例：必要なカラムだけ指定
SELECT event_date, event_name, user_pseudo_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260330'
LIMIT 100
