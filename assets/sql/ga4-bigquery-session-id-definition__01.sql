-- 出典: GA4×BigQueryでセッションIDを正しく定義する方法
-- 記事: articles/ga4-bigquery-session-id-definition.md（ga_session_idはevent_paramsの中にある）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- ga_session_idの取り出し方
SELECT
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
LIMIT 10
