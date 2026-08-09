-- 出典: BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする
-- 記事: articles/bigquery-struct-array-ga4-modeling.md（UNNESTでevent_paramsを展開する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- ga_session_idをevent_paramsから取得する例
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
  ) AS ga_session_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
  AND event_name = 'page_view'
