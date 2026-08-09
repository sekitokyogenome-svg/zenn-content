-- 出典: BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする
-- 記事: articles/bigquery-struct-array-ga4-modeling.md（STRUCT型とARRAY型の基本を理解する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- event_paramsの構造イメージ（スキーマ確認用）
SELECT
  event_name,
  event_params
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX = '20240801'
LIMIT 1
