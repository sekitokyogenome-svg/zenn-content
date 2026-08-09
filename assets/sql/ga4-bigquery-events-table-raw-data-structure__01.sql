-- 出典: BigQueryでGA4の生データ構造を理解する【eventsテーブル解説】
-- 記事: articles/ga4-bigquery-events-table-raw-data-structure.md（event_paramsのUNNEST展開）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'page_location') AS page_location,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'engagement_time_msec') AS engagement_time_msec
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'page_view'
LIMIT 100
