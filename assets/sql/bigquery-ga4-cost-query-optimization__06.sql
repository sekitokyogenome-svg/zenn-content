-- 出典: BigQueryでGA4データのコスト管理・クエリ最適化入門
-- 記事: articles/bigquery-ga4-cost-query-optimization.md（テクニック2：必要なカラムだけSELECTする）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- event_paramsのサブクエリも、必要なキーだけ取り出す
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260330'
