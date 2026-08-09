-- 出典: BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする
-- 記事: articles/bigquery-struct-array-ga4-modeling.md（UNNESTでevent_paramsを展開する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- ページタイトルとセッションIDを同時に取得する例
SELECT
  event_date,
  user_pseudo_id,
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
  ) AS ga_session_id,
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'page_title'
  ) AS page_title,
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'page_location'
  ) AS page_location
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
  AND event_name = 'page_view'
