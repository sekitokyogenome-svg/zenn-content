-- 115. BigQueryでGA4のページ別滞在時間を正しく集計する方法（engagement_time_msecをBigQueryで取得する）
-- 用途: engagement_time_msecをBigQueryで取得する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_name,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND event_name = 'user_engagement'
