-- 出典: BigQueryでGA4のページ別滞在時間を正しく集計する方法
-- 記事: articles/bigquery-ga4-page-time-on-page.md（セッション単位で滞在時間を集計する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_engagement AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    SUM(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec')
    ) AS total_engagement_msec
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'user_engagement'
  GROUP BY user_pseudo_id, ga_session_id
)
SELECT
  COUNT(*) AS sessions,
  ROUND(AVG(total_engagement_msec) / 1000, 1) AS avg_session_engagement_sec,
  ROUND(APPROX_QUANTILES(total_engagement_msec / 1000, 100)[OFFSET(50)], 1) AS median_session_engagement_sec
FROM session_engagement
WHERE total_engagement_msec > 0
