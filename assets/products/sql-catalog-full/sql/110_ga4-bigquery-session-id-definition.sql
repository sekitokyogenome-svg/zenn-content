-- 110. GA4×BigQueryでセッションIDを正しく定義する方法（stagingビューとして定義する）
-- 用途: stagingビューとして定義する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `your-project.staging.stg_sessions` AS
SELECT
  event_date,
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_number') AS ga_session_number,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'page_location') AS landing_page,
  event_timestamp
FROM `${PROJECT}.${DATASET}.events_*`
WHERE event_name = 'session_start'
