-- BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする
-- 用途: UNNESTでevent_paramsを展開する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
