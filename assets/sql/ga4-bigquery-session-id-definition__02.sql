-- 出典: GA4×BigQueryでセッションIDを正しく定義する方法
-- 記事: articles/ga4-bigquery-session-id-definition.md（user_pseudo_id + ga_session_idで一意なセッションIDを作る）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
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
  event_name,
  event_timestamp
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
ORDER BY session_id, event_timestamp
LIMIT 100
