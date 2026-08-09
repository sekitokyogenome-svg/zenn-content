-- 出典: BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）
-- 記事: articles/ga4-bigquery-bounce-rate-calculation.md（BigQueryでエンゲージメント情報を取得する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- エンゲージメント情報の確認
SELECT
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'session_engaged') AS session_engaged,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'engagement_time_msec') AS engagement_time_msec
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
LIMIT 20
