-- 408. BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする（STRUCT型とARRAY型の基本を理解する）
-- 用途: STRUCT型とARRAY型の基本を理解する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_name,
  event_params
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX = '20240801'
LIMIT 1
