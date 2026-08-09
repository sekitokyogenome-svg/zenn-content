-- 455. Google広告のオフラインコンバージョンをBigQuery経由で自動化する（GA4 BigQueryエクスポートからGCLIDを取得する）
-- 用途: GA4 BigQueryエクスポートからGCLIDを取得する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  user_pseudo_id,
  event_date,
  event_timestamp,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'gclid') AS gclid,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'session_start'
  AND collected_traffic_source.manual_medium = 'cpc'
