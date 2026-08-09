-- 20. GA4×BigQueryでセッションIDを正しく定義する方法（セッション開始時刻と流入元を紐づける）
-- 用途: セッション開始時刻と流入元を紐づける
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_starts AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_timestamp,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS landing_page
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
)
SELECT
  source,
  medium,
  COUNT(*) AS sessions,
  COUNT(DISTINCT session_id) AS unique_sessions
FROM session_starts
GROUP BY source, medium
ORDER BY sessions DESC
