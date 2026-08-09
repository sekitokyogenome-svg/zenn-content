-- 出典: GA4イベントパラメータをUNNESTで展開するSQLパターン集
-- 記事: articles/ga4-bigquery-unnest-sql-patterns.md（パターン5：user_propertiesを展開する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(user_properties) WHERE key = 'first_open_time') AS first_open_time,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'user_tier') AS user_tier
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
